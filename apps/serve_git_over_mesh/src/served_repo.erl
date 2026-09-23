%% @doc The front of both git procedures: which repository a call names,
%% whether the caller may do this to it, and its directory, made on first
%% use. Answers `bad_request' for a missing or malformed repo id, and the
%% repo_access verdict otherwise.
-module(served_repo).

-export([resolve/2]).

-spec resolve(map(), may_read | may_write) ->
    {ok, binary(), file:filename(), binary()} | {error, atom()}.
resolve(Payload, Access) ->
    RepoId = mcl_om_wire:field(repo_id, Payload),
    located(repo_paths:dir(RepoId), RepoId, repo_caller:id(Payload), Access).

located({ok, Dir}, RepoId, Caller, Access) ->
    rowed(project_repos_store:get(RepoId), RepoId, Dir, Caller, Access);
located({error, _} = Err, _RepoId, _Caller, _Access) ->
    Err.

rowed({ok, Row}, RepoId, Dir, Caller, Access) ->
    allowed(repo_access:Access(Row, Caller), Row, RepoId, Dir, Caller);
rowed({error, not_found} = Err, _RepoId, _Dir, _Caller, _Access) ->
    Err.

allowed(ok, Row, RepoId, Dir, Caller) ->
    on_disk(bare_repo:ensure(Dir, maps:get(default_branch, Row, <<"main">>)), RepoId, Dir, Caller);
allowed({error, _} = Refused, _Row, _RepoId, _Dir, _Caller) ->
    Refused.

on_disk(ok, RepoId, Dir, Caller) ->
    {ok, RepoId, Dir, Caller};
on_disk({error, Why}, RepoId, _Dir, _Caller) ->
    logger:error("[mcl_git] cannot make the bare repository for ~s: ~p", [RepoId, Why]),
    {error, repo_unavailable}.
