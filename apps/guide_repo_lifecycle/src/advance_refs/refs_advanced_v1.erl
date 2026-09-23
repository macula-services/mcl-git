%% @doc Event: refs_advanced_v1 -- a push moved these refs.
-module(refs_advanced_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, to_map/1]).

event_type() -> <<"refs_advanced_v1">>.

-spec new(map()) -> map().
new(#{repo_id := Id, caller := Pusher, advances := Advances}) ->
    #{event_type => event_type(), repo_id => Id, pusher => Pusher,
      advances => Advances, advanced_at => erlang:system_time(millisecond)}.

-spec to_map(map()) -> map().
to_map(Event) -> Event.
