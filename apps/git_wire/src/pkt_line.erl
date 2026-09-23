%% @doc git's pkt-line framing: four hex digits of length (counting
%% themselves), then the payload. `0000' is a flush, `0001' a delimiter
%% (protocol v2), `0002' the end of a response (v2).
-module(pkt_line).

-export([encode/1, flush/0, delim/0, decode/1]).

-type packet() :: {data, binary()} | flush | delim | response_end.
-export_type([packet/0]).

%% git's own ceiling: 65520 bytes per packet, header included.
-define(MAX_DATA, 65516).

-spec encode(iodata()) -> iodata().
encode(Data) ->
    Size = iolist_size(Data),
    sized(Size =< ?MAX_DATA, Size, Data).

sized(true, Size, Data) -> [io_lib:format("~4.16.0b", [Size + 4]), Data];
sized(false, Size, _)   -> error({pkt_too_large, Size}).

-spec flush() -> iodata().
flush() -> <<"0000">>.

-spec delim() -> iodata().
delim() -> <<"0001">>.

%% @doc The packets in a complete stream, in order.
-spec decode(binary()) -> {ok, [packet()]} | {error, term()}.
decode(Bin) -> decode(Bin, []).

decode(<<>>, Acc) ->
    {ok, lists:reverse(Acc)};
decode(<<Hex:4/binary, Rest/binary>>, Acc) ->
    packet(length_of(Hex), Hex, Rest, Acc);
decode(_Short, _Acc) ->
    {error, truncated}.

packet(0, _Hex, Rest, Acc) -> decode(Rest, [flush | Acc]);
packet(1, _Hex, Rest, Acc) -> decode(Rest, [delim | Acc]);
packet(2, _Hex, Rest, Acc) -> decode(Rest, [response_end | Acc]);
packet(Len, _Hex, Rest, Acc) when is_integer(Len), Len >= 4 ->
    body(Len - 4, Rest, Acc);
packet(_Bad, Hex, _Rest, _Acc) ->
    {error, {bad_length, Hex}}.

body(Size, Rest, Acc) when byte_size(Rest) >= Size ->
    <<Data:Size/binary, Tail/binary>> = Rest,
    decode(Tail, [{data, Data} | Acc]);
body(_Size, _Rest, _Acc) ->
    {error, truncated}.

length_of(Hex) ->
    try binary_to_integer(Hex, 16) catch error:badarg -> bad end.
