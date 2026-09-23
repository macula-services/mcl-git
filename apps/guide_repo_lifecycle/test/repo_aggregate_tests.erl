%% @doc The repo aggregate's business rules, driven through execute/2 and
%% apply/2 exactly as evoq drives them, with no store underneath.
-module(repo_aggregate_tests).

-include_lib("eunit/include/eunit.hrl").

-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).
-define(STRANGER, <<"bb00000000000000000000000000000000000000000000000000000000000000">>).
-define(REPO, <<"repo-0190aaaabbbbccccddddeeeeffff0000">>).

initiate_payload() ->
    {ok, Cmd} = initiate_repo_v1:new(#{name => <<"dotfiles">>, owner => ?OWNER,
                                       description => <<"my config">>,
                                       visibility => <<"public">>,
                                       tags => [<<"config">>]}),
    initiate_repo_v1:to_map(Cmd).

initiated() ->
    Payload = initiate_payload(),
    {ok, State0} = repo_aggregate:init(maps:get(repo_id, Payload)),
    {ok, Events} = repo_aggregate:execute(State0, Payload),
    {maps:get(repo_id, Payload), fold(State0, Events)}.

fold(State, Events) ->
    lists:foldl(fun(E, S) -> repo_aggregate:apply(S, E) end, State, Events).

initiate_mints_a_repo_stream_id_test() ->
    #{repo_id := RepoId} = initiate_payload(),
    ?assertMatch(<<"repo-", _:32/binary>>, RepoId).

initiate_emits_repo_initiated_test() ->
    Payload = initiate_payload(),
    {ok, State0} = repo_aggregate:init(maps:get(repo_id, Payload)),
    {ok, [Event]} = repo_aggregate:execute(State0, Payload),
    ?assertEqual(<<"repo_initiated_v1">>, maps:get(event_type, Event)),
    ?assertEqual(?OWNER, maps:get(owner, Event)),
    ?assertEqual(<<"main">>, maps:get(default_branch, Event)).

initiate_twice_is_refused_test() ->
    {_RepoId, State} = initiated(),
    ?assertEqual({error, already_initiated},
                 repo_aggregate:execute(State, initiate_payload())).

initiate_refuses_an_unknown_visibility_test() ->
    ?assertEqual({error, invalid_visibility},
                 initiate_repo_v1:new(#{name => <<"x">>, owner => ?OWNER,
                                        visibility => <<"everyone">>})).

