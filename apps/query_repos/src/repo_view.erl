%% @doc A read-model row as a lookup answers it. Text goes out as `{text, Bin}'
%% (a CBOR text string; a bare binary is a byte string, which non-BEAM callers
%% receive as bytes), and a value the row does not have is left out rather than
%% sent as null.
-module(repo_view).

-export([render/1, visible/2]).

-define(TEXT, [repo_id, name, owner, description, default_branch, visibility, status]).

-spec render(map()) -> map().
render(Row) ->
    maps:from_list([{K, wire(K, V)} || {K, V} <- maps:to_list(Row), V =/= undefined]).

wire(tags, Tags)                          -> [{text, T} || T <- Tags];
wire(K, V) when is_binary(V)              -> text(lists:member(K, ?TEXT), V);
wire(_K, V)                               -> V.

text(true, V)  -> {text, V};
text(false, V) -> V.

%% @doc The rows `Caller' may see, rendered.
-spec visible([map()], binary() | undefined) -> [map()].
visible(Rows, Caller) ->
    [render(R) || R <- Rows, repo_access:may_read(R, Caller) =:= ok].
