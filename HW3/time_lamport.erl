-module(time_lamport).
-export([zero/0, inc/2, merge/2, leq/2, clock/1, update/3, safe/2]).

%% Worker Side

zero() ->
    0.

inc(_, T) ->
    T + 1.

merge(Ti, Tj) ->
    erlang:max(Ti, Tj).

leq(Ti, Tj) ->
    Ti =< Tj.

%% Logger Side

clock(Nodes) ->
    [{Node, zero()} || Node <- Nodes].

update(Node, Time, Clock) ->
    lists:keystore(Node, 1, Clock, {Node, Time}).

safe(Time, Clock) ->
    lists:all(fun({_Node, T}) -> leq(Time, T) end, Clock).
