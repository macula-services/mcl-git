%% @doc The remote-helper protocol (gitremote-helpers(7)) over mcl-git's two
%% procedures. Capabilities `fetch' and `push':
%%
%%   list            ls-refs (protocol v2) through mcl-git/upload_pack
%%   list for-push   the receive-pack advertisement through mcl-git/receive_pack
%%   fetch <oid> <n> a batch, ended by a blank line: one v2 fetch of every
%%                   wanted oid, whose pack `git index-pack' stores in GIT_DIR
%%   push <src>:<dst> a batch: one receive-pack request with every update and
%%                   the pack that carries them, answered ref by ref
%%
%% Reading and writing are funs, and so is the procedure call, so the whole
%% conversation can be driven without git or a mesh.
-module(remote_helper).

-export([run/4]).

-define(ZERO, <<"0000000000000000000000000000000000000000">>).
-define(TIMEOUT_MS, 300000).

-type call() :: fun((binary(), map()) -> {ok, map()} | {error, term()}).

-spec run(fun(() -> binary() | eof), fun((iodata()) -> ok), call(), file:filename()) ->
    ok | {error, term()}.
run(Read, Write, Call, GitDir) ->
    loop(Read(), #{read => Read, write => Write, call => Call, git_dir => GitDir,
                   advertised => #{}}).

loop(eof, _S)    -> ok;
loop(<<>>, S)    -> next(ok, S);
loop(Line, S)    -> next(command(Line, S), S).

next({ok, S1}, _S)       -> loop(read(S1), S1);
next(ok, S)              -> loop(read(S), S);
next({error, _} = E, _S) -> E.

read(#{read := Read}) -> Read().

command(<<"capabilities">>, S) ->
    emit(S, <<"fetch\npush\n\n">>);
command(<<"list for-push">>, S) ->
    list_for_push(receive_pack(#{advertise => 1}, S), S);
command(<<"list">>, S) ->
    listed(upload_pack(git_v2:ls_refs_request(), S), S);
command(<<"fetch ", Want/binary>>, S) ->
    fetch(batch(<<"fetch ">>, [Want], S), S);
command(<<"push ", Spec/binary>>, S) ->
    push(batch(<<"push ">>, [Spec], S), S);
command(Other, _S) ->
    {error, {unknown_command, Other}}.

%% A batch: the first line, then every line with the same prefix up to the
%% blank line that ends it.
batch(Prefix, Acc, S) ->
    more(read(S), Prefix, Acc, S).

more(<<>>, _Prefix, Acc, _S) -> lists:reverse(Acc);
more(eof, _Prefix, Acc, _S)  -> lists:reverse(Acc);
more(Line, Prefix, Acc, S) ->
    Size = byte_size(Prefix),
    <<Prefix:Size/binary, Rest/binary>> = Line,
    batch(Prefix, [Rest | Acc], S).

%%--------------------------------------------------------------------
%% list
%%--------------------------------------------------------------------

listed({ok, Out}, S) ->
    refs_listed(git_v2:parse_ls_refs(Out), S);
listed({error, _} = E, _S) ->
    E.

refs_listed({ok, Refs}, S) ->
    emit(S, [[ref_line(R) || R <- Refs], $\n]);
refs_listed({error, _} = E, _S) ->
    E.

ref_line(#{name := <<"HEAD">>, symref_target := Target}) when is_binary(Target) ->
    [$@, Target, <<" HEAD\n">>];
ref_line(#{name := Name, oid := Oid}) ->
    [Oid, $\s, Name, $\n].

list_for_push({ok, Adv}, S) ->
    advertised(git_push:parse_advertisement(Adv), S);
list_for_push({error, _} = E, _S) ->
    E.

advertised({ok, Refs, _Caps}, S) ->
    emit(S#{advertised => maps:from_list([{N, O} || #{name := N, oid := O} <- Refs])},
         [[[O, $\s, N, $\n] || #{name := N, oid := O} <- Refs], $\n]);
advertised({error, _} = E, _S) ->
    E.

%%--------------------------------------------------------------------
%% fetch
%%--------------------------------------------------------------------

%% The request names what this repository already holds (its refs' tips), so
%% the server sends only what is missing, as a thin pack index-pack completes.
fetch(Wants, #{git_dir := Dir} = S) ->
    Oids = lists:usort([hd(binary:split(W, <<" ">>)) || W <- Wants]),
    fetched(upload_pack(git_v2:fetch_request(Oids, local_tips(Dir)), S), S).

local_tips(Dir) ->
    tips(git(["--git-dir", Dir, "for-each-ref", "--format=%(objectname)"], <<>>)).

tips({ok, Out})     -> lists:usort(binary:split(Out, <<"\n">>, [global, trim_all]));
tips({error, _})    -> [].

fetched({ok, Out}, S) ->
    packed(git_v2:packfile(Out), S);
fetched({error, _} = E, _S) ->
    E.

packed({ok, Pack}, #{git_dir := Dir} = S) ->
    indexed(git(["--git-dir", Dir, "index-pack", "--stdin", "--fix-thin"], Pack), S);
packed({error, _} = E, _S) ->
    E.

indexed({ok, _}, S)        -> emit(S, <<"\n">>);
indexed({error, _} = E, _S) -> E.

%%--------------------------------------------------------------------
%% push
%%--------------------------------------------------------------------

push(Specs, #{advertised := Advertised, git_dir := Dir} = S) ->
    Resolved = [update(Spec, Advertised, Dir) || Spec <- Specs],
    Refused = [[<<"error ">>, Ref, $\s, Why, $\n] || {refused, Ref, Why} <- Resolved],
    Updates = [U || #{} = U <- Resolved],
    pushing(Updates, Refused, Advertised, Dir, S).

%% Refs that did not resolve locally are refused as themselves; the rest go.
pushing([], Refused, _Advertised, _Dir, S) ->
    emit(S, [Refused, $\n]);
pushing(Updates, Refused, Advertised, Dir, S) ->
    pushed(pack_for(Updates, Advertised, Dir), Updates, S#{refused => Refused}).

%% `+src:dst' forces; the server takes any update from the owner, so the
%% plus changes nothing here. An empty src removes dst.
update(<<"+", Spec/binary>>, Advertised, Dir) -> update(Spec, Advertised, Dir);
update(Spec, Advertised, Dir) ->
    [Src, Dst] = binary:split(Spec, <<":">>),
    resolved(resolve(Src, Dir), Dst, maps:get(Dst, Advertised, ?ZERO)).

