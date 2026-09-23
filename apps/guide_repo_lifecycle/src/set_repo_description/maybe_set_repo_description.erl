%% @doc Handler for set_repo_description_v1.
-module(maybe_set_repo_description).

-export([handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]}.
handle_from_map(Payload) -> {ok, [repo_description_set_v1:new(Payload)]}.

-spec dispatch(map()) -> ok | {error, term()}.
dispatch(Params) ->
    repo_commands:dispatch(set_repo_description_v1, Params).
