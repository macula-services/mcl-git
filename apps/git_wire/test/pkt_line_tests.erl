-module(pkt_line_tests).

-include_lib("eunit/include/eunit.hrl").

encodes_data_with_its_own_length_test() ->
    ?assertEqual(<<"000bcommand">>, iolist_to_binary(pkt_line:encode(<<"command">>))),
    ?assertEqual(<<"0000">>, iolist_to_binary(pkt_line:flush())),
    ?assertEqual(<<"0001">>, iolist_to_binary(pkt_line:delim())).

decodes_a_stream_into_packets_test() ->
    Bin = iolist_to_binary([pkt_line:encode(<<"a\n">>), pkt_line:delim(),
                            pkt_line:encode(<<"bc">>), pkt_line:flush()]),
    ?assertEqual({ok, [{data, <<"a\n">>}, delim, {data, <<"bc">>}, flush]},
                 pkt_line:decode(Bin)).

refuses_a_truncated_stream_test() ->
    ?assertEqual({error, truncated}, pkt_line:decode(<<"000aab">>)),
    ?assertEqual({error, truncated}, pkt_line:decode(<<"00">>)).

refuses_a_bad_length_test() ->
    ?assertEqual({error, {bad_length, <<"zzzz">>}}, pkt_line:decode(<<"zzzz">>)),
    ?assertEqual({error, {bad_length, <<"0003">>}}, pkt_line:decode(<<"0003">>)).

refuses_an_oversized_packet_test() ->
    ?assertError({pkt_too_large, _}, pkt_line:encode(binary:copy(<<"x">>, 65517))).

%% Protocol v2's response-end packet.
decodes_response_end_test() ->
    ?assertEqual({ok, [{data, <<"a">>}, response_end]}, pkt_line:decode(<<"0005a0002">>)).
