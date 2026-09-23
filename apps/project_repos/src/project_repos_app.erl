-module(project_repos_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> project_repos_sup:start_link().

stop(_State) -> ok.
