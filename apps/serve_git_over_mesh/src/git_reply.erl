%% @doc Turning a git run into a procedure's answer.
%%
%% git's stdout goes back whole, as bytes. A run that failed is logged with
%% its stderr, here where it can be read, and answered with a code; git's
%% own stderr names paths on this node and does not go on the wire. An answer
%% the mesh cannot carry (one frame, 16 MiB) is refused by name as
%% `pack_too_large' (bare_repo stops git once it passes 15 MiB); a node at its
%% git bound answers `busy'; a run past bare_repo's deadline, `git_timeout'.
-module(git_reply).

-export([answer/3]).

-spec answer({ok, git_exec:result()} | {error, term()}, binary(), term()) ->
    {reply, map(), term()} | {error, atom(), term()}.
answer({ok, #{exit_status := 0, stdout := Out}}, _RepoId, State) ->
    {reply, #{stdout => Out}, State};
answer({ok, #{exit_status := Status, stderr := Err}}, RepoId, State) ->
    logger:warning("[mcl_git] git exited ~p on ~s: ~ts", [Status, RepoId, Err]),
    {error, git_failed, State};
answer({error, {stdout_exceeds, _}}, _RepoId, State) ->
    {error, pack_too_large, State};
answer({error, busy}, _RepoId, State) ->
    {error, busy, State};
answer({error, {timeout, _}}, RepoId, State) ->
    logger:warning("[mcl_git] git timed out on ~s", [RepoId]),
    {error, git_timeout, State};
answer({error, Why}, RepoId, State) ->
    logger:warning("[mcl_git] git did not run on ~s: ~p", [RepoId, Why]),
    {error, git_failed, State}.
