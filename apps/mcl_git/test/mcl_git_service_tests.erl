%% @doc The service contract, and the files around it, asserted locally.
%%
%% mcl_om resolves the service's callbacks BY NAME at startup, on a live
%% node, so what the compiler cannot see is asserted here: the shapes mcl_om
%% destructures, the procedure names callers dial, and the places where the
%% Erlang side and the config, image and CI sides must agree and nothing else
%% makes them.
-module(mcl_git_service_tests).

-include_lib("eunit/include/eunit.hrl").

-define(SERVICE, mcl_git_service).

exports_every_required_callback_test() ->
    _ = code:ensure_loaded(?SERVICE),
    Required = [{info, 0}, {start, 1}, {stop, 1}, {health, 0}, {capabilities, 0},
                {identity_spec, 0}, {store_id, 0}, {data_dir, 0}],
    ?assertEqual([], [F || {N, A} = F <- Required, not erlang:function_exported(?SERVICE, N, A)]).

info_names_the_service_and_its_version_test() ->
    _ = application:load(mcl_git),
    {ok, Vsn} = application:get_key(mcl_git, vsn),
    ?assertMatch(#{name := <<"mcl-git">>, description := <<_/binary>>}, ?SERVICE:info()),
    ?assertEqual(list_to_binary(Vsn), maps:get(version, ?SERVICE:info())).

%%==============================================================================
%% The procedures: the published contract
%%==============================================================================

the_procedures_are_the_published_contract_test() ->
    ?assertEqual(#{<<"initiate_repo">>        => {initiate_repo_responder, []},
                   <<"rename_repo">>          => {rename_repo_responder, []},
                   <<"set_repo_description">> => {set_repo_description_responder, []},
                   <<"archive_repo">>         => {archive_repo_responder, []},
                   <<"get_repo_by_id">>       => {get_repo_by_id_responder, []},
                   <<"list_repos_by_owner">>  => {list_repos_by_owner_responder, []},
                   <<"search_repos_by_tag">>  => {search_repos_by_tag_responder, []},
                   <<"upload_pack">>          => {upload_pack_responder, []},
                   <<"receive_pack">>         => {receive_pack_responder, []}},
                 maps:from_list([{N, H} || #{name := N, handler := H} <- ?SERVICE:capabilities()])).

%% Every handler is a request/reply macula_response; access is decided by
%% each desk on the wire-authenticated caller, so the transport gate is open.
every_procedure_is_request_reply_and_open_test() ->
    [begin
         ?assertEqual(response, maps:get(kind, C, response)),
         ?assertEqual(open, maps:get(auth, C)),
         {module, M} = code:ensure_loaded(element(1, maps:get(handler, C))),
         ?assert(lists:member(macula_response, behaviours(M)))
     end || C <- ?SERVICE:capabilities()].

%% The git procedures run git, which takes longer than a lookup: macula 12.2
%% (mcl_om 0.28) lets each one wait longer than the default 30 s. The three
%% deadlines are ordered so each layer gives up after the one below it:
%% git, then the handler, then the caller.
the_git_procedures_wait_for_git_test() ->
    Timeouts = maps:from_list([{N, maps:get(handler_timeout_ms, C, default)}
                               || #{name := N} = C <- ?SERVICE:capabilities()]),
    Git = mcl_git_service:git_handler_timeout_ms(),
    ?assertEqual(Git, maps:get(<<"upload_pack">>, Timeouts)),
    ?assertEqual(Git, maps:get(<<"receive_pack">>, Timeouts)),
    ?assertEqual([default], lists:usort([T || {N, T} <- maps:to_list(Timeouts),
                                              N =/= <<"upload_pack">>, N =/= <<"receive_pack">>])),
    ?assert(Git > 30000),
    ?assert(Git =< 600000),
    ?assert(bare_repo:timeout_ms() < Git),
    ?assert(git_remote_macula:call_timeout_ms() > Git).

the_mcl_om_that_carries_handler_timeouts_is_required_test() ->
    Config = read("rebar.config"),
    ?assertNotEqual(nomatch, binary:match(Config, <<"{mcl_om, \"~> 0.28\"}">>)),
    %% 12.2.1: a handler's own refusal reaches the caller as handler_error
    %% with its reason (macula#28); 12.2.0 sent it as unknown_error.
    ?assertNotEqual(nomatch, binary:match(Config, <<"{macula, \">= 12.2.1 and < 13.0.0\"}">>)),
    _ = application:load(macula),
    {ok, Vsn} = application:get_key(macula, vsn),
    ?assert(lists:map(fun list_to_integer/1, string:lexemes(Vsn, ".")) >= [12, 2, 1]).

behaviours(M) ->
    lists:append([B || {behaviour, B} <- M:module_info(attributes)]).

the_shipped_config_names_the_org_test() ->
    ?assertNotEqual(nomatch, binary:match(read("config/sys.config.src"),
                                          <<"{org,               <<\"mcl-git\">>}">>)).

%%==============================================================================
%% The store
%%==============================================================================

the_evoq_block_is_configured_test() ->
    Text = read("config/sys.config.src"),
    [?assertNotEqual(nomatch, binary:match(Text, Needed), Needed)
     || Needed <- [<<"{evoq,">>, <<"event_store_adapter">>, <<"subscription_adapter">>,
                   <<"reckon_evoq_adapter">>]].

the_store_id_agrees_between_erlang_and_config_test() ->
    Declared = atom_to_binary(?SERVICE:store_id(), utf8),
    ?assertNotEqual(nomatch, binary:match(read("config/sys.config.src"),
                                          <<"{store_id,               ", Declared/binary, "}">>)).

data_dir_follows_the_environment_test() ->
    os:putenv("MCL_DATA_DIR", "/data"),
    try ?assertEqual("/data", ?SERVICE:data_dir())
    after os:unsetenv("MCL_DATA_DIR")
    end.

start_refuses_without_a_realm_name_test() ->
    ok = application:unset_env(guide_repo_lifecycle, realm_name),
    ?assertError({mcl_git_realm_name_unset, realm_name}, ?SERVICE:start(#{})).

%%==============================================================================
%% git itself, which every procedure runs
%%==============================================================================

%% The service shells out to git for every clone, fetch and push. An image
%% without it answers `git_failed' to everything while its /health is green;
%% a sibling port once lost ffmpeg exactly this way.
the_runtime_image_installs_git_test() ->
    [_Builder, Runtime] = binary:split(read("Containerfile"), <<"FROM docker.io/alpine">>),
    ?assertMatch({match, _}, re:run(Runtime, <<"apk add[^\\n]*\\bgit\\b">>)).

%% git looks for `git-remote-<scheme>' on PATH, so the image puts the
%% release's bin/, where the launcher is, there.
the_image_puts_the_remote_helper_on_path_test() ->
    ?assertNotEqual(nomatch, binary:match(read("Containerfile"), <<"ENV PATH=\"/app/bin:">>)),
    ?assert(filelib:is_regular(alongside("rel/overlay/bin/git-remote-mesh"))),
    %% relx copies the launcher from rel/, so the image build must have it.
    ?assertMatch({match, _}, re:run(read("Containerfile"), <<"COPY rel \\./rel\\n[^F]*RUN rebar3 as prod release">>)),
    ?assertNotEqual(nomatch, binary:match(read("rebar.config"), <<"\"bin/git-remote-mesh\"">>)),
    %% and `git mesh' (whoami, init) beside it.
    ?assert(filelib:is_regular(alongside("rel/overlay/bin/git-mesh"))),
    ?assertNotEqual(nomatch, binary:match(read("rebar.config"), <<"\"bin/git-mesh\"">>)).

%% mcl_om 0.27 dropped barrel_docdb and with it rocksdb, whose C++ build
%% every image, CI run and local test paid for. Nothing here may bring it back.
no_rocksdb_anywhere_test() ->
    ?assertEqual(non_existing, code:which(rocksdb)),
    ?assertEqual(non_existing, code:which(barrel_docdb)),
    [?assertEqual(nomatch, re:run(read(F), <<"(?i)rocksdb|snappy|lz4|zstd">>, [{capture, none}]), F)
     || F <- ["Containerfile", ".github/workflows/lint.yml"]].

%% The boot claim is labelled, so the realm's operator can tell which box asks.
the_claim_is_labelled_test() ->
    ?assertNotEqual(nomatch, binary:match(read("Containerfile"), <<"ENV MCL_SERVICE_NAME=mcl-git">>)),
    ?assertNotEqual(nomatch, binary:match(read("deploy/docker-compose.yml"), <<"MCL_BOX=${MCL_BOX:?">>)).

%%==============================================================================
%% One OTP, pinned in every place that picks one
%%==============================================================================

%% The builder image, the CI image and the developer's .tool-versions each
%% pick an OTP, and the VM running this suite is a fourth. A green suite on
%% one release says nothing about another, so all four must be 28.4.3.
the_runtime_is_28_4_3_everywhere_test() ->
    ?assertMatch({match, _}, re:run(read("Containerfile"),
                                    <<"FROM docker.io/hexpm/erlang:28\\.4\\.3-[^@\\s]+@sha256:[0-9a-f]{64} AS builder">>)),
    ?assertMatch({match, _}, re:run(read(".github/workflows/lint.yml"),
                                    <<"image: ghcr.io/macula-io/macula-ci-otp:[0-9-]+@sha256:[0-9a-f]{64}">>)),
    ?assertMatch({match, _}, re:run(read(".tool-versions"), <<"^erlang 28\\.4\\.3$">>, [multiline])),
    ?assertEqual(<<"28.4.3">>, running_otp()).

running_otp() ->
    {ok, V} = file:read_file(filename:join([code:root_dir(), "releases",
                                            erlang:system_info(otp_release), "OTP_VERSION"])),
    string:trim(V).

read(Relative) ->
    {ok, Text} = file:read_file(alongside(Relative)),
    Text.

%% Relative to the beam, because eunit runs from wherever the caller stands.
alongside(Name) -> climb(filename:dirname(code:which(?MODULE)), Name, 8).

climb(_Dir, Name, 0) -> Name;
climb(Dir, Name, Left) ->
    Candidate = filename:join(Dir, Name),
    found(filelib:is_regular(Candidate), Candidate, Dir, Name, Left).

found(true, Candidate, _Dir, _Name, _Left) -> Candidate;
found(false, _Candidate, Dir, Name, Left) -> climb(filename:dirname(Dir), Name, Left - 1).
