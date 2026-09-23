%% @doc Command: initiate_repo_v1 -- opens a repository's dossier.
-module(initiate_repo_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, from_map/1]).
-export([repo_id/1]).

-record(initiate_repo_v1, {
    repo_id        :: binary(),
    name           :: binary(),
    owner          :: binary(),
    description    :: binary(),
    default_branch :: binary(),
    visibility     :: binary(),
    tags           :: [binary()]
}).

-opaque t() :: #initiate_repo_v1{}.
-export_type([t/0]).

command_type() -> initiate_repo.

%% Mints the repo id here, via reckon_gater_stream_id:new/1, never from the
%% caller: the id is a valid stream id from the moment it exists, and a caller
%% cannot choose one that collides with somebody else's repository. `owner' is
%% the wire-authenticated caller, never a payload field (see
%% initiate_repo_responder).
-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{name := Name, owner := Owner} = Params)
  when is_binary(Name), Name =/= <<>>, is_binary(Owner), Owner =/= <<>> ->
    visible(maps:get(visibility, Params, <<"private">>), Name, Owner, Params);
new(_) ->
    {error, name_and_owner_required}.

visible(Visibility, Name, Owner, Params)
  when Visibility =:= <<"public">>; Visibility =:= <<"private">> ->
    typed(check(Params), #initiate_repo_v1{
        repo_id        = reckon_gater_stream_id:new(<<"repo">>),
        name           = Name,
        owner          = Owner,
        description    = maps:get(description, Params, <<>>),
        default_branch = maps:get(default_branch, Params, <<"main">>),
        visibility     = Visibility,
        tags           = maps:get(tags, Params, [])
    });
visible(_Other, _Name, _Owner, _Params) ->
    {error, invalid_visibility}.

%% Every stored field typed: the event cannot be undone, and a default branch
%% that is not a ref name would leave a repository nothing can ever create.
check(Params) ->
    first_refusal([branch(maps:get(default_branch, Params, <<"main">>)),
                   description(maps:get(description, Params, <<>>)),
                   tags(maps:get(tags, Params, []))]).

branch(B) when is_binary(B) ->
    branch_shape(re:run(B, <<"^[A-Za-z0-9_][A-Za-z0-9._/-]{0,199}$">>, [dollar_endonly, {capture, none}]));
branch(_) ->
    {error, invalid_default_branch}.

branch_shape(match)   -> ok;
branch_shape(nomatch) -> {error, invalid_default_branch}.

description(D) when is_binary(D) -> ok;
description(_)                   -> {error, invalid_description}.

tags(Tags) when is_list(Tags) -> all_binaries(lists:all(fun erlang:is_binary/1, Tags));
tags(_)                       -> {error, invalid_tags}.

all_binaries(true)  -> ok;
all_binaries(false) -> {error, invalid_tags}.

first_refusal(Checks) -> first([C || {error, _} = C <- Checks]).

first([])        -> ok;
first([Err | _]) -> Err.

typed(ok, Cmd)             -> {ok, Cmd};
typed({error, _} = Err, _) -> Err.

-spec to_map(t()) -> map().
to_map(#initiate_repo_v1{} = C) ->
    #{command_type   => command_type(),
      repo_id        => C#initiate_repo_v1.repo_id,
      name           => C#initiate_repo_v1.name,
      owner          => C#initiate_repo_v1.owner,
      description    => C#initiate_repo_v1.description,
      default_branch => C#initiate_repo_v1.default_branch,
      visibility     => C#initiate_repo_v1.visibility,
      tags           => C#initiate_repo_v1.tags}.

-spec from_map(map()) -> {ok, t()} | {error, term()}.
from_map(#{repo_id := Id, name := Name, owner := Owner, description := Desc,
           default_branch := Branch, visibility := Vis, tags := Tags}) ->
    {ok, #initiate_repo_v1{repo_id = Id, name = Name, owner = Owner,
                           description = Desc, default_branch = Branch,
                           visibility = Vis, tags = Tags}};
from_map(_) ->
    {error, invalid_initiate_repo}.

-spec repo_id(t()) -> binary().
repo_id(#initiate_repo_v1{repo_id = V}) -> V.
