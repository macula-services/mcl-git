%% @doc The integration fact mcl-git announces when a push moves refs:
%% `<realm>/mcl-git/git/repos/refs_advanced_v1'. Its shape is a public
%% contract, deliberately separate from the refs_advanced_v1 domain event
%% it is made from.
%%
%% The realm NAME the topic carries is deploy config (MCL_REALM_NAME), checked
%% at start against the realm tag the pool is in: a topic naming one realm,
%% published in another, reaches nobody.
-module(refs_fact).

-export([topic/1, fact/1, publish/1, realm_name/0, check_realm_name/0, check_realm_name/2]).

-import(mcl_om_wire, [field/2]).

-spec topic(binary()) -> binary().
topic(RealmName) ->
    macula_topic:app_fact(RealmName, <<"mcl-git">>, <<"git">>, <<"repos">>,
                          <<"refs_advanced">>, 1).

-spec fact(map()) -> map().
fact(Data) ->
    #{repo_id     => {text, field(repo_id, Data)},
      pusher      => {text, field(pusher, Data)},
      advanced_at => field(advanced_at, Data),
      advances    => [advance(A) || A <- field(advances, Data)]}.

advance(A) ->
    #{ref     => {text, field(ref, A)},
      old_oid => {text, field(old_oid, A)},
      new_oid => {text, field(new_oid, A)}}.

%% @doc Fire and forget. A node whose mesh is not up has nobody to tell.
-spec publish(map()) -> ok.
publish(Data) ->
    published(mcl_om:mesh_handles(), Data).

published({ok, Pool, Realm}, Data) ->
    {ok, _Pid} = macula_publisher:start_link(refs_fact_publisher, Pool, Realm,
                                             topic(realm_name()), fact(Data), []),
    ok;
published({error, Why}, Data) ->
    logger:warning("[mcl_git] refs of ~s advanced but the mesh is unavailable (~p): not announced",
                   [field(repo_id, Data), Why]),
    ok.

-spec realm_name() -> binary().
realm_name() ->
    named(application:get_env(guide_repo_lifecycle, realm_name, undefined)).

named(Name) when is_list(Name), Name =/= "" -> unicode:characters_to_binary(Name);
named(Name) when is_binary(Name), Name =/= <<>> -> Name;
named(_Unset) -> error({mcl_git_realm_name_unset, realm_name}).

%% @doc Refuse to start unless the configured realm name is the pool's realm.
-spec check_realm_name() -> ok.
check_realm_name() ->
    configured(realm_name(), mcl_om:realm()).

configured(Name, {ok, Tag}) -> check_realm_name(Name, Tag);
configured(Name, Other)     -> error({mcl_git_realm_unset, Name, Other}).

-spec check_realm_name(binary(), binary()) -> ok.
check_realm_name(Name, Tag) ->
    matched(crypto:hash(sha256, Name) =:= Tag, Name, Tag).

matched(true, _Name, _Tag) -> ok;
matched(false, Name, Tag)  -> error({mcl_git_realm_name_mismatch, Name, Tag}).
