%% @doc The repo aggregate's state: identity, ownership, metadata, status.
%%
%% Events reach apply_event/2 in two shapes: flat, straight from execute/2,
%% and with their fields under `data' when evoq replays them from the store,
%% where atom keys may also have become binaries. field/2 reads both.
-module(repo_state).

-behaviour(evoq_state).

-include("repo_status.hrl").

-export([new/1, apply_event/2, to_map/1]).
-export([repo_id/1, name/1, owner/1, status/1, is_public/1, is_archived/1]).

-record(repo_state, {
    repo_id        :: binary(),
    name           :: binary() | undefined,
    owner          :: binary() | undefined,
    description    :: binary() | undefined,
    default_branch :: binary() | undefined,
    tags           :: [binary()],
    status         :: non_neg_integer()
}).

-opaque t() :: #repo_state{}.
-export_type([t/0]).

-spec new(binary()) -> t().
new(RepoId) ->
    #repo_state{repo_id = RepoId, tags = [], status = 0}.

-spec apply_event(t(), map()) -> t().
apply_event(State, Event) ->
    do_apply(mcl_om_wire:field(event_type, Event), State, payload(Event)).

do_apply(<<"repo_initiated_v1">>, State, Data) ->
    Status = evoq_bit_flags:set(State#repo_state.status, ?REPO_INITIATED),
    State#repo_state{
        name           = mcl_om_wire:field(name, Data),
        owner          = mcl_om_wire:field(owner, Data),
        description    = mcl_om_wire:field(description, Data, <<>>),
        default_branch = mcl_om_wire:field(default_branch, Data, <<"main">>),
        tags           = mcl_om_wire:field(tags, Data, []),
        status         = visibility_flag(mcl_om_wire:field(visibility, Data), Status)
    };
do_apply(<<"repo_renamed_v1">>, State, Data) ->
    State#repo_state{name = mcl_om_wire:field(new_name, Data)};
do_apply(<<"repo_description_set_v1">>, State, Data) ->
    State#repo_state{description = mcl_om_wire:field(description, Data)};
do_apply(<<"repo_archived_v1">>, State, _Data) ->
    State#repo_state{status = evoq_bit_flags:set(State#repo_state.status, ?REPO_ARCHIVED)};
do_apply(_Other, State, _Data) ->
    State.

visibility_flag(<<"public">>, Status) -> evoq_bit_flags:set(Status, ?REPO_PUBLIC);
visibility_flag(_Private, Status)     -> Status.

payload(#{data := Data}) when is_map(Data)        -> Data;
payload(#{<<"data">> := Data}) when is_map(Data)  -> Data;
payload(Event)                                    -> Event.

-spec to_map(t()) -> map().
to_map(#repo_state{} = S) ->
    #{repo_id        => S#repo_state.repo_id,
      name           => S#repo_state.name,
      owner          => S#repo_state.owner,
      description    => S#repo_state.description,
      default_branch => S#repo_state.default_branch,
      tags           => S#repo_state.tags,
      status         => S#repo_state.status}.

-spec repo_id(t()) -> binary().
repo_id(#repo_state{repo_id = V}) -> V.

-spec name(t()) -> binary() | undefined.
name(#repo_state{name = V}) -> V.

-spec owner(t()) -> binary() | undefined.
owner(#repo_state{owner = V}) -> V.

-spec status(t()) -> non_neg_integer().
status(#repo_state{status = V}) -> V.

-spec is_public(t()) -> boolean().
is_public(#repo_state{status = S}) -> evoq_bit_flags:has(S, ?REPO_PUBLIC).

-spec is_archived(t()) -> boolean().
is_archived(#repo_state{status = S}) -> evoq_bit_flags:has(S, ?REPO_ARCHIVED).
