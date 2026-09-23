%% @doc Procedure `mcl-git/archive_repo'. Payload: `repo_id', optional
%% `reason'. Only the owner, and final: the repository stays readable as
%% history and refuses every change after.
-module(archive_repo_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(P, State) ->
    lifecycle_call:answer(P, fun(Caller) ->
                                 #{repo_id => mcl_om_wire:field(repo_id, P),
                                   reason => mcl_om_wire:field(reason, P, <<>>),
                                   caller => Caller}
                             end, fun maybe_archive_repo:dispatch/1, State).
