%% @doc The departments together on a REAL store: a reckon-db store, evoq
%% dispatching to the repo aggregate, the projection filling the read model,
%% and the procedures answering from it. Nothing is mocked except the one
%% thing that leaves the node, the mesh announcement of a push.
%%
%% This is the path the unit suites cannot see: evoq's event shapes on the
%% way back out of the store, the aggregate replaying them, and a push
%% recorded through the aggregate's owner rule and projected.
-module(mcl_git_store_tests).

-include_lib("eunit/include/eunit.hrl").

-define(OWNER_KEY, <<16#aa, 0:248>>).
-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).
-define(OTHER_KEY, <<16#bb, 0:248>>).
-define(ZERO, <<"0000000000000000000000000000000000000000">>).

store_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(C) -> [{timeout, 120, fun() -> lifecycle(C) end}] end}.

setup() ->
    Root = filename:join("/tmp", "mcl_git_store_tests_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Root),
    %% Loaded first: an application's .app env overwrites a set_env made
    %% before it loads, and evoq's names `default_store'.
    [ok = application:load(A) || A <- [evoq, reckon_evoq]],
    ok = application:set_env(evoq, event_store_adapter, reckon_evoq_adapter),
    ok = application:set_env(evoq, subscription_adapter, reckon_evoq_adapter),
    ok = application:set_env(evoq, snapshot_store_adapter, reckon_evoq_adapter),
    ok = application:set_env(evoq, store_id, mcl_git_store),
    ok = application:set_env(serve_git_over_mesh, repo_root, filename:join(Root, "repos")),
    {ok, Started} = application:ensure_all_started([reckon_db, evoq, reckon_evoq]),
    ok = mcl_om_store:ensure(mcl_git_store, filename:join(Root, "store")),
    ok = git_slots:init(4),
    meck:new(refs_fact, [passthrough]),
    meck:expect(refs_fact, publish, fun(_) -> ok end),
    {ok, Prj} = project_repos_sup:start_link(),
    {ok, Cmd} = guide_repo_lifecycle_sup:start_link(),
    [unlink(P) || P <- [Prj, Cmd]],
    #{root => Root, sups => [Prj, Cmd], started => Started}.

cleanup(#{root := Root, sups := Sups, started := Started}) ->
    [exit(P, shutdown) || P <- Sups],
    meck:unload(),
    [application:stop(A) || A <- lists:reverse(Started)],
    os:cmd("rm -rf '" ++ Root ++ "'").

lifecycle(#{root := Root}) ->
    %% Initiate through the real dispatcher; the row appears once projected.
    {reply, #{repo_id := {text, RepoId}}} =
        call(initiate_repo_responder, #{name => <<"dotfiles">>, visibility => <<"public">>},
             ?OWNER_KEY, [?OWNER]),
    Row = eventually(fun() -> project_repos_store:get(RepoId) end),
    ?assertMatch(#{owner := ?OWNER, name := <<"dotfiles">>, status := <<"active">>}, Row),

    %% The owner pushes; the push is recorded through the aggregate and projected.
    Head = commit(Root),
    Pack = pack(Root, Head),
    Request = git_push:request([#{ref => <<"refs/heads/main">>, old_oid => ?ZERO, new_oid => Head}], Pack),
    {reply, #{stdout := Report}} = call(receive_pack_responder, #{repo_id => RepoId, stdin => Request},
                                        ?OWNER_KEY, []),
    ?assertEqual({ok, [{<<"refs/heads/main">>, ok}]}, git_push:parse_report(Report)),
    eventually(fun() -> pushed(project_repos_store:get(RepoId)) end),
    eventually(fun() -> announced(RepoId) end),

    %% Anyone may look it up and clone it; only the owner may rename it.
    {reply, #{stdout := Listed}} = call(upload_pack_responder,
                                        #{repo_id => RepoId, stdin => git_v2:ls_refs_request()},
                                        ?OTHER_KEY, []),
    {ok, Refs} = git_v2:parse_ls_refs(Listed),
    ?assert(lists:member(#{name => <<"refs/heads/main">>, oid => Head, symref_target => undefined}, Refs)),
    ?assertEqual({error, not_owner},
                 call(rename_repo_responder, #{repo_id => RepoId, new_name => <<"mine">>}, ?OTHER_KEY, [])),
    {reply, _} = call(rename_repo_responder, #{repo_id => RepoId, new_name => <<"config">>}, ?OWNER_KEY, []),
    eventually(fun() -> renamed(project_repos_store:get(RepoId)) end),

    %% Archived, it refuses the owner's push too, but can still be read.
    {reply, _} = call(archive_repo_responder, #{repo_id => RepoId}, ?OWNER_KEY, []),
    eventually(fun() -> archived(project_repos_store:get(RepoId)) end),
    ?assertEqual({error, archived},
                 call(receive_pack_responder, #{repo_id => RepoId, advertise => 1}, ?OWNER_KEY, [])),
    ?assertMatch({reply, _}, call(get_repo_by_id_responder, #{repo_id => RepoId}, ?OTHER_KEY, [])).

pushed({ok, #{last_pushed_at := At}}) when is_integer(At) -> {ok, At};
pushed(_) -> not_yet.

renamed({ok, #{name := <<"config">>}} = R) -> R;
renamed(_) -> not_yet.

archived({ok, #{status := <<"archived">>}} = R) -> R;
archived(_) -> not_yet.

announced(RepoId) ->
    case [D || {_, {refs_fact, publish, [D]}, _} <- meck:history(refs_fact),
               mcl_om_wire:field(repo_id, D) =:= RepoId] of
        [_ | _] -> {ok, announced};
        []      -> not_yet
    end.

call(Mod, Payload, Caller, Initiators) ->
    ok = application:set_env(guide_repo_lifecycle, initiators, Initiators),
    {ok, S} = Mod:init([]),
    case Mod:handle_request(Payload#{caller => Caller}, S) of
        {reply, R, _} -> {reply, R};
        {error, E, _} -> {error, E}
    end.

eventually(F) -> eventually(F, 100).

eventually(F, 0) -> error({never, F()});
eventually(F, N) ->
    case F() of
        {ok, V} -> V;
        _       -> timer:sleep(50), eventually(F, N - 1)
    end.

commit(Root) ->
    Work = filename:join(Root, "work"),
    git(["init", "--quiet", "--initial-branch=main", Work]),
    ok = file:write_file(filename:join(Work, "README"), <<"hi\n">>),
    git(["-C", Work, "add", "README"]),
    git(["-C", Work, "commit", "--quiet", "-m", "first"]),
    list_to_binary(string:trim(git(["-C", Work, "rev-parse", "HEAD"]))).

pack(Root, Head) ->
    {ok, #{exit_status := 0, stdout := Pack}} =
        git_exec:run(os:find_executable("git"),
                     ["-C", filename:join(Root, "work"), "pack-objects", "--stdout", "--revs", "--quiet"],
                     <<Head/binary, "\n">>, [], 30000),
    Pack.

git(Args) ->
    {ok, #{exit_status := 0, stdout := Out}} =
        git_exec:run(os:find_executable("git"), Args, <<>>,
                     [{"GIT_AUTHOR_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@t"},
                      {"GIT_COMMITTER_NAME", "t"}, {"GIT_COMMITTER_EMAIL", "t@t"}], 30000),
    binary_to_list(Out).
