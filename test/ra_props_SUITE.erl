-module(ra_props_SUITE).
-compile(export_all).

-include("ra.hrl").
-include_lib("proper/include/proper.hrl").
-include_lib("common_test/include/ct.hrl").
-include_lib("eunit/include/eunit.hrl").

% just here to silence unused warning
-export_type([op/0]).

all() ->
    [
     non_assoc
    ].

groups() ->
    [ {tests, [], all()} ].

-type op() :: {add, 1..100} | {subtract, 1..100} | {divide, 2..10} | {mult, 1..10}.


%% this test mixes associative with non-associative operations to tests that
%% all nodes apply operations in the same order
%% TODO: mix in a restart_server type of operation
non_assoc_prop({Ops, Initial}) ->
    ct:pal("non_assoc_prop Ops: ~p Initial: ~p~n", [Ops, Initial]),
    [A, B, C] = Cluster = ra:start_local_cluster(3, "test",
                                                 fun non_assoc_apply/2,
                                                 Initial),
    Expected = lists:foldl(fun non_assoc_apply/2, Initial, Ops),
    % identity operation to ensure cluster is ready
    {ok, _, Leader} = ra:send_and_await_consensus(A, {add, 0}),
    [ra:send_and_await_consensus(Leader, Op) || Op <- Ops],
    % TODO: replace with consistent query when ready
    {ok, _, Leader} = ra:send_and_await_consensus(A, {add, 0}),
    timer:sleep(100),
    {ok, _, ARes} = ra:dirty_query(A, fun id/1),
    {ok, _, BRes} = ra:dirty_query(B, fun id/1),
    {ok, _, CRes} = ra:dirty_query(C, fun id/1),
    terminate_cluster(Cluster),
    % assert all nodes have the same final state
    Expected == ARes andalso Expected == BRes andalso Expected == CRes.

non_assoc(_Config) ->
    run_proper(
      fun () ->
              ?FORALL(N, {list(op()), integer(1, 1000)}, non_assoc_prop(N))
      end, [], 25).

id(X) -> X.

non_assoc_apply({add, N}, State) -> State + N;
non_assoc_apply({subtract, N}, State) -> State - N;
non_assoc_apply({divide, N}, State) -> State / N;
non_assoc_apply({mult, N}, State) -> State * N.

terminate_cluster(Nodes) ->
    [gen_statem:stop(P, normal, 2000) || {P, _} <- Nodes].

run_proper(Fun, Args, NumTests) ->
    ?assertEqual(
       true,
       proper:counterexample(erlang:apply(Fun, Args),
			     [{numtests, NumTests},
			      {on_output, fun(".", _) -> ok; % don't print the '.'s on new lines
					     (F, A) -> ct:pal(?LOW_IMPORTANCE, F, A) end}])).
