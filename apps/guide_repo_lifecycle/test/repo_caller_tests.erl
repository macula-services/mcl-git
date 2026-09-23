-module(repo_caller_tests).

-include_lib("eunit/include/eunit.hrl").

a_node_key_id_becomes_lowercase_hex_test() ->
    ?assertEqual(<<"ab", (binary:copy(<<"00">>, 31))/binary>>,
                 repo_caller:id(#{caller => <<16#ab, 0:248>>})).

no_caller_is_no_identity_test() ->
    ?assertEqual(undefined, repo_caller:id(#{})),
    ?assertEqual(undefined, repo_caller:id(<<"not a map">>)).

a_caller_that_is_not_a_key_id_is_no_identity_test() ->
    ?assertEqual(undefined, repo_caller:id(#{caller => <<"short">>})).
