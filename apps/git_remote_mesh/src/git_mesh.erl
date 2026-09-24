%% @doc `git mesh': the user-facing commands. git runs `git-mesh' on PATH for
%% `git mesh <command>', as it runs any `git-<name>'.
%%
%%   git mesh whoami
%%       This machine's node id: its one stored macula identity, the owner of
%%       every repository it initiates. An mcl-git operator lists it in
%%       MCL_GIT_INITIATORS before this machine may initiate there.
%%
%%   git mesh init <name> [--public] [--description <text>]
%%                        [--default-branch <branch>] [--realm <realm-name>]
%%       Initiate a repository on the mcl-git serving the realm (default
%%       io.macula), owned by this machine's node, and print its URL:
%%       `git clone "$(git mesh init dotfiles)"'.
%%
%% stdout carries only the answer; everything else goes to stderr.
-module(git_mesh).

-export([main/0, parse/1, describe/2]).

-define(DEFAULT_REALM, <<"io.macula">>).

-spec main() -> no_return().
main() ->
    finish(run(parse(init:get_plain_arguments()))).

-spec parse([string()]) -> whoami | {init, binary(), map()} | {error, usage}.
parse(["whoami"])        -> whoami;
parse(["init", Name | Opts]) when Name =/= "", hd(Name) =/= $- ->
    options(Opts, ?DEFAULT_REALM, #{name => list_to_binary(Name), visibility => <<"private">>});
parse(_)                 -> {error, usage}.

options([], Realm, Params)                          -> {init, Realm, Params};
options(["--public" | T], Realm, P)                 -> options(T, Realm, P#{visibility => <<"public">>});
options(["--description", D | T], Realm, P)         -> options(T, Realm, P#{description => list_to_binary(D)});
options(["--default-branch", B | T], Realm, P)      -> options(T, Realm, P#{default_branch => list_to_binary(B)});
options(["--realm", R | T], _Realm, P)              -> options(T, list_to_binary(R), P);
options(_Unknown, _Realm, _P)                       -> {error, usage}.

run(whoami) ->
    identified(identity());
run({init, Realm, Params}) ->
    Transport = transport(),
    initiated(Transport:connect(#{realm_name => Realm}), Transport, Realm, Params);
run({error, _} = Err) ->
    Err.

identified({ok, Id})        -> {ok, [Id, $\n]};
identified({error, _} = E)  -> E.

initiated({ok, Conn}, Transport, Realm, Params) ->
    minted(Transport:initiate(Conn, Params), Realm);
initiated({error, _} = Err, _Transport, _Realm, _Params) ->
    Err.

minted({ok, RepoId}, Realm) -> {ok, [<<"mesh://">>, Realm, $/, RepoId, $\n]};
minted({error, Why}, _Realm) -> {error, {initiate, Why}}.

%% @doc This machine's node id, hex: macula's one stored identity, made on
%% first use exactly as the helper would make it.
identity() ->
    {ok, _} = application:ensure_all_started(crypto),
    _ = application:load(macula),
    {ok, Profile} = macula_crypto_profile:configured(),
    keyed(macula_node_keys:node_identity(Profile)).

keyed({ok, Key})        -> {ok, binary:encode_hex(macula_node_keys:key_id(Key), lowercase)};
keyed({error, _} = E)   -> E.

transport() -> chosen(os:getenv("MCL_GIT_REMOTE_TRANSPORT")).

chosen(false) -> git_remote_macula;
chosen("")    -> git_remote_macula;
chosen(Name)  -> list_to_atom(Name).

finish({ok, Out}) ->
    ok = io:put_chars(standard_io, Out),
    halt(0);
finish({error, Why}) ->
    io:format(standard_error, "git mesh: ~ts~n", [describe(Why, own_id())]),
    halt(1).

own_id() ->
    try identity() of
        {ok, Id} -> Id;
        _        -> <<"(unknown: run git mesh whoami)">>
    catch _:_ -> <<"(unknown: run git mesh whoami)">>
    end.

%% @doc A failure as the user can act on it.
-spec describe(term(), binary()) -> iodata().
describe(usage, _Id) ->
    "usage: git mesh whoami\n"
    "       git mesh init <name> [--public] [--description <text>] "
    "[--default-branch <branch>] [--realm <realm-name>]";
describe({initiate, Why} = Failure, Id) ->
    initiate_failure(string:find(io_lib:format("~p", [Why]), "not_an_initiator"), Failure, Id);
describe({missing_env, Name}, _Id) ->
    io_lib:format("~s is not set (see the mcl-git README, Using it)", [Name]);
describe({bad_env, Name}, _Id) ->
    io_lib:format("~s is not valid hex", [Name]);
describe(Other, _Id) ->
    io_lib:format("~p", [Other]).

initiate_failure(nomatch, {initiate, Why}, _Id) ->
    io_lib:format("initiate_repo failed: ~p", [Why]);
initiate_failure(_Found, _Failure, Id) ->
    io_lib:format("this machine's node ~s may not initiate repositories on that mcl-git. "
                  "Ask its operator to add it to MCL_GIT_INITIATORS.", [Id]).
