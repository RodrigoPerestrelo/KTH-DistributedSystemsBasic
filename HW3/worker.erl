-module(worker).
-export([start/5, stop/1, peers/2]).

start(Name, Logger, Seed, Sleep, Jitter) ->
    spawn_link( fun() -> init(Name, Logger, Seed, Sleep, Jitter) end).

stop(Worker) ->
    Worker ! stop.

init(Name, Log, Seed, Sleep, Jitter) ->
    rand:seed(default, Seed),
    receive
        {peers, Peers} ->
            Time = time:zero(),
            loop(Name, Log, Peers, Sleep, Jitter, Time);
        stop ->
            ok
    end.

peers(Wrk, Peers) ->
    Wrk ! {peers, Peers}.

loop(Name, Log, Peers, Sleep, Jitter, Time) ->
    Wait = rand:uniform(Sleep),
    receive
        {msg, TimeMsg, Msg} ->
            ActualTime = time:inc(Name, time:merge(Time, TimeMsg)),
            Log ! {log, Name, ActualTime, {received, Msg}},
            loop(Name, Log, Peers, Sleep, Jitter, ActualTime);
        stop ->
            ok;
        Error ->
            Log ! {log, Name, time, {error, Error}}
    after Wait ->
        Selected = select(Peers),
        ActualTime = time:inc(Name, Time),
        Message = {hello, rand:uniform(100)},
        Selected ! {msg, ActualTime, Message},
        jitter(Jitter),
        Log ! {log, Name, Time, {sending, Message}},
        loop(Name, Log, Peers, Sleep, Jitter, ActualTime)
    end.

select(Peers) ->
    lists:nth(rand:uniform(length(Peers)), Peers).

jitter(0) -> ok;
jitter(Jitter) -> timer:sleep(rand:uniform(Jitter)).