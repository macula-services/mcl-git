%% @doc Event: repo_initiated_v1 -- a repository's dossier was opened.
-module(repo_initiated_v1).

-behaviour(evoq_event).

-export([event_type/0, new/1, to_map/1]).

event_type() -> <<"repo_initiated_v1">>.

%% @doc Built from the initiate_repo_v1 command map.
-spec new(map()) -> map().
new(#{repo_id := Id, name := Name, owner := Owner, description := Desc,
      default_branch := Branch, visibility := Vis, tags := Tags}) ->
    #{event_type     => event_type(),
      repo_id        => Id,
      name           => Name,
      owner          => Owner,
      description    => Desc,
      default_branch => Branch,
      visibility     => Vis,
      tags           => Tags,
      initiated_at   => erlang:system_time(millisecond)}.

-spec to_map(map()) -> map().
to_map(Event) -> Event.
