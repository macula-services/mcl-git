%% @doc The mesh transport: a macula pool dialled to pinned stations, trusting
%% the realm's signing key, calling `mcl-git/<procedure>' by direct dial.
%%
%% Configured from the environment git passes the helper:
%%
%%   MACULA_STATION_SEEDS     host[:port],...  (port defaults to 4433)
%%   MACULA_STATION_NODE_IDS  the stations' node ids, 64 hex, index for index
%%   MCL_GIT_REALM_KEY        the realm's public signing key, hex
%%
%% The pool uses this machine's ONE stored macula identity (macula's
%% node_identity_path), never a fresh one: the node id is who owns a
%% repository and who may push to it, so it must be the same on every run.
-module(git_remote_macula).

-export([connect/1, call/3, initiate/2]).
%% The pieces with no network in them, exported for their tests.
-export([seeds/0, realm_key/0, reply/1, repo_id/1, call_timeout_ms/0]).

%% After the server's handler deadline (300 s, mcl_git_service), so a slow
%% git run reaches the caller as its real outcome, never as a local timeout.
-define(CALL_TIMEOUT_MS, 330000).
-define(HEALTHY_WAIT_MS, 30000).

-spec connect(#{realm_name := binary(), _ => _}) -> {ok, {pid(), binary()}} | {error, term()}.
connect(#{realm_name := RealmName}) ->
    {ok, _} = application:ensure_all_started(macula),
    Realm = macula_realm:id(RealmName),
    with_env(seeds(), realm_key(), Realm).

with_env({ok, Seeds}, {ok, RealmKey}, Realm) ->
    pooled(macula:connect(Seeds, #{realm_trust => #{Realm => RealmKey}}), Realm);
with_env({error, _} = E, _Key, _Realm) -> E;
with_env(_Seeds, {error, _} = E, _Realm) -> E.

pooled({ok, Pool}, Realm) -> healthy(wait_healthy(Pool, ?HEALTHY_WAIT_MS div 100), Pool, Realm);
pooled({error, _} = E, _Realm) -> E.

healthy(ok, Pool, Realm)         -> {ok, {Pool, Realm}};
healthy({error, _} = E, _P, _R)  -> E.

wait_healthy(_Pool, 0) -> {error, no_healthy_station};
wait_healthy(Pool, N) ->
    ready(macula_client:status(Pool), Pool, N).

ready({ok, #{healthy_links := H}}, _Pool, _N) when H > 0 -> ok;
ready(_Status, Pool, N) ->
    timer:sleep(100),
    wait_healthy(Pool, N - 1).

-spec call_timeout_ms() -> pos_integer().
call_timeout_ms() -> ?CALL_TIMEOUT_MS.

-spec call({pid(), binary()}, binary(), map()) -> {ok, map()} | {error, term()}.
call({Pool, Realm}, Procedure, Payload) ->
    reply(macula:call(Pool, Realm, Procedure, wire(Payload), ?CALL_TIMEOUT_MS)).

%% @doc A reply as the helper reads it. macula 12 hands a RESULT's keys back
%% as CBOR text, `{text, <<"stdout">>}', not atoms; the git bytes are the
%% value, as sent.
-spec reply({ok, term()} | {error, term()}) -> {ok, #{stdout := binary()}} | {error, term()}.
reply({ok, #{{text, <<"stdout">>} := Out}}) -> {ok, #{stdout => Out}};
reply({ok, #{<<"stdout">> := Out}})         -> {ok, #{stdout => Out}};
reply({ok, #{stdout := Out}})               -> {ok, #{stdout => Out}};
reply({ok, Other})                          -> {error, {unexpected_reply, Other}};
reply({error, _} = Err)                     -> Err.

%% @doc mcl-git/initiate_repo as this machine's node: its answer is the
%% minted repo id.
-spec initiate({pid(), binary()}, map()) -> {ok, binary()} | {error, term()}.
initiate({Pool, Realm}, Params) ->
    repo_id(macula:call(Pool, Realm, <<"mcl-git/initiate_repo">>,
                        maps:map(fun(_K, V) -> {text, V} end, Params), 60000)).

%% @doc The repo id out of initiate_repo's reply, as macula 12 carries it
%% (CBOR text key and value).
-spec repo_id({ok, term()} | {error, term()}) -> {ok, binary()} | {error, term()}.
repo_id({ok, #{{text, <<"repo_id">>} := {text, Id}}}) -> {ok, Id};
repo_id({ok, #{{text, <<"repo_id">>} := Id}}) when is_binary(Id) -> {ok, Id};
repo_id({ok, #{repo_id := {text, Id}}}) -> {ok, Id};
repo_id({ok, #{repo_id := Id}}) when is_binary(Id) -> {ok, Id};
repo_id({ok, Other}) -> {error, {unexpected_reply, Other}};
repo_id({error, _} = Err) -> Err.

%% The repo id is text on the wire; the git bytes stay bytes.
wire(#{repo_id := Id} = Payload) -> Payload#{repo_id => {text, Id}}.

-spec seeds() -> {ok, [map()]} | {error, term()}.
seeds() ->
    paired(csv("MACULA_STATION_SEEDS"), csv("MACULA_STATION_NODE_IDS")).

paired([], _Ids) -> {error, {missing_env, "MACULA_STATION_SEEDS"}};
paired(Hosts, Ids) when length(Hosts) =:= length(Ids) ->
    {ok, [seed(H, I) || {H, I} <- lists:zip(Hosts, Ids)]};
paired(_Hosts, _Ids) ->
    {error, {missing_env, "MACULA_STATION_NODE_IDS (one node id per seed)"}}.

seed(Host, IdHex) ->
    {Name, Port} = host_port(string:split(Host, ":")),
    #{host => list_to_binary(Name), port => Port, expected_node_id => binary:decode_hex(list_to_binary(IdHex))}.

host_port([Name])       -> {Name, 4433};
host_port([Name, Port]) -> {Name, list_to_integer(Port)}.

-spec realm_key() -> {ok, binary()} | {error, term()}.
realm_key() -> key(os:getenv("MCL_GIT_REALM_KEY")).

key(false) -> {error, {missing_env, "MCL_GIT_REALM_KEY"}};
key("")    -> {error, {missing_env, "MCL_GIT_REALM_KEY"}};
key(Hex)   -> decoded(re:run(Hex, "^([0-9a-fA-F]{2})+$", [{capture, none}]), Hex).

decoded(match, Hex)   -> {ok, binary:decode_hex(list_to_binary(Hex))};
decoded(nomatch, _Hex) -> {error, {bad_env, "MCL_GIT_REALM_KEY"}}.

csv(Name) -> [T || T <- string:lexemes(env(os:getenv(Name)), ", ")].

env(false) -> "";
env(V)     -> V.
