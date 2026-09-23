%% @doc Who may read or change a repository, decided on its read-model row.
%%
%% Reading: anyone for a public repo, only its owner for a private one. A
%% stranger asking after a private repo is told `not_found', exactly what a
%% missing repo answers, so the answer leaks nothing about what exists.
%%
%% Changing (a push): only the owner, and never an archived repo. The
%% aggregate enforces the same rule on every command; this is the check a
%% push needs BEFORE git moves any ref on disk, which no event can undo.
-module(repo_access).

-export([may_read/2, may_write/2]).

-spec may_read(map(), binary() | undefined) -> ok | {error, not_found}.
may_read(#{visibility := <<"public">>}, _Caller) -> ok;
may_read(#{owner := Owner}, Owner)              -> ok;
may_read(_Row, _Caller)                         -> {error, not_found}.

-spec may_write(map(), binary() | undefined) -> ok | {error, not_found | not_owner | archived}.
may_write(Row, Caller) ->
    written(may_read(Row, Caller), Row, Caller).

written({error, _} = Hidden, _Row, _Caller)             -> Hidden;
written(ok, #{owner := Owner}, Caller) when Owner =/= Caller -> {error, not_owner};
written(ok, #{status := <<"archived">>}, _Caller)       -> {error, archived};
written(ok, _Row, _Caller)                              -> ok.
