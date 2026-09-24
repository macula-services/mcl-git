%% @doc `git mesh': the user-facing commands. git runs `git-mesh' on PATH for
%% `git mesh <command>', as it does any `git-<name>'.
%%
%%   git mesh whoami                  this machine's node id (what an operator
%%                                    lists in MCL_GIT_INITIATORS)
%%   git mesh init <name> [options]   initiate a repository, owned by this
%%                                    machine's node, and print its mesh:// URL
-module(git_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

parses_init_test() ->
    ?assertEqual({init, <<"io.macula">>, #{name => <<"dotfiles">>, visibility => <<"private">>}},
                 git_mesh:parse(["init", "dotfiles"])),
    ?assertEqual({init, <<"example.org">>, #{name => <<"x">>, visibility => <<"public">>,
                                             description => <<"my stuff">>,
                                             default_branch => <<"trunk">>}},
                 git_mesh:parse(["init", "x", "--public", "--description", "my stuff",
                                 "--default-branch", "trunk", "--realm", "example.org"])).

parses_whoami_and_refuses_the_rest_test() ->
    ?assertEqual(whoami, git_mesh:parse(["whoami"])),
    ?assertEqual({error, usage}, git_mesh:parse([])),
    ?assertEqual({error, usage}, git_mesh:parse(["init"])),
    ?assertEqual({error, usage}, git_mesh:parse(["init", "x", "--nonsense"])),
    ?assertEqual({error, usage}, git_mesh:parse(["frobnicate"])).

%% The procedure's refusal, as a user can act on it.
not_an_initiator_says_what_to_do_test() ->
    Msg = lists:flatten(git_mesh:describe({initiate, {call_error, <<"not_an_initiator">>, <<>>}},
                                          <<"ab12">>)),
    ?assertNotEqual(nomatch, string:find(Msg, "ab12")),
    ?assertNotEqual(nomatch, string:find(Msg, "MCL_GIT_INITIATORS")).

%% macula 12 answers with CBOR text keys and values.
the_repo_id_is_read_off_the_wire_test() ->
    ?assertEqual({ok, <<"repo-01">>},
                 git_remote_macula:repo_id({ok, #{{text, <<"repo_id">>} => {text, <<"repo-01">>}}})),
    ?assertEqual({ok, <<"repo-01">>}, git_remote_macula:repo_id({ok, #{repo_id => <<"repo-01">>}})),
    ?assertEqual({error, {unexpected_reply, #{}}}, git_remote_macula:repo_id({ok, #{}})),
    ?assertEqual({error, x}, git_remote_macula:repo_id({error, x})).

%% From zero to a clone, as the README walks it: init prints a URL, and that
%% URL clones, takes a push, and clones again. Real git, loopback transport.
walkthrough_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(C) -> [{timeout, 120, fun() -> walkthrough(C) end}] end}.

setup() ->
    Root = filename:join("/tmp", "git_mesh_tests_" ++ integer_to_list(erlang:unique_integer([positive]))),
    Bin = filename:join(Root, "bin"),
    ok = filelib:ensure_path(Bin),
    ok = filelib:ensure_path(filename:join(Root, "repos")),
    Paths = string:join(["-pa " ++ P || P <- code:get_path(), filelib:is_dir(P)], " "),
    [begin
         F = filename:join(Bin, Name),
         ok = file:write_file(F, ["#!/bin/sh\nexec erl -noshell ", Paths,
                                  " -macula crypto_profile pq_hybrid -run ", Mod,
                                  " main -extra \"$@\"\n"]),
         ok = file:change_mode(F, 8#755)
     end || {Name, Mod} <- [{"git-remote-mesh", "git_remote_mesh"}, {"git-mesh", "git_mesh"}]],
    Env = "HOME=" ++ Root ++ " PATH=" ++ Bin ++ ":$PATH MCL_GIT_REMOTE_TRANSPORT=git_remote_loopback "
          "MCL_GIT_LOOPBACK_ROOT=" ++ filename:join(Root, "repos") ++ " "
          "GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t ",
    #{root => Root, env => Env}.

cleanup(#{root := Root}) -> os:cmd("rm -rf '" ++ Root ++ "'").

walkthrough(#{root := Root, env := Env}) ->
    %% whoami: 64 hex, and the same on every run (the one stored identity).
    {0, Id1} = sh(Env ++ "git mesh whoami"),
    {0, Id2} = sh(Env ++ "git mesh whoami"),
    ?assertMatch({match, _}, re:run(Id1, "^[0-9a-f]{64}\n$")),
    ?assertEqual(Id1, Id2),
    %% init prints the URL, and nothing else, on stdout.
    {0, Out} = sh(Env ++ "git mesh init dotfiles --public"),
    {match, [Url]} = re:run(Out, "^(mesh://io\\.macula/repo-[0-9a-f]{32})\n$", [{capture, all_but_first, list}]),
    A = filename:join(Root, "a"),
    {0, _} = sh(Env ++ "git clone --quiet " ++ Url ++ " " ++ A),
    ok = file:write_file(filename:join(A, "README"), <<"hello\n">>),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " add README"),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " commit --quiet -m first"),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " push --quiet origin HEAD:main"),
    B = filename:join(Root, "b"),
    {0, _} = sh(Env ++ "git clone --quiet " ++ Url ++ " " ++ B),
    ?assertEqual({ok, <<"hello\n">>}, file:read_file(filename:join(B, "README"))),
    %% A bad invocation says how to use it, on stderr, and fails.
    {Status, _} = sh(Env ++ "git mesh init"),
    ?assertNotEqual(0, Status).

%% stdout only: the URL must be all a script capturing `$(git mesh init x)' gets.
sh(Cmd) ->
    Port = open_port({spawn, "sh -c '" ++ Cmd ++ "' 2>/dev/null"}, [exit_status, stream]),
    collect(Port, []).

collect(Port, Acc) ->
    receive
        {Port, {data, D}} -> collect(Port, Acc ++ D);
        {Port, {exit_status, S}} -> {S, Acc}
    after 60000 -> error(timeout)
    end.
