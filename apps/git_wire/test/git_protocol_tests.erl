%% @doc The whole wire, against real git on both ends, with no mesh between:
%% push a commit into a bare repo through `git receive-pack --stateless-rpc',
%% then list its refs and fetch the commit back through `git upload-pack'
%% (protocol v2), and index the pack into an empty repo.
%%
%% This is what mcl-git's two procedures carry, byte for byte, so a green
%% run here means the requests the helper builds and the responses it
%% parses are the ones git actually speaks.
-module(git_protocol_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ZERO, <<"0000000000000000000000000000000000000000">>).

push_then_clone_test_() ->
    {setup, fun setup/0, fun cleanup/1, fun(Ctx) -> [{timeout, 60, fun() -> round_trip(Ctx) end}] end}.

setup() ->
    Root = filename:join("/tmp", "git_protocol_tests_" ++ integer_to_list(erlang:unique_integer([positive]))),
    ok = filelib:ensure_path(Root),
    Bare = filename:join(Root, "server.git"),
    Work = filename:join(Root, "work"),
    Clone = filename:join(Root, "clone.git"),
    git(["init", "--quiet", "--bare", "--initial-branch=main", Bare]),
    git(["init", "--quiet", "--initial-branch=main", Work]),
    git(["init", "--quiet", "--bare", Clone]),
    ok = file:write_file(filename:join(Work, "README"), <<"hello mesh\n">>),
    git(["-C", Work, "add", "README"]),
    git(["-C", Work, "commit", "--quiet", "-m", "first"]),
    Head = list_to_binary(string:trim(git(["-C", Work, "rev-parse", "HEAD"]))),
    #{root => Root, bare => Bare, work => Work, clone => Clone, head => Head}.

cleanup(#{root := Root}) ->
    os:cmd("rm -rf '" ++ Root ++ "'").

round_trip(#{bare := Bare, work := Work, clone := Clone, head := Head}) ->
    %% PUSH. The advertisement of an empty repo carries no refs but still
    %% names the capabilities receive-pack offers.
    {ok, Adv} = run_git(["receive-pack", "--stateless-rpc", "--advertise-refs", Bare], <<>>, []),
    {ok, [], Caps} = git_push:parse_advertisement(Adv),
    ?assert(lists:member(<<"report-status">>, Caps)),
    {ok, Pack} = run_git(["-C", Work, "pack-objects", "--stdout", "--revs", "--quiet"],
                         <<Head/binary, "\n">>, []),
    Request = git_push:request([#{ref => <<"refs/heads/main">>, old_oid => ?ZERO,
                                  new_oid => Head}], Pack),
    {ok, Report} = run_git(["receive-pack", "--stateless-rpc", Bare], Request, []),
    ?assertEqual({ok, [{<<"refs/heads/main">>, ok}]}, git_push:parse_report(Report)),

    %% LIST. Protocol v2 ls-refs sees the ref the push created.
    V2 = [{"GIT_PROTOCOL", "version=2"}],
    {ok, Listed} = run_git(["upload-pack", "--stateless-rpc", Bare], git_v2:ls_refs_request(), V2),
    {ok, Refs} = git_v2:parse_ls_refs(Listed),
    ?assert(lists:member(#{name => <<"refs/heads/main">>, oid => Head, symref_target => undefined}, Refs)),
    ?assert(lists:member(#{name => <<"HEAD">>, oid => Head, symref_target => <<"refs/heads/main">>}, Refs)),

    %% FETCH. The packfile section, unwrapped from its sideband, indexes into
    %% an empty repo and the pushed commit is there.
    {ok, Fetched} = run_git(["upload-pack", "--stateless-rpc", Bare],
                            git_v2:fetch_request([Head]), V2),
    {ok, Packfile} = git_v2:packfile(Fetched),
    {ok, _} = run_git(["--git-dir", Clone, "index-pack", "--stdin", "--fix-thin"], Packfile, []),
    ?assertEqual("commit", string:trim(git(["--git-dir", Clone, "cat-file", "-t", binary_to_list(Head)]))).

refused_ref_is_reported_test() ->
    Report = iolist_to_binary([pkt_line:encode(<<"unpack ok\n">>),
                               pkt_line:encode(<<"ng refs/heads/main non-fast-forward\n">>),
                               pkt_line:flush()]),
    ?assertEqual({ok, [{<<"refs/heads/main">>, {error, <<"non-fast-forward">>}}]},
                 git_push:parse_report(Report)).

failed_unpack_is_reported_test() ->
    Report = iolist_to_binary([pkt_line:encode(<<"unpack index-pack abnormal exit\n">>),
                               pkt_line:flush()]),
    ?assertEqual({error, {unpack, <<"index-pack abnormal exit">>}}, git_push:parse_report(Report)).

a_fetch_response_without_a_packfile_is_refused_test() ->
    ?assertEqual({error, no_packfile},
                 git_v2:packfile(iolist_to_binary([pkt_line:encode(<<"acknowledgments\n">>),
                                                   pkt_line:flush()]))).

a_sideband_error_is_surfaced_test() ->
    Resp = iolist_to_binary([pkt_line:encode(<<"packfile\n">>),
                             pkt_line:encode(<<3, "upload-pack: not our ref">>),
                             pkt_line:flush()]),
    ?assertEqual({error, {remote, <<"upload-pack: not our ref">>}}, git_v2:packfile(Resp)).

run_git(Args, Stdin, Env) ->
    case git_exec:run(os:find_executable("git"), Args, Stdin, Env, 30000) of
        {ok, #{exit_status := 0, stdout := Out}} -> {ok, Out};
        {ok, Failed} -> {error, Failed};
        {error, _} = Err -> Err
    end.

git(Args) ->
    {ok, Out} = run_git(Args, <<>>, [{"GIT_AUTHOR_NAME", "t"}, {"GIT_AUTHOR_EMAIL", "t@t"},
                                     {"GIT_COMMITTER_NAME", "t"}, {"GIT_COMMITTER_EMAIL", "t@t"}]),
    binary_to_list(Out).
