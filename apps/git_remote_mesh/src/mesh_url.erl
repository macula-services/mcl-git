%% @doc `mesh://<realm-name>/<repo_id>': the realm by NAME (its tag is sha256
%% of the name), and the repo id mcl-git minted at initiate_repo.
-module(mesh_url).

-export([parse/1]).

-spec parse(string() | binary()) ->
    {ok, #{realm_name := binary(), repo_id := binary()}} | {error, {bad_mesh_url, string()}}.
parse(Url) when is_binary(Url) -> parse(binary_to_list(Url));
parse("mesh://" ++ Rest = Url) -> parts(string:split(Rest, "/", all), Url);
parse(Url)                     -> {error, {bad_mesh_url, Url}}.

parts([Realm, RepoId], _Url) when Realm =/= "", RepoId =/= "" ->
    {ok, #{realm_name => list_to_binary(Realm), repo_id => list_to_binary(RepoId)}};
parts(_Other, Url) ->
    {error, {bad_mesh_url, Url}}.
