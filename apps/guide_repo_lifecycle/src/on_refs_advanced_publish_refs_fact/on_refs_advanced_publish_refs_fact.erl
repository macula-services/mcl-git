%% @doc PM: on refs_advanced_v1, announce the refs_advanced integration fact
%% on the mesh, so subscribers (mirrors, CI, a catalogue) learn a push landed.
-module(on_refs_advanced_publish_refs_fact).

-behaviour(evoq_event_handler).

-export([interested_in/0, init/1, handle_event/4, replay_policy/0]).

%% Announcing is a side effect in the world: replay would re-announce every
%% push ever made on every restart.
replay_policy() -> skip.

interested_in() -> [<<"refs_advanced_v1">>].

init(_Config) -> {ok, undefined}.

handle_event(<<"refs_advanced_v1">>, Event, _Metadata, State) ->
    ok = refs_fact:publish(maps:get(data, Event, Event)),
    {ok, State};
handle_event(_Other, _Event, _Metadata, State) ->
    {ok, State}.
