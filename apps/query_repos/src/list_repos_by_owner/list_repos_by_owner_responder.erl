%% @doc Procedure `mcl-git/list_repos_by_owner'. Payload: `owner', a node id
%% in hex. The owner sees all of them; anyone else, the public ones.
-module(list_repos_by_owner_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(P, State) ->
    listed(mcl_om_wire:field(owner, P), repo_caller:id(P), State).

listed(Owner, Caller, State) when is_binary(Owner) ->
    Rows = project_repos_store:list_by_owner(string:lowercase(Owner)),
    {reply, #{repos => repo_view:visible(Rows, Caller)}, State};
listed(_Missing, _Caller, State) ->
    {error, bad_request, State}.
