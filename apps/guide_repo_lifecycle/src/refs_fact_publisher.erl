%% @doc The macula_publisher callback for refs_fact: publish once and stop,
%% saying so when the publish did not go out.
-module(refs_fact_publisher).

-behaviour(macula_publisher).

-export([init/1, handle_published/2]).

init(_Args) -> {ok, undefined}.

handle_published(ok, State)       -> {stop, normal, State};
handle_published({ok, _}, State)  -> {stop, normal, State};
handle_published(Failed, State) ->
    logger:warning("[mcl_git] a push announcement did not go out: ~p", [Failed]),
    {stop, normal, State}.
