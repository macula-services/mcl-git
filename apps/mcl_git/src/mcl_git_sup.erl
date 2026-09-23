%% @doc The service's own root. It has no processes of its own: each
%% department (guide_repo_lifecycle, project_repos) supervises its own, and
%% mcl_om supervises and re-advertises the procedure handlers.
-module(mcl_git_sup).

-behaviour(supervisor).

-export([start_link/0, init/1]).

start_link() -> supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) -> {ok, {#{strategy => one_for_one, intensity => 5, period => 10}, []}}.
