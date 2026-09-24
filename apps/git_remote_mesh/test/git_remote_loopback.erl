%% @doc A transport for tests: answers the two git procedures by running the
%% server side of git directly against a bare repository under
%% MCL_GIT_LOOPBACK_ROOT, with no mesh and no read model between. Selected
%% with MCL_GIT_REMOTE_TRANSPORT=git_remote_loopback.
-module(git_remote_loopback).

-export([connect/1, call/3, initiate/2]).

connect(_Url) -> {ok, loopback}.

call(loopback, <<"mcl-git/upload_pack">>, #{repo_id := Id, stdin := In}) ->
    run(["upload-pack", "--stateless-rpc", dir(Id)], In, [{"GIT_PROTOCOL", "version=2"}]);
call(loopback, <<"mcl-git/receive_pack">>, #{repo_id := Id, advertise := 1}) ->
    run(["receive-pack", "--stateless-rpc", "--advertise-refs", dir(Id)], <<>>, []);
call(loopback, <<"mcl-git/receive_pack">>, #{repo_id := Id, stdin := In}) ->
    run(["receive-pack", "--stateless-rpc", dir(Id)], In, []).

%% A new bare repository under a minted id, as mcl-git's initiate_repo does.
initiate(loopback, #{name := _}) ->
    Id = <<"repo-", (binary:encode_hex(crypto:strong_rand_bytes(16), lowercase))/binary>>,
    {ok, _} = run(["init", "--quiet", "--bare", "--initial-branch=main", dir(Id)], <<>>, []),
    {ok, Id}.

dir(Id) -> filename:join(os:getenv("MCL_GIT_LOOPBACK_ROOT"), <<Id/binary, ".git">>).

run(Args, In, Env) ->
    case git_exec:run(os:find_executable("git"), Args, In, Env, 30000) of
        {ok, #{exit_status := 0, stdout := Out}} -> {ok, #{stdout => Out}};
        Other -> {error, Other}
    end.
