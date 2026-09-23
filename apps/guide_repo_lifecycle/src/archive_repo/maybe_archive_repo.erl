%% @doc Handler for archive_repo_v1.
-module(maybe_archive_repo).

-export([handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]}.
handle_from_map(Payload) -> {ok, [repo_archived_v1:new(Payload)]}.

-spec dispatch(map()) -> ok | {error, term()}.
dispatch(Params) ->
    repo_commands:dispatch(archive_repo_v1, Params).
