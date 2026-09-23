%% @doc The three lookups, against the real read-model store. A private
%% repository is visible to its owner only; to anyone else it does not exist.
-module(query_repos_tests).

-include_lib("eunit/include/eunit.hrl").

-define(OWNER_KEY, <<16#aa, 0:248>>).
-define(OWNER, <<"aa00000000000000000000000000000000000000000000000000000000000000">>).
-define(OTHER_KEY, <<16#bb, 0:248>>).
-define(PUB, <<"repo-0190aaaabbbbccccddddeeeeffff0001">>).
-define(PRIV, <<"repo-0190aaaabbbbccccddddeeeeffff0002">>).

query_test_() ->
    {foreach,
     fun() ->
         {ok, Pid} = project_repos_store:start_link(), unlink(Pid),
         ok = project_repos_store:put(?PUB, row(?PUB, <<"public">>)),
         ok = project_repos_store:put(?PRIV, row(?PRIV, <<"private">>)),
         Pid
     end,
     fun(Pid) -> exit(Pid, kill), timer:sleep(10) end,
     [fun by_id_public/0, fun by_id_private/0, fun by_owner/0, fun by_tag/0, fun bad_requests/0]}.

row(Id, Vis) ->
    #{repo_id => Id, name => <<"n">>, owner => ?OWNER, description => <<"d">>,
      default_branch => <<"main">>, visibility => Vis, tags => [<<"cfg">>],
      status => <<"active">>, initiated_at => 1, last_pushed_at => undefined}.

call(Mod, Payload, Caller) ->
    {ok, S} = Mod:init([]),
    case Mod:handle_request(Payload#{caller => Caller}, S) of
        {reply, R, _} -> {reply, R};
        {error, E, _} -> {error, E}
    end.

by_id_public() ->
    {reply, Repo} = call(get_repo_by_id_responder, #{repo_id => ?PUB}, ?OTHER_KEY),
    ?assertMatch(#{repo_id := {text, ?PUB}, name := {text, <<"n">>}, owner := {text, ?OWNER},
                   visibility := {text, <<"public">>}, tags := [{text, <<"cfg">>}],
                   status := {text, <<"active">>}, initiated_at := 1}, Repo),
    %% No booleans or undefined on the wire: an absent value is left out.
    ?assertNot(maps:is_key(last_pushed_at, Repo)).

by_id_private() ->
    ?assertEqual({error, not_found}, call(get_repo_by_id_responder, #{repo_id => ?PRIV}, ?OTHER_KEY)),
    ?assertMatch({reply, #{repo_id := {text, ?PRIV}}},
                 call(get_repo_by_id_responder, #{repo_id => ?PRIV}, ?OWNER_KEY)).

by_owner() ->
    {reply, #{repos := Others}} = call(list_repos_by_owner_responder, #{owner => ?OWNER}, ?OTHER_KEY),
    ?assertEqual([{text, ?PUB}], ids(Others)),
    {reply, #{repos := Own}} = call(list_repos_by_owner_responder, #{owner => ?OWNER}, ?OWNER_KEY),
    ?assertEqual([{text, ?PUB}, {text, ?PRIV}], ids(Own)).

by_tag() ->
    {reply, #{repos := Others}} = call(search_repos_by_tag_responder, #{tag => <<"cfg">>}, ?OTHER_KEY),
    ?assertEqual([{text, ?PUB}], ids(Others)),
    {reply, #{repos := None}} = call(search_repos_by_tag_responder, #{tag => <<"x">>}, ?OTHER_KEY),
    ?assertEqual([], None).

bad_requests() ->
    ?assertEqual({error, bad_request}, call(get_repo_by_id_responder, #{}, ?OTHER_KEY)),
    ?assertEqual({error, bad_request}, call(list_repos_by_owner_responder, #{}, ?OTHER_KEY)),
    ?assertEqual({error, bad_request}, call(search_repos_by_tag_responder, #{}, ?OTHER_KEY)).

ids(Repos) -> lists:sort([maps:get(repo_id, R) || R <- Repos]).
