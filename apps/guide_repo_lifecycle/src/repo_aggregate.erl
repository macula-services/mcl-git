%% @doc The repo aggregate: one per repository, stream id = repo id.
%%
%% Owns the two rules every later command answers to: a repo is initiated
%% once, and only its owner (the node that initiated it) may change it or
%% move its refs. Archiving is final; an archived repo refuses everything.
-module(repo_aggregate).

-behaviour(evoq_aggregate).

-include("repo_status.hrl").

-export([init/1, execute/2, apply/2, state_module/0, stream_id/1]).

state_module() -> repo_state.

init(RepoId) -> {ok, repo_state:new(RepoId)}.

apply(State, Event) -> repo_state:apply_event(State, Event).

%% The repo id is minted as a stream id (reckon_gater_stream_id:new/1, in
%% initiate_repo_v1:new/1), so it needs no separate derivation.
-spec stream_id(binary()) -> binary().
stream_id(RepoId) -> RepoId.

execute(State, #{command_type := initiate_repo} = Payload) ->
    initiate(evoq_bit_flags:has(repo_state:status(State), ?REPO_INITIATED), Payload);
execute(State, #{command_type := Type} = Payload) ->
    change(live(State), Type, Payload);
execute(_State, _Payload) ->
    {error, unknown_command}.

initiate(true, _Payload)  -> {error, already_initiated};
initiate(false, Payload)  -> maybe_initiate_repo:handle_from_map(Payload).

%% A change needs a live repo, and then its owner.
live(State) ->
    Status = repo_state:status(State),
    lived(evoq_bit_flags:has(Status, ?REPO_INITIATED),
          evoq_bit_flags:has(Status, ?REPO_ARCHIVED), State).

lived(false, _Archived, _State) -> {error, not_initiated};
lived(true, true, _State)       -> {error, archived};
lived(true, false, State)       -> {ok, repo_state:owner(State)}.

change({error, _} = Refused, _Type, _Payload) ->
    Refused;
change({ok, Owner}, Type, #{caller := Owner} = Payload) ->
    handle(Type, Payload);
change({ok, _Owner}, _Type, _Payload) ->
    {error, not_owner}.

handle(rename_repo, P)          -> maybe_rename_repo:handle_from_map(P);
handle(set_repo_description, P) -> maybe_set_repo_description:handle_from_map(P);
handle(archive_repo, P)         -> maybe_archive_repo:handle_from_map(P);
handle(advance_refs, P)         -> maybe_advance_refs:handle_from_map(P);
handle(_Unknown, _P)            -> {error, unknown_command}.
