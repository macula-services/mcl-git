%% @doc Projection: the repo lifecycle events -> the repos read model.
%%
%% The evoq_read_model handle is a checkpoint passthrough; the rows live in
%% project_repos_store. Event fields sit under `data', and keys may be atoms
%% or binaries after a round trip through the store: mcl_om_wire:field/2,3
%% reads both.
-module(repo_lifecycle_to_repos).

-behaviour(evoq_projection).

-export([interested_in/0, init/1, project/4]).

-import(mcl_om_wire, [field/2, field/3]).

interested_in() ->
    [<<"repo_initiated_v1">>, <<"repo_renamed_v1">>, <<"repo_description_set_v1">>,
     <<"repo_archived_v1">>, <<"refs_advanced_v1">>].

init(_Config) ->
    {ok, RM} = evoq_read_model:new(evoq_read_model_ets, #{name => mcl_git_repos_projection}),
    {ok, #{}, RM}.

project(#{event_type := Type, data := Data}, _Metadata, State, RM) ->
    ok = row(Type, field(repo_id, Data), Data),
    {ok, State, RM}.

row(<<"repo_initiated_v1">>, RepoId, D) ->
    project_repos_store:put(RepoId, #{
        repo_id        => RepoId,
        name           => field(name, D),
        owner          => field(owner, D),
        description    => field(description, D, <<>>),
        default_branch => field(default_branch, D, <<"main">>),
        visibility     => field(visibility, D, <<"private">>),
        tags           => field(tags, D, []),
        status         => <<"active">>,
        initiated_at   => field(initiated_at, D),
        last_pushed_at => undefined});
row(<<"repo_renamed_v1">>, RepoId, D) ->
    project_repos_store:revise(RepoId, #{name => field(new_name, D)});
row(<<"repo_description_set_v1">>, RepoId, D) ->
    project_repos_store:revise(RepoId, #{description => field(description, D)});
row(<<"repo_archived_v1">>, RepoId, _D) ->
    project_repos_store:revise(RepoId, #{status => <<"archived">>});
row(<<"refs_advanced_v1">>, RepoId, D) ->
    project_repos_store:revise(RepoId, #{last_pushed_at => field(advanced_at, D)}).
