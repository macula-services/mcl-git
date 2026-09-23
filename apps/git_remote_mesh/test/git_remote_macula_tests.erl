%% @doc The mesh transport's own logic: the environment it dials with, and
%% the shape a macula 12 reply arrives in. A RESULT payload's keys come back
%% as CBOR text, `{text, <<"stdout">>}', never as atoms (macula's own
%% station_link suite asserts it), so the transport, not the helper, turns
%% that into the plain map the helper reads.
-module(git_remote_macula_tests).

-include_lib("eunit/include/eunit.hrl").

-define(ID1, "004d1f470097ccf8826ce291900e882fdb1f20375e53901facaec0f23eb4efd8").
-define(ID2, "00df68247d119685f94030afdb203ab7a2a105fb6093a964dbf0509a57e86435").

env_test_() ->
    {foreach, fun() -> ok end,
     fun(_) -> [os:unsetenv(V) || V <- ["MACULA_STATION_SEEDS", "MACULA_STATION_NODE_IDS",
                                         "MCL_GIT_REALM_KEY"]] end,
     [fun seeds_pair_index_for_index/0, fun seeds_need_a_pin_each/0,
      fun no_seeds_is_named/0, fun realm_key_is_required_hex/0]}.

seeds_pair_index_for_index() ->
    os:putenv("MACULA_STATION_SEEDS", "a.example, b.example:5000"),
    os:putenv("MACULA_STATION_NODE_IDS", ?ID1 "," ?ID2),
    ?assertEqual({ok, [#{host => <<"a.example">>, port => 4433,
                         expected_node_id => binary:decode_hex(<<?ID1>>)},
                       #{host => <<"b.example">>, port => 5000,
                         expected_node_id => binary:decode_hex(<<?ID2>>)}]},
                 git_remote_macula:seeds()).

seeds_need_a_pin_each() ->
    os:putenv("MACULA_STATION_SEEDS", "a.example,b.example"),
    os:putenv("MACULA_STATION_NODE_IDS", ?ID1),
    ?assertMatch({error, {missing_env, "MACULA_STATION_NODE_IDS" ++ _}}, git_remote_macula:seeds()).

no_seeds_is_named() ->
    ?assertEqual({error, {missing_env, "MACULA_STATION_SEEDS"}}, git_remote_macula:seeds()).

realm_key_is_required_hex() ->
    ?assertEqual({error, {missing_env, "MCL_GIT_REALM_KEY"}}, git_remote_macula:realm_key()),
    os:putenv("MCL_GIT_REALM_KEY", "zz"),
    ?assertEqual({error, {bad_env, "MCL_GIT_REALM_KEY"}}, git_remote_macula:realm_key()),
    os:putenv("MCL_GIT_REALM_KEY", "0aff"),
    ?assertEqual({ok, <<10, 255>>}, git_remote_macula:realm_key()).

a_wire_reply_becomes_the_plain_map_test() ->
    ?assertEqual({ok, #{stdout => <<"PACK">>}},
                 git_remote_macula:reply({ok, #{{text, <<"stdout">>} => <<"PACK">>}})),
    ?assertEqual({ok, #{stdout => <<"PACK">>}},
                 git_remote_macula:reply({ok, #{<<"stdout">> => <<"PACK">>}})),
    ?assertEqual({ok, #{stdout => <<"PACK">>}},
                 git_remote_macula:reply({ok, #{stdout => <<"PACK">>}})).

a_reply_without_stdout_is_refused_by_name_test() ->
    ?assertEqual({error, {unexpected_reply, #{{text, <<"x">>} => 1}}},
                 git_remote_macula:reply({ok, #{{text, <<"x">>} => 1}})).

%% A provider's refusal arrives with its code as a binary detail.
errors_pass_through_test() ->
    ?assertEqual({error, {call_error, <<"not_owner">>, <<>>}},
                 git_remote_macula:reply({error, {call_error, <<"not_owner">>, <<>>}})).
