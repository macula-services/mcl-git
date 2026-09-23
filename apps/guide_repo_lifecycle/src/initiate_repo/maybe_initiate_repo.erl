%% @doc Handler for initiate_repo_v1: builds the event (from the aggregate's
%% execute/2) and dispatches the command (from the mesh responder).
-module(maybe_initiate_repo).

-export([handle_from_map/1, dispatch/1]).

-spec handle_from_map(map()) -> {ok, [map()]} | {error, term()}.
handle_from_map(Payload) ->
    handled(initiate_repo_v1:from_map(Payload)).

handled({ok, Cmd})         -> {ok, [repo_initiated_v1:new(initiate_repo_v1:to_map(Cmd))]};
handled({error, _} = Err)  -> Err.

%% @doc Mint and dispatch. Returns the minted repo id, which is what the
%% caller clones by.
-spec dispatch(map()) -> {ok, binary()} | {error, term()}.
dispatch(Params) ->
    dispatched(initiate_repo_v1:new(Params)).

dispatched({ok, Cmd}) ->
    RepoId = initiate_repo_v1:repo_id(Cmd),
    Evoq = evoq_command:new(initiate_repo, repo_aggregate, repo_aggregate:stream_id(RepoId),
                            initiate_repo_v1:to_map(Cmd)),
    minted(evoq_router:dispatch(Evoq), RepoId);
dispatched({error, _} = Err) ->
    Err.

minted({ok, _Version, _Events}, RepoId) -> {ok, RepoId};
minted({error, _} = Err, _RepoId)       -> Err.