resolved({ok, New}, Dst, Old)     -> #{ref => Dst, old_oid => Old, new_oid => New};
resolved({error, _}, Dst, _Old)   -> {refused, Dst, <<"src refspec does not resolve">>}.

%% Not peeled: an annotated tag is pushed as its tag object, and
%% pack-objects --revs walks from it to what it points at.
resolve(<<>>, _Dir) -> {ok, ?ZERO};
resolve(Src, Dir) ->
    oid(git(["--git-dir", Dir, "rev-parse", "--verify", "--end-of-options", Src], <<>>)).

oid({ok, Out})      -> {ok, string:trim(Out)};
oid({error, _} = E) -> E.

%% The objects the new tips reach that the remote does not already have:
%% every advertised oid this repository also holds is excluded.
pack_for(Updates, Advertised, Dir) ->
    Tips = [N || #{new_oid := N} <- Updates, N =/= ?ZERO],
    Known = [O || O <- lists:usort(maps:values(Advertised)), present(O, Dir)],
    packed_objects(Tips, Known, Dir).

packed_objects([], _Known, _Dir) ->
    {ok, <<>>};
packed_objects(Tips, Known, Dir) ->
    git(["--git-dir", Dir, "pack-objects", "--stdout", "--revs", "--quiet"],
        [[[T, $\n] || T <- Tips], [[$^, K, $\n] || K <- Known]]).

present(Oid, Dir) ->
    {ok, 0} =:= exit_status(git_exec:run(git_executable(), ["--git-dir", Dir, "cat-file", "-e", Oid],
                                         <<>>, [], ?TIMEOUT_MS)).

exit_status({ok, #{exit_status := S}}) -> {ok, S};
exit_status(Other)                     -> Other.

pushed({ok, Pack}, Updates, S) ->
    reported(receive_pack(#{stdin => git_push:request(Updates, Pack)}, S), Updates, S);
pushed({error, _} = E, _Updates, _S) ->
    E.

reported({ok, Out}, Updates, S) ->
    verdicts(git_push:parse_report(Out), Updates, S);
reported({error, Why}, Updates, S) ->
    emit(S, [maps:get(refused, S, []),
             [[<<"error ">>, R, $\s, reason(Why), $\n] || #{ref := R} <- Updates], $\n]).

verdicts({ok, Verdicts}, _Updates, S) ->
    emit(S, [maps:get(refused, S, []), [verdict(V) || V <- Verdicts], $\n]);
verdicts({error, Why}, Updates, S) ->
    reported({error, Why}, Updates, S).

verdict({Ref, ok})          -> [<<"ok ">>, Ref, $\n];
verdict({Ref, {error, Why}}) -> [<<"error ">>, Ref, $\s, Why, $\n].

reason(Why) -> iolist_to_binary(io_lib:format("~p", [Why])).

%%--------------------------------------------------------------------
%% procedures, git, output
%%--------------------------------------------------------------------

upload_pack(Stdin, #{call := Call}) ->
    stdout(Call(<<"mcl-git/upload_pack">>, #{stdin => Stdin})).

receive_pack(Payload, #{call := Call}) ->
    stdout(Call(<<"mcl-git/receive_pack">>, Payload)).

stdout({ok, #{stdout := Out}})       -> {ok, Out};
stdout({ok, #{<<"stdout">> := Out}}) -> {ok, Out};
stdout({ok, Other})                  -> {error, {unexpected_reply, Other}};
stdout({error, _} = E)               -> E.

git(Args, Stdin) ->
    ran(git_exec:run(git_executable(), Args, Stdin, [], ?TIMEOUT_MS)).

ran({ok, #{exit_status := 0, stdout := Out}}) -> {ok, Out};
ran({ok, #{exit_status := N, stderr := Err}}) -> {error, {git, N, Err}};
ran({error, _} = E)                            -> E.

git_executable() -> os:find_executable("git").

emit(#{write := Write} = S, IoData) ->
    ok = Write(IoData),
    {ok, S}.
