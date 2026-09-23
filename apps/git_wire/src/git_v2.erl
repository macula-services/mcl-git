%% @doc Protocol v2 as `git upload-pack --stateless-rpc' speaks it (with
%% GIT_PROTOCOL=version=2): the ls-refs and fetch requests a client sends,
%% and what it needs out of the answers.
-module(git_v2).

-export([ls_refs_request/0, parse_ls_refs/1, fetch_request/1, fetch_request/2, packfile/1]).

-type ref() :: #{name := binary(), oid := binary(), symref_target := binary() | undefined}.
-export_type([ref/0]).

-spec ls_refs_request() -> binary().
ls_refs_request() ->
    iolist_to_binary([pkt_line:encode(<<"command=ls-refs\n">>),
                      pkt_line:delim(),
                      pkt_line:encode(<<"symrefs\n">>),
                      pkt_line:encode(<<"ref-prefix HEAD\n">>),
                      pkt_line:encode(<<"ref-prefix refs/heads/\n">>),
                      pkt_line:encode(<<"ref-prefix refs/tags/\n">>),
                      pkt_line:flush()]).

-spec parse_ls_refs(binary()) -> {ok, [ref()]} | {error, term()}.
parse_ls_refs(Bin) ->
    refs(pkt_line:decode(Bin)).

refs({ok, Packets}) -> {ok, [ref_line(strip_lf(D)) || {data, D} <- Packets]};
refs({error, _} = Err) -> Err.

ref_line(Line) ->
    [Oid, Name | Attrs] = binary:split(Line, <<" ">>, [global]),
    #{oid => Oid, name => Name, symref_target => symref(Attrs)}.

symref([<<"symref-target:", Target/binary>> | _]) -> Target;
symref([_ | Rest])                                -> symref(Rest);
symref([])                                        -> undefined.

%% @doc A fetch of everything `Wants' reaches. `done' up front: no
%% negotiation round, the server answers with the pack straight away. The
%% `Haves' let it leave out what the client holds; the pack may be thin,
%% so the client indexes it with --fix-thin.
-spec fetch_request([binary()]) -> binary().
fetch_request(Wants) -> fetch_request(Wants, []).

-spec fetch_request([binary()], [binary()]) -> binary().
fetch_request(Wants, Haves) ->
    iolist_to_binary([pkt_line:encode(<<"command=fetch\n">>),
                      pkt_line:delim(),
                      pkt_line:encode(<<"thin-pack\n">>),
                      pkt_line:encode(<<"ofs-delta\n">>),
                      pkt_line:encode(<<"no-progress\n">>),
                      [pkt_line:encode(<<"want ", W/binary, "\n">>) || W <- Wants],
                      [pkt_line:encode(<<"have ", H/binary, "\n">>) || H <- Haves],
                      pkt_line:encode(<<"done\n">>),
                      pkt_line:flush()]).

%% @doc The pack bytes out of a fetch response: the `packfile' section's
%% sideband channel 1, concatenated. Channel 2 is progress and is dropped;
%% channel 3 is the server giving up, and says why.
-spec packfile(binary()) -> {ok, binary()} | {error, term()}.
packfile(Bin) ->
    section(pkt_line:decode(Bin)).

section({ok, Packets}) -> after_marker(Packets);
section({error, _} = Err) -> Err.

after_marker([{data, <<"packfile\n">>} | Rest]) -> sideband(Rest, []);
after_marker([_ | Rest])                        -> after_marker(Rest);
after_marker([])                                -> {error, no_packfile}.

sideband([{data, <<1, Pack/binary>>} | Rest], Acc) -> sideband(Rest, [Pack | Acc]);
sideband([{data, <<2, _Progress/binary>>} | Rest], Acc) -> sideband(Rest, Acc);
sideband([{data, <<3, Why/binary>>} | _], _Acc) -> {error, {remote, strip_lf(Why)}};
sideband([flush | _], Acc) -> {ok, iolist_to_binary(lists:reverse(Acc))};
sideband([response_end | _], Acc) -> {ok, iolist_to_binary(lists:reverse(Acc))};
sideband([], Acc) -> {ok, iolist_to_binary(lists:reverse(Acc))};
sideband([Other | _], _Acc) -> {error, {unexpected_packet, Other}}.

strip_lf(Bin) -> string:trim(Bin, trailing, "\n").
