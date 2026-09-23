%% @doc The four lifecycle procedures, driven as macula_response drives them.
%% meck stands in for the dispatch, so a test sees exactly the command a
%% responder built, and that the caller came from the wire, never the payload.
-module(repo_lifecycle_responders_tests).

-include_lib("eunit/include/eunit.hrl").

-define(OWNER_KEY, <<16#aa, 0:248>>).
-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).
-define(OTHER_KEY, <<16#bb, 0:248>>).
-define(REPO, <<"repo-0190aaaabbbbccccddddeeeeffff0000">>).

responders_test_() ->
    {foreach,
     fun() ->
         meck:new([maybe_initiate_repo, maybe_rename_repo, maybe_set_repo_description,
                   maybe_archive_repo], [passthrough]),
         meck:expect(maybe_initiate_repo, dispatch, fun(_) -> {ok, ?REPO} end),
         [meck:expect(M, dispatch, fun(_) -> ok end)
          || M <- [maybe_rename_repo, maybe_set_repo_description, maybe_archive_repo]],
         application:set_env(guide_repo_lifecycle, initiators, [?OWNER])
     end,
     fun(_) -> meck:unload(), application:unset_env(guide_repo_lifecycle, initiators) end,
     [fun initiator_initiates/0, fun non_initiator_is_refused/0,
      fun empty_allowlist_refuses_everyone/0, fun payload_cannot_claim_an_owner/0,
      fun rename_carries_the_wire_caller/0, fun refusals_pass_through/0,
      fun no_caller_is_unauthenticated/0, fun text_values_are_unwrapped/0]}.

call(Mod, Payload, Caller) ->
    {ok, S} = Mod:init([]),
    strip(Mod:handle_request(Payload#{caller => Caller}, S)).

strip({reply, R, _}) -> {reply, R};
strip({error, E, _}) -> {error, E}.

initiator_initiates() ->
    ?assertEqual({reply, #{repo_id => {text, ?REPO}}},
                 call(initiate_repo_responder, #{name => <<"dotfiles">>}, ?OWNER_KEY)),
    ?assert(meck:called(maybe_initiate_repo, dispatch,
                        [#{name => <<"dotfiles">>, owner => ?OWNER, description => <<>>,
                           visibility => <<"private">>, default_branch => <<"main">>,
                           tags => []}])).

non_initiator_is_refused() ->
    ?assertEqual({error, not_an_initiator},
                 call(initiate_repo_responder, #{name => <<"x">>}, ?OTHER_KEY)),
    ?assertNot(meck:called(maybe_initiate_repo, dispatch, '_')).

empty_allowlist_refuses_everyone() ->
    application:set_env(guide_repo_lifecycle, initiators, []),
    ?assertEqual({error, not_an_initiator},
                 call(initiate_repo_responder, #{name => <<"x">>}, ?OWNER_KEY)).

%% `owner' in the payload is ignored: the owner is whoever the wire says called.
payload_cannot_claim_an_owner() ->
    {reply, _} = call(initiate_repo_responder, #{name => <<"x">>, owner => <<"someone">>}, ?OWNER_KEY),
    ?assert(meck:called(maybe_initiate_repo, dispatch, [#{name => <<"x">>, owner => ?OWNER,
                                                          description => <<>>,
                                                          visibility => <<"private">>,
                                                          default_branch => <<"main">>,
                                                          tags => []}])).

rename_carries_the_wire_caller() ->
    ?assertEqual({reply, #{status => {text, <<"accepted">>}}},
                 call(rename_repo_responder, #{repo_id => ?REPO, new_name => <<"n">>}, ?OTHER_KEY)),
    ?assert(meck:called(maybe_rename_repo, dispatch,
                        [#{repo_id => ?REPO, new_name => <<"n">>,
                           caller => binary:encode_hex(?OTHER_KEY, lowercase)}])).

refusals_pass_through() ->
    meck:expect(maybe_archive_repo, dispatch, fun(_) -> {error, not_owner} end),
    ?assertEqual({error, not_owner},
                 call(archive_repo_responder, #{repo_id => ?REPO}, ?OTHER_KEY)).

no_caller_is_unauthenticated() ->
    {ok, S} = set_repo_description_responder:init([]),
    ?assertMatch({error, unauthenticated, _},
                 set_repo_description_responder:handle_request(#{repo_id => ?REPO,
                                                                 description => <<"d">>}, S)).

%% A non-BEAM caller's strings arrive as CBOR text, {text, Bin}.
text_values_are_unwrapped() ->
    {reply, _} = call(set_repo_description_responder,
                      #{<<"repo_id">> => {text, ?REPO}, <<"description">> => {text, <<"d">>}},
                      ?OWNER_KEY),
    ?assert(meck:called(maybe_set_repo_description, dispatch,
                        [#{repo_id => ?REPO, description => <<"d">>, caller => ?OWNER}])).
