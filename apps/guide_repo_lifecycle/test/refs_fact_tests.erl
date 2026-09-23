%% @doc The integration fact a push announces, and the process manager that
%% announces it. The domain event stays in this node's store; what goes on
%% the mesh is this explicit, stable shape.
-module(refs_fact_tests).

-include_lib("eunit/include/eunit.hrl").

-define(REPO, <<"repo-0190aaaabbbbccccddddeeeeffff0000">>).
-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).

topic_is_an_app_fact_owned_by_mcl_git_test() ->
    ?assertEqual(<<"io.macula/mcl-git/git/repos/refs_advanced_v1">>,
                 refs_fact:topic(<<"io.macula">>)).

fact_sends_text_as_text_test() ->
    Data = #{repo_id => ?REPO, pusher => ?OWNER, advanced_at => 7,
             advances => [#{ref => <<"refs/heads/main">>, old_oid => <<"0">>, new_oid => <<"1">>}]},
    ?assertEqual(#{repo_id => {text, ?REPO}, pusher => {text, ?OWNER}, advanced_at => 7,
                   advances => [#{ref => {text, <<"refs/heads/main">>},
                                  old_oid => {text, <<"0">>}, new_oid => {text, <<"1">>}}]},
                 refs_fact:fact(Data)).

%% Replayed events arrive with binary keys.
fact_reads_a_stored_event_test() ->
    Data = #{<<"repo_id">> => ?REPO, <<"pusher">> => ?OWNER, <<"advanced_at">> => 7,
             <<"advances">> => [#{<<"ref">> => <<"r">>, <<"old_oid">> => <<"0">>,
                                  <<"new_oid">> => <<"1">>}]},
    ?assertMatch(#{advances := [#{ref := {text, <<"r">>}}]}, refs_fact:fact(Data)).

realm_name_must_be_the_pools_realm_test() ->
    Tag = crypto:hash(sha256, <<"io.macula">>),
    ?assertEqual(ok, refs_fact:check_realm_name(<<"io.macula">>, Tag)),
    ?assertError({mcl_git_realm_name_mismatch, <<"other">>, Tag},
                 refs_fact:check_realm_name(<<"other">>, Tag)).

the_process_manager_skips_replay_test() ->
    %% Replay would re-announce every push ever made on every restart.
    ?assertEqual(skip, on_refs_advanced_publish_refs_fact:replay_policy()).

the_process_manager_publishes_the_event_test() ->
    meck:new(refs_fact, [passthrough]),
    meck:expect(refs_fact, publish, fun(_) -> ok end),
    try
        Data = #{repo_id => ?REPO, pusher => ?OWNER, advances => [], advanced_at => 1},
        {ok, s} = on_refs_advanced_publish_refs_fact:handle_event(
                    <<"refs_advanced_v1">>, #{event_type => <<"refs_advanced_v1">>, data => Data},
                    #{}, s),
        ?assert(meck:called(refs_fact, publish, [Data]))
    after
        meck:unload(refs_fact)
    end.
