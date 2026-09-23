%% @doc Command: advance_refs_v1 -- records the refs a push moved.
%%
%% git is the source of truth for refs: receive-pack has already moved them
%% on disk when this is dispatched. The command records WHO moved WHICH refs
%% from where to where, so the dossier carries the history and the fact
%% publisher can tell the mesh.
-module(advance_refs_v1).

-behaviour(evoq_command).

-export([command_type/0, new/1, to_map/1, repo_id/1]).

-type advance() :: #{ref := binary(), old_oid := binary(), new_oid := binary()}.
-export_type([advance/0]).

-record(advance_refs_v1, {repo_id :: binary(), caller :: binary(), advances :: [advance()]}).

-opaque t() :: #advance_refs_v1{}.
-export_type([t/0]).

command_type() -> advance_refs.

-spec new(map()) -> {ok, t()} | {error, term()}.
new(#{advances := []}) ->
    {error, no_advances};
new(#{repo_id := Id, caller := Caller, advances := Advances})
  when is_binary(Id), is_binary(Caller), is_list(Advances) ->
    {ok, #advance_refs_v1{repo_id = Id, caller = Caller, advances = Advances}};
new(_) ->
    {error, invalid_advance_refs}.

-spec to_map(t()) -> map().
to_map(#advance_refs_v1{repo_id = Id, caller = Caller, advances = Advances}) ->
    #{command_type => command_type(), repo_id => Id, caller => Caller, advances => Advances}.

-spec repo_id(t()) -> binary().
repo_id(#advance_refs_v1{repo_id = V}) -> V.
