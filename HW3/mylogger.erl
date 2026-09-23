-module(mylogger).
-export([start/1, stop/1]).

start(Nodes) ->
    spawn_link(fun() -> init(Nodes) end).

stop(Logger) ->
    Logger ! stop.

init(Nodes) ->
    Clock = time:clock(Nodes),
    Queue = [],
    loop(Clock, Queue, 0, 0).

loop(Clock, Queue, Count, QueueLengthSum) ->
    receive
        {log, From, Time, Msg} ->
            NewClock = time:update(From, Time, Clock),
            NewQueue = insert({log, From, Time, Msg}, Queue),
            FlushedQueue = flush(NewClock, NewQueue),
            loop(NewClock, FlushedQueue, Count+1, QueueLengthSum+length(FlushedQueue));
        stop ->
            io:format("Logger was stopped. Entries remaining from Queue: ~p~nAverage queue length was: ~.2f~n", 
            [length(Queue), QueueLengthSum/Count]),
            ok
    end.

insert(Entry, []) ->
    [Entry];
insert({log, _, T_new, _} = NewEntry, [{log, _, T_curr, _} = Curr | Rest]) ->
    case time:leq(T_new, T_curr) of
        true ->
            [NewEntry, Curr | Rest];
        false ->
            [Curr | insert(NewEntry, Rest)]
    end.

flush(Clock, [{log, From, Time, Msg} = Entry | Rest]) ->
    case time:safe(Time, Clock) of
        true ->
            log(From, Time, Msg),
            flush(Clock, Rest);
        false ->
            [Entry | Rest]
    end;
flush(_Clock, []) ->
    [].

log(From, Time, Msg) ->
    io:format("log: ~w ~w ~p~n", [Time, From, Msg]).