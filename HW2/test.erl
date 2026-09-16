-module(test).
-export([test/0, setup/2, start_all/1, stop_all/1, connect_routers/2, broadcast_all/1, update_all/1]).

test() ->
    Routers = [{r1, stockholm}, {r2, malmo}, {r3, lund}, {r4, gothenburg}],
    Cons = [
    {r1, r3}, {r3, r1},   % stockholm <-> lund
    {r1, r2}, {r2, r3},   % stockholm -> malmo, malmo -> lund
    {r3, r4}, {r4, r3}    % lund <-> gothenburg
    ],
    setup(Routers, Cons),
    io:format("setup for test finished~nmap:~n
        stockholm <-> lund~n
        stockholm -> malmo, malmo -> lund~n
        lund <-> gothenburg~n~n"),
    io:format("sending testmessage stockholm -> gothenburg~n"),
    r1 ! {send, gothenburg, "test message to gothenburg, hello from stockholm"},
    timer:sleep(1000),
    io:format("~nsending testmessage malmö -> stockholm~n"),
    r2 ! {send, stockholm, "test message to stockholm, hello from malmö"},
    timer:sleep(1000),
    stop_all(Routers).

setup(Routers, Cons) ->
    start_all(Routers),
    connect_routers(Cons, Routers),
    broadcast_all(Routers),
    timer:sleep(100),  % give flooding a moment to settle
    update_all(Routers).

start_all(Routers) ->
    lists:foreach(fun({R, Name}) -> routy:start(R, Name) end, Routers).

stop_all(Routers) ->
    lists:foreach(fun({R, _}) -> routy:stop(R) end, Routers).

connect_routers(Cons, Routers) ->
    lists:foreach(fun({SenderPid, RecvrPid}) ->
        {_, RecvrName} = lists:keyfind(RecvrPid, 1, Routers),
        SenderPid ! {add, RecvrName, RecvrPid}
    end,
    Cons).

broadcast_all(Routers) ->
    lists:foreach(fun({R, _}) -> R ! broadcast end, Routers).

update_all(Routers) ->
    lists:foreach(fun({R, _}) -> R ! update end, Routers).