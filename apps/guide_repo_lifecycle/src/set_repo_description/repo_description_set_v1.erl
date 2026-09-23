%% @doc Event: repo_description_set_v1.
-module(repo_description_set_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, to_map/1]).

event_type() -> <<"repo_description_set_v1">>.

-spec new(map()) -> map().
new(#{repo_id := Id, description := Desc}) ->
    #{event_type => event_type(), repo_id => Id, description => Desc,
      set_at => erlang:system_time(millisecond)}.

-spec to_map(map()) -> map().
to_map(Event) -> Event.
