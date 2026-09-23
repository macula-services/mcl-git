%% @doc Command: rename_repo_v1 -- the owner gives a repository a new name.
-module(rename_repo_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, repo_id/1]).

-record(rename_repo_v1, {repo_id :: binary(), caller :: binary(), new_name :: binary()}).

-opaque t() :: #rename_repo_v1{}.
-export_type([t/0]).

command_type() -> rename_repo.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{repo_id := Id, caller := Caller, new_name := Name})
  when is_binary(Id), is_binary(Caller), is_binary(Name), Name =/= <<>> ->
    {ok, #rename_repo_v1{repo_id = Id, caller = Caller, new_name = Name}};
new(_) ->
    {error, invalid_rename_repo}.

-spec to_map(t()) -> map().
to_map(#rename_repo_v1{repo_id = Id, caller = Caller, new_name = Name}) ->
    #{command_type => command_type(), repo_id => Id, caller => Caller, new_name => Name}.

-spec repo_id(t()) -> binary().
repo_id(#rename_repo_v1{repo_id = V}) -> V.
