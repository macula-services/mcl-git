%% @doc Where a repository lives on disk: `<repo_root>/<repo_id>.git'.
%%
%% The repo id reaches here from the wire, so it is checked against the
%% exact shape initiate_repo_v1 mints (`repo-' and 32 lowercase hex) before
%% it is ever part of a path. Nothing else can name a directory.
-module(repo_paths).

-export([dir/1]).

-spec dir(term()) -> {ok, file:filename()} | {error, bad_request}.
dir(RepoId) when is_binary(RepoId) ->
    shaped(re:run(RepoId, <<"^repo-[0-9a-f]{32}$">>, [dollar_endonly, {capture, none}]), RepoId);
dir(_NotAnId) ->
    {error, bad_request}.

shaped(match, RepoId) -> {ok, filename:join(root(), <<RepoId/binary, ".git">>)};
shaped(nomatch, _Id)  -> {error, bad_request}.

root() -> rooted(application:get_env(serve_git_over_mesh, repo_root)).

rooted({ok, Root}) when Root =/= "", Root =/= <<>> -> Root;
rooted(_Unset) -> error({mcl_git_repo_root_unset, repo_root}).
