%% @doc OTP application entry. mcl_om:boot/1 opens the event store and its evoq
%% subscription (mcl_git_service exports store_id/0 and data_dir/0), wires the
%% mesh, the realm identity, the nine procedures and /health, then starts this
%% service.
-module(mcl_git_app).

-behaviour(application).

-export([start/2, stop/1]).

start(_Type, _Args) -> mcl_om:boot(mcl_git_service).

stop(_State) -> ok.
