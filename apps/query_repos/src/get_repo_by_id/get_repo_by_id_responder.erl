%% @doc Procedure `mcl-git/get_repo_by_id'. Payload: `repo_id'. A private
%% repository answers `not_found' to everyone but its owner.
-module(get_repo_by_id_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(P, State) ->
    looked_up(mcl_om_wire:field(repo_id, P), repo_caller:id(P), State).

looked_up(RepoId, Caller, State) when is_binary(RepoId) ->
    found(project_repos_store:get(RepoId), Caller, State);
looked_up(_Missing, _Caller, State) ->
    {error, bad_request, State}.

found({ok, Row}, Caller, State) ->
    shown(repo_access:may_read(Row, Caller), Row, State);
found({error, not_found}, _Caller, State) ->
    {error, not_found, State}.

shown(ok, Row, State)             -> {reply, repo_view:render(Row), State};
shown({error, Why}, _Row, State)  -> {error, Why, State}.
