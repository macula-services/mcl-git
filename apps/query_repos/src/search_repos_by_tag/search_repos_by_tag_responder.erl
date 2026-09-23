%% @doc Procedure `mcl-git/search_repos_by_tag'. Payload: `tag'. Public
%% repositories carrying it, and the caller's own private ones.
-module(search_repos_by_tag_responder).

-behaviour(macula_response).

-export([init/1, handle_request/2]).

init(_Args) -> {ok, undefined}.

handle_request(P, State) ->
    searched(mcl_om_wire:field(tag, P), repo_caller:id(P), State).

searched(Tag, Caller, State) when is_binary(Tag) ->
    {reply, #{repos => repo_view:visible(project_repos_store:list_by_tag(Tag), Caller)}, State};
searched(_Missing, _Caller, State) ->
    {error, bad_request, State}.
