-module(git_exec_tests).

-include_lib("eunit/include/eunit.hrl").

feeds_stdin_and_sees_eof_test() ->
    ?assertMatch({ok, #{exit_status := 0, stdout := <<"hello">>}},
                 git_exec:run("/bin/cat", [], <<"hello">>, [], 5000)).

keeps_stderr_out_of_stdout_test() ->
    {ok, #{exit_status := 0, stdout := Out, stderr := Err}} =
        git_exec:run("/bin/sh", ["-c", "echo out; echo err >&2"], <<>>, [], 5000),
    ?assertEqual(<<"out\n">>, Out),
    ?assertEqual(<<"err\n">>, Err).

reports_a_failing_exit_status_test() ->
    ?assertMatch({ok, #{exit_status := 3}},
                 git_exec:run("/bin/sh", ["-c", "exit 3"], <<>>, [], 5000)).

arguments_are_never_shell_parsed_test() ->
    Hostile = "$(touch /tmp/git_exec_pwned); `id`",
    {ok, #{stdout := Out}} = git_exec:run("/bin/echo", [Hostile], <<>>, [], 5000),
    ?assertEqual(list_to_binary(Hostile ++ "\n"), Out),
    ?assertNot(filelib:is_file("/tmp/git_exec_pwned")).

passes_environment_test() ->
    {ok, #{stdout := Out}} = git_exec:run("/bin/sh", ["-c", "printf %s \"$GIT_PROTOCOL\""],
                                          <<>>, [{"GIT_PROTOCOL", "version=2"}], 5000),
    ?assertEqual(<<"version=2">>, Out).

times_out_test() ->
    ?assertEqual({error, {timeout, 200}},
                 git_exec:run("/bin/sleep", ["5"], <<>>, [], 200)).

%% A reply the mesh could never carry is not collected in full first: the
%% run stops, and says so, as soon as stdout passes the limit.
stops_collecting_past_the_limit_test() ->
    Big = binary:copy(<<"x">>, 200000),
    ?assertEqual({error, {stdout_exceeds, 1000}},
                 git_exec:run("/bin/cat", [], Big, [], 5000, #{max_stdout => 1000})),
    ?assertMatch({ok, #{stdout := <<"hi">>}},
                 git_exec:run("/bin/cat", [], <<"hi">>, [], 5000, #{max_stdout => 1000})).

%% git runs children (receive-pack runs index-pack); a timeout kills them too.
a_timeout_kills_the_children_test() ->
    Marker = "/tmp/git_exec_child_" ++ integer_to_list(erlang:unique_integer([positive])),
    {error, {timeout, 300}} =
        git_exec:run("/bin/sh", ["-c", "sh -c 'sleep 2; touch " ++ Marker ++ "' & wait"],
                     <<>>, [], 300),
    timer:sleep(2500),
    ?assertNot(filelib:is_file(Marker)).
