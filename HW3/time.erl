-module(time).
-export([zero/0, inc/2, merge/2, leq/2, clock/1, update/3, safe/2]).

-define(BACKEND, time_lamport).
% -define(BACKEND, time_vector).

zero() ->
    ?BACKEND:zero().

inc(Name, T) ->
    ?BACKEND:inc(Name, T).

merge(Ti, Tj) ->
    ?BACKEND:merge(Ti, Tj).

leq(Ti, Tj) ->
    ?BACKEND:leq(Ti, Tj).

clock(Nodes) ->
    ?BACKEND:clock(Nodes).

update(Node, Time, Clock) ->
    ?BACKEND:update(Node, Time, Clock).

safe(Time, Clock) ->
    ?BACKEND:safe(Time, Clock).