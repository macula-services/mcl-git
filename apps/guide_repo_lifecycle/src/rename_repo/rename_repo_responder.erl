%% @doc Procedure `mcl-git/rename_repo'. Payload: `repo_id', `new_name'.
%% Only the owner; the aggregate decides.
-module(rename_repo_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(P, State) ->
    lifecycle_call:answer(P, fun(Caller) ->
                                 #{repo_id => mcl_om_wire:field(repo_id, P),
                                   new_name => mcl_om_wire:field(new_name, P),
                                   caller => Caller}
                             end, fun maybe_rename_repo:dispatch/1, State).
