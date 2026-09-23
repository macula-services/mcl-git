%% @doc The push side of the smart protocol, as `git receive-pack
%% --stateless-rpc' speaks it: the ref advertisement, the update request
%% (commands, then the raw pack), and the report-status answer.
-module(git_push).

-export([parse_advertisement/1, request/2, parse_report/1]).

-type update() :: #{ref := binary(), old_oid := binary(), new_oid := binary()}.
-export_type([update/0]).

%% @doc Refs and capabilities from `receive-pack --advertise-refs'. An empty
%% repository advertises one placeholder line, `capabilities^{}', which
%% carries the capabilities and is not a ref.
-spec parse_advertisement(binary()) ->
    {ok, [#{name := binary(), oid := binary()}], [binary()]} | {error, term()}.
parse_advertisement(Bin) ->
    advertised(pkt_line:decode(Bin)).

advertised({ok, Packets}) ->
    Lines = [strip_lf(D) || {data, D} <- Packets],
    {ok, [R || R <- lists:map(fun ref/1, Lines), R =/= placeholder], caps(Lines)};
advertised({error, _} = Err) ->
    Err.

ref(Line) ->
    [RefPart | _Caps] = binary:split(Line, <<0>>),
    [Oid, Name] = binary:split(RefPart, <<" ">>),
    named(Name, Oid).

named(<<"capabilities^{}">>, _Oid) -> placeholder;
named(Name, Oid)                   -> #{name => Name, oid => Oid}.

caps([First | _]) -> caps_of(binary:split(First, <<0>>));
caps([])          -> [].

caps_of([_Ref, Caps]) -> binary:split(Caps, <<" ">>, [global, trim_all]);
caps_of([_Ref])       -> [].

%% @doc The update request. The first command carries the capabilities
%% asked for; only report-status, so the answer is a plain pkt-line list.
%% A request that only removes refs carries no pack.
-spec request([update()], binary()) -> binary().
request([First | Rest], Pack) ->
    iolist_to_binary([pkt_line:encode([command(First), 0, <<"report-status\n">>]),
                      [pkt_line:encode([command(U), $\n]) || U <- Rest],
                      pkt_line:flush(),
                      Pack]).

command(#{ref := Ref, old_oid := Old, new_oid := New}) ->
    <<Old/binary, " ", New/binary, " ", Ref/binary>>.

%% @doc What receive-pack says it did: whether the pack unpacked, then one
%% verdict per ref.
-spec parse_report(binary()) -> {ok, [{binary(), ok | {error, binary()}}]} | {error, term()}.
parse_report(Bin) ->
    reported(pkt_line:decode(Bin)).

reported({ok, Packets}) ->
    unpacked([strip_lf(D) || {data, D} <- Packets]);
reported({error, _} = Err) ->
    Err.

unpacked([<<"unpack ok">> | Refs]) -> {ok, [verdict(R) || R <- Refs]};
unpacked([<<"unpack ", Why/binary>> | _]) -> {error, {unpack, Why}};
unpacked(Other) -> {error, {bad_report, Other}}.

verdict(<<"ok ", Ref/binary>>) -> {Ref, ok};
verdict(<<"ng ", Rest/binary>>) ->
    [Ref, Why] = binary:split(Rest, <<" ">>),
    {Ref, {error, Why}}.

strip_lf(Bin) -> string:trim(Bin, trailing, "\n").
