%% @doc How many git processes this node runs at once. Every clone, fetch
%% and push is a git process, and `upload_pack' is open to anyone who can
%% read a public repository, so without a bound a stranger decides how many
%% run. Past the bound a call is refused as `busy' instead of queueing.
%%
%% One atomics counter, set up once by mcl_git_service:start/1.
-module(git_slots).

-export([init/1, acquire/0, release/0]).

-define(KEY, {?MODULE, slots}).

-spec init(pos_integer()) -> ok.
init(Max) when is_integer(Max), Max > 0 ->
    persistent_term:put(?KEY, {counters:new(1, [atomics]), Max}).

-spec acquire() -> ok | {error, busy}.
acquire() ->
    {Ref, Max} = persistent_term:get(?KEY),
    ok = counters:add(Ref, 1, 1),
    taken(counters:get(Ref, 1) =< Max, Ref).

taken(true, _Ref) -> ok;
taken(false, Ref) -> ok = counters:sub(Ref, 1, 1), {error, busy}.

-spec release() -> ok.
release() ->
    {Ref, _Max} = persistent_term:get(?KEY),
    counters:sub(Ref, 1, 1).
