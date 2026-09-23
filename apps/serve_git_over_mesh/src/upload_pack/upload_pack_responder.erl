%% @doc Procedure `mcl-git/upload_pack': one protocol v2 request (ls-refs or
%% fetch) through `git upload-pack --stateless-rpc', its answer whole.
%%
%% Payload: `repo_id', and `stdin', the request bytes exactly as git's client
%% side writes them. Clone and fetch are two calls: ls-refs, then fetch.
%% Anyone may read a public repository; only its owner a private one.
-module(upload_pack_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    served(served_repo:resolve(Payload, may_read), Payload, State).

served({ok, RepoId, Dir, _Caller}, Payload, State) ->
    Stdin = mcl_om_wire:field(stdin, Payload, <<>>),
    git_reply:answer(bare_repo:git(["upload-pack", "--stateless-rpc", Dir], Stdin,
                               [{"GIT_PROTOCOL", "version=2"}]),
                 RepoId, State);
served({error, Why}, _Payload, State) ->
    {error, Why, State}.
