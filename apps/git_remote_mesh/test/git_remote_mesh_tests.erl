%% @doc git-remote-mesh, driven by REAL git: `git clone mesh://...', commit,
%% `git push', and a second clone that sees the push. git runs the helper as
%% a separate VM, as it would on a user's machine; only the transport is
%% swapped for the loopback, so the mesh is the one thing not exercised here.
-module(git_remote_mesh_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REPO, "repo-0190aaaabbbbccccddddeeeeffff0000").

url_parses_test() ->
    ?assertEqual({ok, #{realm_name => <<"io.macula">>, repo_id => <<?REPO>>}},
                 mesh_url:parse("mesh://io.macula/" ?REPO)),
    ?assertEqual({error, {bad_mesh_url, "mesh://io.macula"}}, mesh_url:parse("mesh://io.macula")),
    ?assertEqual({error, {bad_mesh_url, "https://x/y"}}, mesh_url:parse("https://x/y")),
    ?assertEqual({error, {bad_mesh_url, "mesh://io.macula/a/b"}}, mesh_url:parse("mesh://io.macula/a/b")).

real_git_test_() ->
    {setup, fun setup/0, fun cleanup/1,
     fun(C) -> [{timeout, 120, fun() -> clone_push_clone(C) end}] end}.

setup() ->
    Root = filename:join("/tmp", "git_remote_mesh_tests_" ++ integer_to_list(erlang:unique_integer([positive]))),
    Bin = filename:join(Root, "bin"),
    Repos = filename:join(Root, "repos"),
    ok = filelib:ensure_path(Bin),
    ok = filelib:ensure_path(Repos),
    sh("git init --quiet --bare --initial-branch=main " ++ filename:join(Repos, ?REPO ".git")),
    Helper = filename:join(Bin, "git-remote-mesh"),
    Paths = string:join(["-pa " ++ P || P <- code:get_path(), filelib:is_dir(P)], " "),
    ok = file:write_file(Helper, ["#!/bin/sh\nexec erl -noshell ", Paths,
                                  " -run git_remote_mesh main -extra \"$@\"\n"]),
    ok = file:change_mode(Helper, 8#755),
    Env = "PATH=" ++ Bin ++ ":$PATH MCL_GIT_REMOTE_TRANSPORT=git_remote_loopback "
          "MCL_GIT_LOOPBACK_ROOT=" ++ Repos ++ " "
          "GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t ",
    #{root => Root, env => Env}.

cleanup(#{root := Root}) -> os:cmd("rm -rf '" ++ Root ++ "'").

clone_push_clone(#{root := Root, env := Env}) ->
    Url = "mesh://io.macula/" ?REPO,
    A = filename:join(Root, "a"),
    B = filename:join(Root, "b"),
    {0, _} = sh(Env ++ "git clone --quiet " ++ Url ++ " " ++ A),
    ok = file:write_file(filename:join(A, "README"), <<"over the mesh\n">>),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " add README"),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " commit --quiet -m first"),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " push --quiet origin HEAD:main"),
    {0, _} = sh(Env ++ "git clone --quiet " ++ Url ++ " " ++ B),
    ?assertEqual({ok, <<"over the mesh\n">>}, file:read_file(filename:join(B, "README"))),
    %% A second push on top, then a fetch into the first clone's sibling.
    ok = file:write_file(filename:join(A, "README"), <<"again\n">>),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " commit --quiet -am second"),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " push --quiet origin HEAD:main"),
    {0, _} = sh(Env ++ "git -C " ++ B ++ " pull --quiet --ff-only origin main"),
    ?assertEqual({ok, <<"again\n">>}, file:read_file(filename:join(B, "README"))),
    %% An annotated tag arrives as a tag object, not peeled to its commit.
    {0, _} = sh(Env ++ "git -C " ++ A ++ " tag -a v1 -m release-one"),
    {0, _} = sh(Env ++ "git -C " ++ A ++ " push --quiet origin v1"),
    C = filename:join(Root, "c"),
    {0, _} = sh(Env ++ "git clone --quiet " ++ Url ++ " " ++ C),
    ?assertMatch({0, <<"tag\n">>}, sh("git -C " ++ C ++ " cat-file -t refs/tags/v1")),
    %% A ref that does not exist is refused as that ref, not as a crash.
    {Status, Out} = sh(Env ++ "git -C " ++ A ++ " push origin nosuchbranch"),
    ?assertNotEqual(0, Status),
    ?assertEqual(nomatch, binary:match(Out, <<"crash">>)).

sh(Cmd) ->
    Port = open_port({spawn, "sh -c '" ++ Cmd ++ "' 2>&1"}, [exit_status, binary, stream]),
    collect(Port, <<>>).

collect(Port, Acc) ->
    receive
        {Port, {data, D}} -> collect(Port, <<Acc/binary, D/binary>>);
        {Port, {exit_status, S}} -> S =:= 0 orelse ?debugFmt("~s", [Acc]), {S, Acc}
    after 60000 -> error(timeout)
    end.
