%% @doc Run a program with a one-shot stdin, collecting stdout and stderr
%% apart.
%%
%% git's `--stateless-rpc' modes read their whole request and answer only
%% after stdin reaches EOF, and an Erlang port cannot half-close a child's
%% stdin. So the request is written to a temporary file and the child reads
%% it by redirection. The redirection is done by `/bin/sh' running a FIXED
%% script, with the program and its arguments passed as positional
%% parameters: nothing a caller supplies is ever parsed by a shell.
%%
%% stderr goes to a second file, never into stdout: git writes warnings
%% there, and one merged into a pack stream corrupts the pack.
-module(git_exec).

-export([run/5, run/6]).

-type result() :: #{exit_status := non_neg_integer(), stdout := binary(), stderr := binary()}.
-export_type([result/0]).

-define(SCRIPT, "in=$1; err=$2; shift 2; exec \"$@\" < \"$in\" 2> \"$err\"").

-spec run(file:filename(), [string() | binary()], iodata(), [{string(), string()}],
          pos_integer()) -> {ok, result()} | {error, term()}.
run(Exe, Args, Stdin, Env, TimeoutMs) ->
    run(Exe, Args, Stdin, Env, TimeoutMs, #{}).

%% @doc As run/5. `max_stdout' stops the run, and kills it, as soon as stdout
%% passes that many bytes, rather than collecting an answer nobody can carry.
-spec run(file:filename(), [string() | binary()], iodata(), [{string(), string()}],
          pos_integer(), #{max_stdout => pos_integer()}) -> {ok, result()} | {error, term()}.
run(Exe, Args, Stdin, Env, TimeoutMs, Opts) ->
    In = temp_path("in"),
    Err = temp_path("err"),
    try
        ok = file:write_file(In, Stdin),
        spawned(open_port({spawn_executable, "/bin/sh"},
                          [{args, ["-c", ?SCRIPT, "sh", In, Err, Exe | Args]},
                           {env, Env}, binary, exit_status, stream, use_stdio]),
                Err, TimeoutMs, maps:get(max_stdout, Opts, infinity))
    after
        _ = file:delete(In),
        _ = file:delete(Err)
    end.

spawned(Port, Err, TimeoutMs, Max) ->
    Deadline = erlang:monotonic_time(millisecond) + TimeoutMs,
    collected(collect(Port, [], 0, Max, Deadline), Err, TimeoutMs, Max).

collect(Port, _Acc, Size, Max, _Deadline) when Size > Max ->
    stop(Port),
    too_large;
collect(Port, Acc, Size, Max, Deadline) ->
    Left = max(0, Deadline - erlang:monotonic_time(millisecond)),
    receive
        {Port, {data, Chunk}} ->
            collect(Port, [Chunk | Acc], Size + byte_size(Chunk), Max, Deadline);
        {Port, {exit_status, Status}} ->
            {exited, Status, iolist_to_binary(lists:reverse(Acc))}
    after Left ->
        stop(Port),
        timeout
    end.

collected({exited, Status, Out}, Err, _TimeoutMs, _Max) ->
    {ok, #{exit_status => Status, stdout => Out, stderr => read_stderr(Err)}};
collected(timeout, _Err, TimeoutMs, _Max) ->
    {error, {timeout, TimeoutMs}};
collected(too_large, _Err, _TimeoutMs, Max) ->
    {error, {stdout_exceeds, Max}}.

%% The program and everything it started: receive-pack runs index-pack, and
%% killing only the parent would leave the child writing into the repository.
stop(Port) ->
    kill(erlang:port_info(Port, os_pid)),
    catch port_close(Port),
    ok.

read_stderr(Err) ->
    stderr_of(file:read_file(Err)).

stderr_of({ok, Bin})   -> Bin;
stderr_of({error, _})  -> <<>>.

kill({os_pid, Pid}) ->
    Tree = tree(integer_to_list(Pid)),
    _ = os:cmd("kill -9 " ++ lists:join(" ", Tree) ++ " 2>/dev/null"),
    ok;
kill(_Gone) ->
    ok.

%% A process and its descendants, from /proc (Linux).
tree(Pid) ->
    [Pid | lists:append([tree(C) || C <- children(Pid)])].

children(Pid) ->
    listed(file:read_file(["/proc/", Pid, "/task/", Pid, "/children"])).

listed({ok, Bin})  -> string:lexemes(binary_to_list(Bin), " \n");
listed({error, _}) -> [].

temp_path(Kind) ->
    filename:join(temp_dir(), io_lib:format("git_exec-~s-~s-~b",
                                            [Kind, os:getpid(),
                                             erlang:unique_integer([positive])])).

temp_dir() -> dir(os:getenv("TMPDIR")).

dir(false) -> "/tmp";
dir("")    -> "/tmp";
dir(Dir)   -> Dir.
