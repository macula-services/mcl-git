%% @doc The CMD department's own processes: the process manager that
%% announces pushes. The repo aggregates themselves are started on demand by
%% evoq, keyed by stream id, the first time a command reaches one.
-module(guide_repo_lifecycle_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => on_refs_advanced_publish_refs_fact,
          start => {evoq_event_handler, start_link, [on_refs_advanced_publish_refs_fact, #{}, #{}]}}
    ],
    {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, Children}}.