initiate_requires_name_and_owner_test() ->
    ?assertEqual({error, name_and_owner_required}, initiate_repo_v1:new(#{name => <<"x">>})),
    ?assertEqual({error, name_and_owner_required},
                 initiate_repo_v1:new(#{name => <<>>, owner => ?OWNER})).

public_visibility_sets_the_public_flag_test() ->
    {_RepoId, State} = initiated(),
    ?assert(repo_state:is_public(State)),
    ?assertEqual(?OWNER, repo_state:owner(State)).

owner_renames_test() ->
    {RepoId, State} = initiated(),
    {ok, [Event]} = repo_aggregate:execute(State, rename(RepoId, ?OWNER, <<"config">>)),
    ?assertEqual(<<"repo_renamed_v1">>, maps:get(event_type, Event)),
    ?assertEqual(<<"config">>, repo_state:name(fold(State, [Event]))).

a_stranger_may_not_rename_test() ->
    {RepoId, State} = initiated(),
    ?assertEqual({error, not_owner},
                 repo_aggregate:execute(State, rename(RepoId, ?STRANGER, <<"mine">>))).

rename_before_initiate_is_refused_test() ->
    {ok, State0} = repo_aggregate:init(?REPO),
    ?assertEqual({error, not_initiated},
                 repo_aggregate:execute(State0, rename(?REPO, ?OWNER, <<"x">>))).

owner_sets_description_test() ->
    {RepoId, State} = initiated(),
    {ok, Cmd} = set_repo_description_v1:new(#{repo_id => RepoId, caller => ?OWNER,
                                              description => <<"new words">>}),
    {ok, [Event]} = repo_aggregate:execute(State, set_repo_description_v1:to_map(Cmd)),
    ?assertEqual(<<"repo_description_set_v1">>, maps:get(event_type, Event)).

archive_then_everything_is_refused_test() ->
    {RepoId, State} = initiated(),
    {ok, Arch} = archive_repo_v1:new(#{repo_id => RepoId, caller => ?OWNER}),
    {ok, Events} = repo_aggregate:execute(State, archive_repo_v1:to_map(Arch)),
    Archived = fold(State, Events),
    ?assert(repo_state:is_archived(Archived)),
    ?assertEqual({error, archived},
                 repo_aggregate:execute(Archived, rename(RepoId, ?OWNER, <<"y">>))),
    ?assertEqual({error, archived},
                 repo_aggregate:execute(Archived, archive_repo_v1:to_map(Arch))).

a_stranger_may_not_archive_test() ->
    {RepoId, State} = initiated(),
    {ok, Arch} = archive_repo_v1:new(#{repo_id => RepoId, caller => ?STRANGER}),
    ?assertEqual({error, not_owner},
                 repo_aggregate:execute(State, archive_repo_v1:to_map(Arch))).

owner_advances_refs_test() ->
    {RepoId, State} = initiated(),
    Advances = [#{ref => <<"refs/heads/main">>,
                  old_oid => <<"0000000000000000000000000000000000000000">>,
                  new_oid => <<"1111111111111111111111111111111111111111">>}],
    {ok, Cmd} = advance_refs_v1:new(#{repo_id => RepoId, caller => ?OWNER,
                                      advances => Advances}),
    {ok, [Event]} = repo_aggregate:execute(State, advance_refs_v1:to_map(Cmd)),
    ?assertEqual(<<"refs_advanced_v1">>, maps:get(event_type, Event)),
    ?assertEqual(Advances, maps:get(advances, Event)).

advance_refs_needs_at_least_one_advance_test() ->
    ?assertEqual({error, no_advances},
                 advance_refs_v1:new(#{repo_id => ?REPO, caller => ?OWNER, advances => []})).

a_stranger_may_not_advance_refs_test() ->
    {RepoId, State} = initiated(),
    {ok, Cmd} = advance_refs_v1:new(#{repo_id => RepoId, caller => ?STRANGER,
                                      advances => [#{ref => <<"refs/heads/x">>,
                                                     old_oid => <<"0">>, new_oid => <<"1">>}]}),
    ?assertEqual({error, not_owner}, repo_aggregate:execute(State, advance_refs_v1:to_map(Cmd))).

%% evoq hands a replayed event back with its fields under `data', and a
%% round trip through the store may turn atom keys into binaries.
replayed_events_fold_like_live_ones_test() ->
    {_RepoId, Live} = initiated(),
    Payload = initiate_payload(),
    {ok, State0} = repo_aggregate:init(maps:get(repo_id, Payload)),
    {ok, [Event]} = repo_aggregate:execute(State0, Payload),
    Stored = #{event_type => <<"repo_initiated_v1">>,
               data => maps:fold(fun(K, V, Acc) -> Acc#{atom_to_binary(K) => V} end,
                                 #{}, maps:remove(event_type, Event))},
    Replayed = repo_aggregate:apply(State0, Stored),
    ?assertEqual(repo_state:owner(Live), repo_state:owner(Replayed)),
    ?assert(repo_state:is_public(Replayed)).

rename(RepoId, Caller, NewName) ->
    {ok, Cmd} = rename_repo_v1:new(#{repo_id => RepoId, caller => Caller, new_name => NewName}),
    rename_repo_v1:to_map(Cmd).

%% Every field initiate stores is typed: a repo whose default branch is not a
%% ref name could never be made on disk, and the event cannot be undone.
initiate_refuses_badly_typed_fields_test() ->
    Base = #{name => <<"x">>, owner => ?OWNER},
    ?assertEqual({error, invalid_default_branch}, initiate_repo_v1:new(Base#{default_branch => 42})),
    ?assertEqual({error, invalid_default_branch},
                 initiate_repo_v1:new(Base#{default_branch => <<"-x">>})),
    ?assertEqual({error, invalid_default_branch},
                 initiate_repo_v1:new(Base#{default_branch => <<"a b">>})),
    ?assertEqual({error, invalid_description}, initiate_repo_v1:new(Base#{description => 7})),
    ?assertEqual({error, invalid_tags}, initiate_repo_v1:new(Base#{tags => [<<"ok">>, 3]})),
    ?assertEqual({error, invalid_tags}, initiate_repo_v1:new(Base#{tags => <<"notalist">>})),
    ?assertMatch({ok, _}, initiate_repo_v1:new(Base#{default_branch => <<"release/1.x">>})).
