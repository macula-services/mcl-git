%% @doc git-remote-mesh: git runs this as `git-remote-mesh <remote> <url>'
%% for a `mesh://' URL and speaks the remote-helper protocol with it on
%% stdin and stdout (gitremote-helpers(7)).
%%
%% stdout is the protocol, so nothing else may reach it: logging goes to
%% stderr (the launcher script sets that), and a fatal error is printed to
%% stderr before exiting non-zero, which git reports as the remote failing.
-module(git_remote_mesh).

-export([main/0]).

-spec main() -> no_return().
main() ->
    ok = io:setopts(standard_io, [binary]),
    exit_with(run(init:get_plain_arguments())).

run([_Remote, Url | _]) ->
    connected(mesh_url:parse(Url));
run(_Args) ->
    {error, usage}.

connected({ok, Target}) ->
    Transport = transport(),
    started(Transport:connect(Target), Transport, Target);
connected({error, _} = Err) ->
    Err.

started({ok, Conn}, Transport, #{repo_id := RepoId}) ->
    Call = fun(Procedure, Payload) ->
                   Transport:call(Conn, Procedure, Payload#{repo_id => RepoId})
           end,
    remote_helper:run(fun read_line/0, fun write/1, Call, git_dir());
started({error, _} = Err, _Transport, _Target) ->
    Err.

%% The transport is macula unless a test names another module.
transport() -> chosen(os:getenv("MCL_GIT_REMOTE_TRANSPORT")).

chosen(false) -> git_remote_macula;
chosen("")    -> git_remote_macula;
chosen(Name)  -> list_to_atom(Name).

git_dir() -> dir(os:getenv("GIT_DIR")).

dir(false) -> ".git";
dir(Dir)   -> Dir.

read_line() -> line(io:get_line(standard_io, "")).

line(eof)                  -> eof;
line({error, _})           -> eof;
line(Bin) when is_binary(Bin) -> string:trim(Bin, trailing, "\r\n").

write(IoData) -> ok = io:put_chars(standard_io, IoData).

exit_with(ok) ->
    halt(0);
exit_with({error, Why}) ->
    io:format(standard_error, "git-remote-mesh: ~ts~n", [describe(Why)]),
    halt(1).

describe(usage)                  -> "usage: git-remote-mesh <remote> mesh://<realm>/<repo_id>";
describe({bad_mesh_url, Url})    -> io_lib:format("not a mesh URL: ~ts (mesh://<realm>/<repo_id>)", [Url]);
describe({missing_env, Name})    -> io_lib:format("~s is not set", [Name]);
describe({bad_env, Name})        -> io_lib:format("~s is not valid hex", [Name]);
describe(Other)                  -> io_lib:format("~p", [Other]).
