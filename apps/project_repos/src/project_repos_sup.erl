%% @doc The PRJ department: the read-model store, then the projection that
%% fills it (store first, so the projection's first write has somewhere to go).
-module(project_repos_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    Children = [
        #{id => project_repos_store, start => {project_repos_store, start_link, []}},
        #{id => repo_lifecycle_to_repos,
          start => {evoq_projection, start_link, [repo_lifecycle_to_repos, #{}, #{}]}}
    ],
    {ok, {#{strategy => rest_for_one, intensity => 5, period => 10}, Children}}.
