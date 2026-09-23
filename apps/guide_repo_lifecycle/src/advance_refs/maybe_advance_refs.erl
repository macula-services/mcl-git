%% @doc Handler for advance_refs_v1.
-module(maybe_advance_refs).

-export([handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]}.
handle_from_map(Payload) -> {ok, [refs_advanced_v1:new(Payload)]}.

-spec dispatch(map()) -> ok | {error, term()}.
dispatch(Params) ->
    repo_commands:dispatch(advance_refs_v1, Params).
