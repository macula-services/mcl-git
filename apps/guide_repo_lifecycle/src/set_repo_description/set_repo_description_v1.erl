%% @doc Command: set_repo_description_v1 -- the owner describes the repository.
-module(set_repo_description_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, repo_id/1]).

-record(set_repo_description_v1, {repo_id :: binary(), caller :: binary(),
                                  description :: binary()}).

-opaque t() :: #set_repo_description_v1{}.
-export_type([t/0]).

command_type() -> set_repo_description.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{repo_id := Id, caller := Caller, description := Desc})
  when is_binary(Id), is_binary(Caller), is_binary(Desc) ->
    {ok, #set_repo_description_v1{repo_id = Id, caller = Caller, description = Desc}};
new(_) ->
    {error, invalid_set_repo_description}.

-spec to_map(t()) -> map().
to_map(#set_repo_description_v1{repo_id = Id, caller = Caller, description = Desc}) ->
    #{command_type => command_type(), repo_id => Id, caller => Caller, description => Desc}.

-spec repo_id(t()) -> binary().
repo_id(#set_repo_description_v1{repo_id = V}) -> V.
