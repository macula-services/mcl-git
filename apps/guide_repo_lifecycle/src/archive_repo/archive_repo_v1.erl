%% @doc Command: archive_repo_v1 -- the owner retires the repository for good.
-module(archive_repo_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, repo_id/1]).

-record(archive_repo_v1, {repo_id :: binary(), caller :: binary(), reason :: binary()}).

-opaque t() :: #archive_repo_v1{}.
-export_type([t/0]).

command_type() -> archive_repo.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{repo_id := Id, caller := Caller} = Params) when is_binary(Id), is_binary(Caller) ->
    {ok, #archive_repo_v1{repo_id = Id, caller = Caller,
                          reason = maps:get(reason, Params, <<>>)}};
new(_) ->
    {error, invalid_archive_repo}.

-spec to_map(t()) -> map().
to_map(#archive_repo_v1{repo_id = Id, caller = Caller, reason = Reason}) ->
    #{command_type => command_type(), repo_id => Id, caller => Caller, reason => Reason}.

-spec repo_id(t()) -> binary().
repo_id(#archive_repo_v1{repo_id = V}) -> V.
