%% @doc Event: repo_archived_v1 -- final; the repository refuses everything after.
-module(repo_archived_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, to_map/1]).

event_type() -> <<"repo_archived_v1">>.

-spec new(map()) -> map().
new(#{repo_id := Id, reason := Reason}) ->
    #{event_type => event_type(), repo_id => Id, reason => Reason,
      archived_at => erlang:system_time(millisecond)}.

-spec to_map(map()) -> map().
to_map(Event) -> Event.
