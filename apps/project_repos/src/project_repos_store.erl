%% @doc The repos read model: one ETS row per repository. The projection
%% writes through this process; readers go to ETS directly.
%%
%% It is rebuilt from the event store on every boot (evoq replays the store
%% to every projection), so it holds nothing the store does not.
-module(project_repos_store).

-behaviour(gen_server).

-export([start_link/0, get/1, put/2, revise/2, list_by_owner/1, list_by_tag/1]).
-export([init/1, handle_call/3, handle_cast/2]).

-define(TABLE, mcl_git_repos).

-spec start_link() -> {ok, pid()} | {error, term()}.
start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

-spec get(binary()) -> {ok, map()} | {error, not_found}.
get(RepoId) ->
    found(ets:lookup(?TABLE, RepoId)).

found([{_Id, Row}]) -> {ok, Row};
found([])           -> {error, not_found}.

-spec put(binary(), map()) -> ok.
put(RepoId, Row) -> gen_server:call(?MODULE, {put, RepoId, Row}).

%% @doc Merge `Changes' into an existing row; a row that does not exist
%% stays absent (an event for a repo this model never saw initiated).
-spec revise(binary(), map()) -> ok.
revise(RepoId, Changes) -> gen_server:call(?MODULE, {revise, RepoId, Changes}).

-spec list_by_owner(binary()) -> [map()].
list_by_owner(Owner) ->
    [Row || {_Id, #{owner := O} = Row} <- ets:tab2list(?TABLE), O =:= Owner].

-spec list_by_tag(binary()) -> [map()].
list_by_tag(Tag) ->
    [Row || {_Id, #{tags := Tags} = Row} <- ets:tab2list(?TABLE), lists:member(Tag, Tags)].

init([]) ->
    ?TABLE = ets:new(?TABLE, [set, protected, named_table, {read_concurrency, true}]),
    {ok, #{}}.

handle_call({put, RepoId, Row}, _From, State) ->
    true = ets:insert(?TABLE, {RepoId, Row}),
    {reply, ok, State};
handle_call({revise, RepoId, Changes}, _From, State) ->
    revised(ets:lookup(?TABLE, RepoId), Changes),
    {reply, ok, State}.

handle_cast(_Msg, State) -> {noreply, State}.

revised([{RepoId, Row}], Changes) -> true = ets:insert(?TABLE, {RepoId, maps:merge(Row, Changes)});
revised([], _Changes)             -> ok.
