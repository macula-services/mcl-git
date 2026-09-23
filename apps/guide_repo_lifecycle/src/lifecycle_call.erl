%% @doc The shape every lifecycle procedure shares: no wire-authenticated
%% caller, no command; otherwise build the command's parameters (the caller
%% always from the wire, never from the payload), dispatch, and answer.
-module(lifecycle_call).

-export([answer/4]).

-spec answer(map() | term(), fun((binary()) -> map()), fun((map()) -> term()), term()) ->
    {reply, map(), term()} | {error, term(), term()}.
answer(Payload, Params, Dispatch, State) ->
    identified(repo_caller:id(Payload), Params, Dispatch, State).

identified(undefined, _Params, _Dispatch, State) ->
    {error, unauthenticated, State};
identified(Caller, Params, Dispatch, State) ->
    replied(Dispatch(Params(Caller)), State).

replied(ok, State)            -> {reply, #{status => {text, <<"accepted">>}}, State};
replied({ok, RepoId}, State)  -> {reply, #{repo_id => {text, RepoId}}, State};
replied({error, Why}, State)  -> {error, Why, State}.

