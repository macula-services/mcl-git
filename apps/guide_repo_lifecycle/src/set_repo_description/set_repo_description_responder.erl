%% @doc Procedure `mcl-git/set_repo_description'. Payload: `repo_id',
%% `description'. Only the owner; the aggregate decides.
-module(set_repo_description_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(P, State) ->
    lifecycle_call:answer(P, fun(Caller) ->
                                 #{repo_id => mcl_om_wire:field(repo_id, P),
                                   description => mcl_om_wire:field(description, P),
                                   caller => Caller}
                             end, fun maybe_set_repo_description:dispatch/1, State).
