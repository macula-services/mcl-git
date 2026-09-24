%% @doc The mcl_om service contract for mcl-git.
%%
%% Git over the mesh. Nine org-namespaced procedures under `mcl-git': four
%% that change a repository's dossier, three lookups, and the two git ones,
%% upload_pack (clone, fetch) and receive_pack (push). A push is announced on
%% `<realm>/mcl-git/git/repos/refs_advanced_v1'.
%%
%% Every procedure is `open' at the transport. Who may do what is decided by
%% each desk on the wire-authenticated caller macula hands it: initiate needs
%% an initiator, a change or a push needs the owner, and a private repository
%% is invisible to everyone else.
-module(mcl_git_service).

-behaviour(mcl_om_service).

-export([info/0, start/1, stop/1, health/0, capabilities/0, identity_spec/0]).
%% ⚠ These two turn the store on: mcl_om:boot/1 opens it before start/1. The
%% store id is named here AND in the `evoq' block of config/sys.config.src,
%% and mcl_git_service_tests checks that the two agree.
-export([store_id/0, data_dir/0]).
-export([git_handler_timeout_ms/0]).

%% How many git processes run at once on this node (see git_slots).
-define(GIT_SLOTS, 8).
-define(GIT_HANDLER_TIMEOUT_MS, 300000).

info() ->
    #{name => <<"mcl-git">>,
      version => <<"0.1.0">>,
      description => <<"Git over the mesh: bare repositories cloned, fetched and pushed through org-namespaced procedures">>}.

%% The realm name the push announcements carry must be the pool's realm, or
%% they go where nobody listens.
start(_Opts) ->
    ok = refs_fact:check_realm_name(),
    ok = git_slots:init(?GIT_SLOTS),
    mcl_git_sup:start_link().

stop(_State) -> ok.

%% Whether callers can REACH the procedures (their realm-issued provider
%% grants) is reported by mcl_om's own /health, combined with this verdict.
health() -> ok.

capabilities() ->
    [procedure(<<"initiate_repo">>, initiate_repo_responder),
     procedure(<<"rename_repo">>, rename_repo_responder),
     procedure(<<"set_repo_description">>, set_repo_description_responder),
     procedure(<<"archive_repo">>, archive_repo_responder),
     procedure(<<"get_repo_by_id">>, get_repo_by_id_responder),
     procedure(<<"list_repos_by_owner">>, list_repos_by_owner_responder),
     procedure(<<"search_repos_by_tag">>, search_repos_by_tag_responder),
     git_procedure(<<"upload_pack">>, upload_pack_responder),
     git_procedure(<<"receive_pack">>, receive_pack_responder)].

procedure(Name, Handler) ->
    #{name => Name, version => 1, handler => {Handler, []}, auth => open}.

%% A git procedure runs git, so it waits longer than macula's 30 s default
%% before the mesh gives up on it (see git_handler_timeout_ms/0).
git_procedure(Name, Handler) ->
    (procedure(Name, Handler))#{handler_timeout_ms => ?GIT_HANDLER_TIMEOUT_MS}.

%% @doc How long macula waits for upload_pack and receive_pack before
%% answering the caller `temporary_relay_failure'. The three deadlines are
%% ordered so each layer gives up after the one below it: git (bare_repo,
%% 270 s), then this handler (300 s), then the caller (git_remote_macula,
%% 330 s). A caller therefore always hears git's real outcome.
-spec git_handler_timeout_ms() -> pos_integer().
git_handler_timeout_ms() -> ?GIT_HANDLER_TIMEOUT_MS.

%% The authority is the realm's per-procedure provider grant, not a UCAN this
%% service asks for, so it asks for nothing beyond its scope.
identity_spec() ->
    #{scope => <<"mcl-git">>, actions => [], resources => [], ttl_days => 30}.

-spec store_id() -> atom().
store_id() -> mcl_git_store.

%% @doc Where the store lives; the repositories live under `repos/' beside it
%% (config/sys.config.src). ⚠ On a fleet node this must be a mounted volume on
%% a bulk drive: without one, every container recreate loses every repository.
-spec data_dir() -> string().
data_dir() -> chosen(os:getenv("MCL_DATA_DIR")).

chosen(false) -> "/tmp/mcl_git";
chosen("")    -> "/tmp/mcl_git";
chosen(Path)  -> Path.
