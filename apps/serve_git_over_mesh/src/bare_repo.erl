%% @doc The bare repository behind a repo id, and the git runs against it.
%%
%% A repository's directory is made the first time anything touches it
%% (`git init --bare' is idempotent here: an existing repository is left
%% alone), so there is no window in which a just-initiated repo exists in the
%% dossier but not on disk.
-module(bare_repo).

-export([ensure/2, refs/1, git/3, timeout_ms/0]).

%% Under the git procedures' handler deadline (mcl_git_service:
%% git_handler_timeout_ms/0, 300 s): past that macula answers the caller
%% `temporary_relay_failure' while the handler runs on, so a push could land
%% and be reported failed. git stops first; the caller hears the real outcome.
-define(TIMEOUT_MS, 270000).
%% One mesh frame carries 16 MiB; stop collecting well before.
-define(MAX_STDOUT, 15 * 1024 * 1024).

-spec timeout_ms() -> pos_integer().
timeout_ms() -> ?TIMEOUT_MS.

-spec ensure(file:filename(), binary()) -> ok | {error, term()}.
ensure(Dir, DefaultBranch) ->
    initialised(filelib:is_regular(filename:join(Dir, "HEAD")), Dir, DefaultBranch).

initialised(true, _Dir, _Branch) ->
    ok;
initialised(false, Dir, Branch) ->
    ok = filelib:ensure_path(Dir),
    succeeded(git(["init", "--quiet", "--bare", <<"--initial-branch=", Branch/binary>>, Dir], <<>>, [])).

%% @doc Every ref and the object it points at.
-spec refs(file:filename()) -> {ok, #{binary() => binary()}} | {error, term()}.
refs(Dir) ->
    listed(git(["--git-dir", Dir, "for-each-ref", "--format=%(objectname) %(refname)"], <<>>, [])).

listed({ok, #{exit_status := 0, stdout := Out}}) ->
    {ok, maps:from_list([ref(L) || L <- binary:split(Out, <<"\n">>, [global, trim_all])])};
listed({error, _} = Err) ->
    Err;
listed(Failed) ->
    {error, {for_each_ref, Failed}}.

ref(Line) ->
    [Oid, Name] = binary:split(Line, <<" ">>),
    {Name, Oid}.

-spec git([iodata()], iodata(), [{string(), string()}]) -> {ok, git_exec:result()} | {error, term()}.
git(Args, Stdin, Env) ->
    slotted(git_slots:acquire(), Args, Stdin, Env).

slotted(ok, Args, Stdin, Env) ->
    try git_exec:run(executable(), Args, Stdin, Env, ?TIMEOUT_MS, #{max_stdout => ?MAX_STDOUT})
    after git_slots:release()
    end;
slotted({error, busy} = Busy, _Args, _Stdin, _Env) ->
    Busy.

executable() -> found(os:find_executable("git")).

found(false) -> error(git_not_installed);
found(Path)  -> Path.

succeeded({ok, #{exit_status := 0}}) -> ok;
succeeded(Other)                     -> {error, {git_init, Other}}.
