%% @doc Procedure `mcl-git/receive_pack': a push, through `git receive-pack
%% --stateless-rpc'. Only the repository's owner may push, and never to an
%% archived repository.
%%
%% Payload: `repo_id', and either `advertise' = 1 (the ref advertisement a
%% push starts from) or `stdin', the update commands and pack exactly as
%% git's client side writes them.
%%
%% git moves the refs on disk; this desk then records which refs moved, from
%% where to where, as advance_refs_v1 on the repo's dossier. It reads the
%% refs before and after, holding a per-repository lock so two pushes cannot
%% be attributed one another's changes. A failure to RECORD cannot undo what
%% git already did, so it is logged as an error rather than refused.
-module(receive_pack_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

-define(ZERO, <<"0000000000000000000000000000000000000000">>).

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    served(served_repo:resolve(Payload, may_write), Payload, State).

served({ok, RepoId, Dir, Caller}, Payload, State) ->
    replied(run(mcl_om_wire:field(advertise, Payload, 0), RepoId, Dir, Caller, Payload),
            RepoId, State);
served({error, Why}, _Payload, State) ->
    {error, Why, State}.

replied({error, Why}, _RepoId, State) when is_atom(Why) -> {error, Why, State};
replied(Result, RepoId, State) -> git_reply:answer(Result, RepoId, State).

run(1, _RepoId, Dir, _Caller, _Payload) ->
    bare_repo:git(["receive-pack", "--stateless-rpc", "--advertise-refs", Dir], <<>>, []);
run(_Push, RepoId, _Dir, _Caller, Payload) ->
    global:trans({{mcl_git_push, RepoId}, self()},
                 fun() -> locked(served_repo:resolve(Payload, may_write), Payload) end, [node()]).

%% Checked again under the lock: an archive or a change of hands that landed
%% since the first check refuses the push before git touches the disk. What
%% remains is an archive between this check and git finishing, which leaves
%% the push on disk, unrecorded and logged.
locked({ok, RepoId, Dir, Caller}, Payload) ->
    pushed(RepoId, Dir, Caller, mcl_om_wire:field(stdin, Payload, <<>>));
locked({error, _} = Refused, _Payload) ->
    Refused.

pushed(RepoId, Dir, Caller, Stdin) ->
    around(bare_repo:refs(Dir), RepoId, Dir, Caller, Stdin).

around({ok, Before}, RepoId, Dir, Caller, Stdin) ->
    Result = bare_repo:git(["receive-pack", "--stateless-rpc", Dir], Stdin, []),
    ok = record_after(bare_repo:refs(Dir), Before, RepoId, Caller),
    Result;
around({error, _} = Err, _RepoId, _Dir, _Caller, _Stdin) ->
    Err.

record_after({ok, After}, Before, RepoId, Caller) ->
    record(advances(Before, After), RepoId, Caller);
record_after({error, Why}, _Before, RepoId, _Caller) ->
    logger:error("[mcl_git] ~s: could not read the refs after a push, nothing recorded: ~p",
                 [RepoId, Why]),
    ok.

%% Every ref whose object changed, including ones created (old = zero) and
%% ones removed (new = zero), in ref order.
advances(Before, After) ->
    Names = lists:usort(maps:keys(Before) ++ maps:keys(After)),
    [#{ref => N, old_oid => maps:get(N, Before, ?ZERO), new_oid => maps:get(N, After, ?ZERO)}
     || N <- Names, maps:get(N, Before, ?ZERO) =/= maps:get(N, After, ?ZERO)].

record([], _RepoId, _Caller) ->
    ok;
record(Advances, RepoId, Caller) ->
    recorded(maybe_advance_refs:dispatch(#{repo_id => RepoId, caller => Caller,
                                           advances => Advances}), RepoId, Advances).

recorded(ok, _RepoId, _Advances) ->
    ok;
recorded({error, Why}, RepoId, Advances) ->
    logger:error("[mcl_git] ~s: git moved ~p but recording it failed: ~p",
                 [RepoId, Advances, Why]),
    ok.
