%% @doc Procedure `mcl-git/initiate_repo': open a new repository, owned by the
%% caller. Answers the minted `repo_id', which is what `mesh://<realm>/<repo_id>'
%% clones.
%%
%% Payload: `name'; optional `description', `visibility' (`public' or
%% `private', default private), `default_branch' (default `main'), `tags'.
%%
%% ONLY AN INITIATOR MAY. Every repository is a directory on this node's disk,
%% so the procedure is fail-closed: the caller's node id must be on the
%% `initiators' list (MCL_GIT_INITIATORS), and an empty list admits nobody.
-module(initiate_repo_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(Payload, State) ->
    admitted(lists:member(repo_caller:id(Payload), repo_initiators:list()), Payload, State).

admitted(false, _Payload, State) ->
    {error, not_an_initiator, State};
admitted(true, Payload, State) ->
    lifecycle_call:answer(Payload, fun(Caller) -> params(Payload, Caller) end,
                          fun maybe_initiate_repo:dispatch/1, State).

params(P, Caller) ->
    #{name           => mcl_om_wire:field(name, P),
      owner          => Caller,
      description    => mcl_om_wire:field(description, P, <<>>),
      visibility     => mcl_om_wire:field(visibility, P, <<"private">>),
      default_branch => mcl_om_wire:field(default_branch, P, <<"main">>),
      tags           => mcl_om_wire:field(tags, P, [])}.
