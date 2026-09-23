%% @doc The repos read model: the projection folds lifecycle events into
%% rows, and repo_access decides who may see or change a row.
-module(project_repos_tests).

-include_lib("eunit/include/eunit.hrl").

-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).
-define(STRANGER, <<"bb00000000000000000000000000000000000000000000000000000000000000">>).
-define(REPO, <<"repo-0190aaaabbbbccccddddeeeeffff0000">>).

projection_test_() ->
    {foreach,
     fun() -> {ok, Pid} = project_repos_store:start_link(), unlink(Pid), Pid end,
     fun(Pid) -> exit(Pid, kill), timer:sleep(10) end,
     [fun initiated_row/0, fun renamed_and_described/0, fun archived_row/0,
      fun refs_advanced_row/0, fun stored_shape_is_read_too/0,
      fun lists_by_owner_and_tag/0]}.

project(Type, Data) ->
    {ok, _, _} = repo_lifecycle_to_repos:project(#{event_type => Type, data => Data}, #{},
                                                   #{}, rm),
    ok.

initiate(Visibility) ->
    project(<<"repo_initiated_v1">>,
            #{repo_id => ?REPO, name => <<"dotfiles">>, owner => ?OWNER,
              description => <<"cfg">>, default_branch => <<"main">>,
              visibility => Visibility, tags => [<<"config">>], initiated_at => 1}).

initiated_row() ->
    initiate(<<"public">>),
    {ok, Row} = project_repos_store:get(?REPO),
    ?assertMatch(#{repo_id := ?REPO, name := <<"dotfiles">>, owner := ?OWNER,
                   visibility := <<"public">>, status := <<"active">>,
                   default_branch := <<"main">>, tags := [<<"config">>]}, Row).

renamed_and_described() ->
    initiate(<<"private">>),
    project(<<"repo_renamed_v1">>, #{repo_id => ?REPO, new_name => <<"config">>}),
    project(<<"repo_description_set_v1">>, #{repo_id => ?REPO, description => <<"words">>}),
    {ok, Row} = project_repos_store:get(?REPO),
    ?assertMatch(#{name := <<"config">>, description := <<"words">>}, Row).

archived_row() ->
    initiate(<<"private">>),
    project(<<"repo_archived_v1">>, #{repo_id => ?REPO, reason => <<>>}),
    ?assertMatch({ok, #{status := <<"archived">>}}, project_repos_store:get(?REPO)).

refs_advanced_row() ->
    initiate(<<"private">>),
    project(<<"refs_advanced_v1">>, #{repo_id => ?REPO, pusher => ?OWNER, advanced_at => 42,
                                      advances => [#{ref => <<"refs/heads/main">>,
                                                     old_oid => <<"0">>, new_oid => <<"1">>}]}),
    ?assertMatch({ok, #{last_pushed_at := 42}}, project_repos_store:get(?REPO)).

%% A replayed event arrives with binary keys.
stored_shape_is_read_too() ->
    project(<<"repo_initiated_v1">>,
            #{<<"repo_id">> => ?REPO, <<"name">> => <<"n">>, <<"owner">> => ?OWNER,
              <<"description">> => <<>>, <<"default_branch">> => <<"trunk">>,
              <<"visibility">> => <<"public">>, <<"tags">> => [], <<"initiated_at">> => 1}),
    ?assertMatch({ok, #{default_branch := <<"trunk">>}}, project_repos_store:get(?REPO)).

lists_by_owner_and_tag() ->
    initiate(<<"public">>),
    ?assertMatch([#{repo_id := ?REPO}], project_repos_store:list_by_owner(?OWNER)),
    ?assertEqual([], project_repos_store:list_by_owner(?STRANGER)),
    ?assertMatch([#{repo_id := ?REPO}], project_repos_store:list_by_tag(<<"config">>)),
    ?assertEqual([], project_repos_store:list_by_tag(<<"other">>)).

row(Visibility, Status) ->
    #{repo_id => ?REPO, owner => ?OWNER, visibility => Visibility, status => Status}.

anyone_reads_a_public_repo_test() ->
    ?assertEqual(ok, repo_access:may_read(row(<<"public">>, <<"active">>), ?STRANGER)).

only_the_owner_reads_a_private_repo_test() ->
    ?assertEqual(ok, repo_access:may_read(row(<<"private">>, <<"active">>), ?OWNER)),
    %% not_found, not "forbidden": a stranger learns nothing about a private repo.
    ?assertEqual({error, not_found}, repo_access:may_read(row(<<"private">>, <<"active">>), ?STRANGER)).

nobody_reads_without_an_identity_test() ->
    ?assertEqual({error, not_found}, repo_access:may_read(row(<<"private">>, <<"active">>), undefined)).

an_archived_repo_is_read_only_history_test() ->
    ?assertEqual(ok, repo_access:may_read(row(<<"public">>, <<"archived">>), ?STRANGER)),
    ?assertEqual({error, archived}, repo_access:may_write(row(<<"public">>, <<"archived">>), ?OWNER)).

only_the_owner_writes_test() ->
    ?assertEqual(ok, repo_access:may_write(row(<<"public">>, <<"active">>), ?OWNER)),
    ?assertEqual({error, not_owner}, repo_access:may_write(row(<<"public">>, <<"active">>), ?STRANGER)),
    ?assertEqual({error, not_found}, repo_access:may_write(row(<<"private">>, <<"active">>), ?STRANGER)).
