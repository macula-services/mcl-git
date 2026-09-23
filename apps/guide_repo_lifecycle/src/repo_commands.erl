%% @doc Dispatch for the commands that change an existing repository: build
%% the typed command from its parameters, wrap it for evoq, route it to the
%% repo's aggregate. initiate_repo mints its own id and dispatches itself.
-module(repo_commands).

-export([dispatch/2]).

-spec dispatch(module(), map()) -> ok | {error, term()}.
dispatch(CommandModule, Params) ->
    dispatched(CommandModule, CommandModule:new(Params)).

dispatched(CommandModule, {ok, Cmd}) ->
    RepoId = CommandModule:repo_id(Cmd),
    Evoq = evoq_command:new(CommandModule:command_type(), repo_aggregate,
                            repo_aggregate:stream_id(RepoId), CommandModule:to_map(Cmd)),
    routed(evoq_router:dispatch(Evoq));
dispatched(_CommandModule, {error, _} = Err) ->
    Err.

routed({ok, _Version, _Events}) -> ok;
routed({error, _} = Err)        -> Err.
