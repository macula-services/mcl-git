%% @doc The two git procedures, driven exactly as macula_response drives
%% them (init/1, then handle_request/2 with the caller merged into the
%% payload), against real bare repositories. meck stands in for the read
%% model and for the command dispatch, so each test sees exactly what a
%% desk decided and what it recorded.
-module(serve_git_over_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

%% A caller arrives as its 32-byte node key id; the read model keeps the
%% owner as lowercase hex.
-define(OWNER_KEY, <<16#aa, 0:248>>).
-define(STRANGER_KEY, <<16#bb, 0:248>>).
-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).
-define(REPO, <<"repo-0190aaaabbbbccccddddeeeeffff0000">>).
-define(ZERO, <<"0000000000000000000000000000000000000000">>).

serve_test_() ->
    {foreach, fun setup/0, fun cleanup/1,
     [fun(C) -> {timeout, 60, fun() -> owner_pushes_then_anyone_clones_public(C) end} end,
      fun(C) -> {timeout, 60, fun() -> stranger_cannot_push(C) end} end,
      fun(C) -> {timeout, 60, fun() -> stranger_cannot_see_private(C) end} end,
      fun(C) -> {timeout, 60, fun() -> archived_refuses_push(C) end} end,
      fun(C) -> {timeout, 60, fun() -> unknown_repo_is_not_found(C) end} end,
      fun(C) -> {timeout, 60, fun() -> refused_push_records_nothing(C) end} end]}.

setup() ->
    Root = filename:join("/tmp", "serve_git_tests_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Root),
    application:set_env(serve_git_over_mesh, repo_root, filename:join(Root, "repos")),
    Work = filename:join(Root, "work"),
    git(["init", "--quiet", "--initial-branch=main", Work]),
    ok = file:write_file(filename:join(Work, "README"), <<"hello\n">>),
    git(["-C", Work, "add", "README"]),
    git(["-C", Work, "commit", "--quiet", "-m", "first"]),
    Head = list_to_binary(string:trim(git(["-C", Work, "rev-parse", "HEAD"]))),
    ok = git_slots:init(4),
    meck:new(project_repos_store, [non_strict]),
    meck:new(maybe_advance_refs, [non_strict]),
    meck:expect(maybe_advance_refs, dispatch, fun(_) -> ok end),
    row(<<"public">>, <<"active">>),
    #{root => Root, work => Work, head => Head}.

cleanup(#{root := Root}) ->
    meck:unload(),
    application:unset_env(serve_git_over_mesh, repo_root),
    os:cmd("rm -rf '" ++ Root ++ "'").

row(Visibility, Status) ->
    meck:expect(project_repos_store, get,
                fun(?REPO) -> {ok, #{repo_id => ?REPO, owner => ?OWNER, visibility => Visibility,
                                     status => Status, default_branch => <<"main">>}};
                   (_)     -> {error, not_found}
                end).

owner_pushes_then_anyone_clones_public(#{work := Work, head := Head, root := Root}) ->
    {reply, #{stdout := Adv}} = receive_pack(#{repo_id => ?REPO, advertise => 1}, ?OWNER_KEY),
    {ok, [], _Caps} = git_push:parse_advertisement(Adv),
    {reply, #{stdout := Report}} = receive_pack(#{repo_id => ?REPO, stdin => push_request(Work, Head)}, ?OWNER_KEY),
    ?assertEqual({ok, [{<<"refs/heads/main">>, ok}]}, git_push:parse_report(Report)),
    %% The push is recorded, with the refs it moved and who moved them.
    ?assert(meck:called(maybe_advance_refs, dispatch,
                        [#{repo_id => ?REPO, caller => ?OWNER,
                           advances => [#{ref => <<"refs/heads/main">>, old_oid => ?ZERO,
                                          new_oid => Head}]}])),

    {reply, #{stdout := Listed}} = upload_pack(#{repo_id => ?REPO, stdin => git_v2:ls_refs_request()}, ?STRANGER_KEY),
    {ok, Refs} = git_v2:parse_ls_refs(Listed),
    ?assert(lists:member(#{name => <<"refs/heads/main">>, oid => Head, symref_target => undefined}, Refs)),
    {reply, #{stdout := Fetched}} = upload_pack(#{repo_id => ?REPO, stdin => git_v2:fetch_request([Head])}, ?STRANGER_KEY),
    {ok, Pack} = git_v2:packfile(Fetched),
    Clone = filename:join(Root, "clone.git"),
    git(["init", "--quiet", "--bare", Clone]),
    {ok, #{exit_status := 0}} = git_exec:run(os:find_executable("git"),
                                             ["--git-dir", Clone, "index-pack", "--stdin"], Pack, [], 30000),
    ?assertEqual("commit", string:trim(git(["--git-dir", Clone, "cat-file", "-t", binary_to_list(Head)]))).

stranger_cannot_push(#{work := Work, head := Head}) ->
    ?assertEqual({error, not_owner},
                 receive_pack(#{repo_id => ?REPO, stdin => push_request(Work, Head)}, ?STRANGER_KEY)),
    ?assertEqual({error, not_owner}, receive_pack(#{repo_id => ?REPO, advertise => 1}, ?STRANGER_KEY)).

stranger_cannot_see_private(_C) ->
    row(<<"private">>, <<"active">>),
    ?assertEqual({error, not_found},
                 upload_pack(#{repo_id => ?REPO, stdin => git_v2:ls_refs_request()}, ?STRANGER_KEY)),
    ?assertMatch({reply, #{stdout := _}},
                 upload_pack(#{repo_id => ?REPO, stdin => git_v2:ls_refs_request()}, ?OWNER_KEY)).

archived_refuses_push(#{work := Work, head := Head}) ->
    row(<<"public">>, <<"archived">>),
    ?assertEqual({error, archived},
                 receive_pack(#{repo_id => ?REPO, stdin => push_request(Work, Head)}, ?OWNER_KEY)).

unknown_repo_is_not_found(_C) ->
    ?assertEqual({error, not_found},
                 upload_pack(#{repo_id => <<"repo-01900000000000000000000000000000">>,
                               stdin => git_v2:ls_refs_request()}, ?OWNER_KEY)),
    %% An id that is not a repo id never reaches the filesystem.
    ?assertEqual({error, bad_request},
                 upload_pack(#{repo_id => <<"../../etc">>, stdin => <<>>}, ?OWNER_KEY)),
    ?assertEqual({error, bad_request}, upload_pack(#{stdin => <<>>}, ?OWNER_KEY)),
    %% `$' alone would also match before a trailing newline.
    ?assertEqual({error, bad_request},
                 upload_pack(#{repo_id => <<?REPO/binary, "\n">>, stdin => <<>>}, ?OWNER_KEY)).

refused_push_records_nothing(#{work := Work, head := Head}) ->
    %% Claims the ref is at an oid it is not at: receive-pack refuses it.
    Bogus = <<"1111111111111111111111111111111111111111">>,
    {ok, Pack} = pack(Work, Head),
    Request = git_push:request([#{ref => <<"refs/heads/main">>, old_oid => Bogus, new_oid => Head}], Pack),
    {reply, #{stdout := Report}} = receive_pack(#{repo_id => ?REPO, stdin => Request}, ?OWNER_KEY),
    ?assertMatch({ok, [{<<"refs/heads/main">>, {error, _}}]}, git_push:parse_report(Report)),
    ?assertNot(meck:called(maybe_advance_refs, dispatch, '_')).

%% macula_response gives a handler 30 s, fixed, and answers
%% temporary_relay_failure past it while the handler runs on. git must stop
%% first, so a caller always hears the real outcome.
git_stops_before_the_mesh_gives_up_test() ->
    ?assert(bare_repo:timeout_ms() < 30000).

%% A node runs a bounded number of git processes; past it a call is refused
%% as busy instead of queueing another git.
git_runs_are_bounded_test() ->
    ok = git_slots:init(2),
    ok = git_slots:acquire(),
    ok = git_slots:acquire(),
    ?assertEqual({error, busy}, git_slots:acquire()),
    ok = git_slots:release(),
    ?assertEqual(ok, git_slots:acquire()),
    ok = git_slots:release(),
    ok = git_slots:release().

upload_pack(Payload, Caller)  -> call(upload_pack_responder, Payload, Caller).
receive_pack(Payload, Caller) -> call(receive_pack_responder, Payload, Caller).

call(Mod, Payload, Caller) ->
    {ok, S0} = Mod:init([]),
    case Mod:handle_request(Payload#{caller => Caller}, S0) of
        {reply, Reply, _S} -> {reply, Reply};
        {error, Why, _S}   -> {error, Why}
    end.

push_request(Work, Head) ->
    {ok, Pack} = pack(Work, Head),
    git_push:request([#{ref => <<"refs/heads/main">>, old_oid => ?ZERO, new_oid => Head}], Pack).

pack(Work, Head) ->
    {ok, #{exit_status := 0, stdout := Pack}} =
        git_exec:run(os:find_executable("git"),
                     ["-C", Work, "pack-objects", "--stdout", "--revs", "--quiet"],
                     <<Head/binary, "\n">>, [], 30000),
    {ok, Pack}.

git(Args) ->
    {ok, #{exit_status := 0, stdout := Out}} =
        git_exec:run(os:find_executable("git"), Args, <<>>,
                     [{"GIT_AUTHOR_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@t"},
                      {"GIT_COMMITTER_NAME", "t"}, {"GIT_COMMITTER_EMAIL", "t@t"}], 30000),
    binary_to_list(Out).
