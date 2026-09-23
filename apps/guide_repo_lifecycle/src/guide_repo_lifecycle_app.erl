-module(guide_repo_lifecycle_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> guide_repo_lifecycle_sup:start_link().

stop(_State) -> ok.
