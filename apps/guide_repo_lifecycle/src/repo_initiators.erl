%% @doc The node ids allowed to initiate repositories on this node, as
%% lowercase hex. Configured as a list, or as the comma-separated string
%% `config/sys.config.src' substitutes from MCL_GIT_INITIATORS. Unset or
%% empty admits nobody.
-module(repo_initiators).

-export([list/0]).

-spec list() -> [binary()].
list() -> parsed(application:get_env(guide_repo_lifecycle, initiators, [])).

parsed(Text) when is_binary(Text) -> parsed(binary_to_list(Text));
parsed([C | _] = Text) when is_integer(C) ->
    [normal(T) || T <- string:lexemes(Text, ", "), T =/= []];
parsed(List) when is_list(List) -> [normal(T) || T <- List].

normal(Id) -> string:lowercase(unicode:characters_to_binary(Id)).
