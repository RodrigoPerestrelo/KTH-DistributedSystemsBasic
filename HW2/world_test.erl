-module(world_test).
-export([test/0, setup/2, start_all/1, stop_all/1, connect_routers/2, broadcast_all/1, update_all/1]).

test() ->
    %% 8 Nodes across 4 Continents:
    %% Europe (3): oslo, london, paris
    %% Africa (2): cairo, nairobi
    %% America (2): new_york, sao_paulo
    %% Oceania/Asia (1): sydney
    Routers = [
        {r1, oslo}, 
        {r2, london}, 
        {r3, paris},
        {r4, cairo}, 
        {r5, nairobi},
        {r6, new_york}, 
        {r7, sao_paulo},
        {r8, sydney}
    ],

    %% All links exist from the start:
    %% Intercontinental Topology:
    Cons = [
        %% Europe internal
        {r1, r3}, {r3, r1},   % oslo <-> paris
        {r2, r3}, {r3, r2},   % london <-> paris

        %% Africa internal
        {r4, r5}, {r5, r4},   % cairo <-> nairobi

        %% America internal
        {r6, r7}, {r7, r6},   % new_york <-> sao_paulo

        %% Intercontinental Links:
        {r1, r8}, {r8, r1},   % oslo <-> sydney (Europe <-> Oceania)
        {r3, r4}, {r4, r3},   % paris <-> cairo (Europe <-> Africa)

        %% Transatlantic Primary: New York <-> London (Americas <-> Europe)
        {r6, r2}, {r2, r6},

        %% Transatlantic Backup: Sao Paulo <-> Nairobi (Americas <-> Africa)
        {r7, r5}, {r5, r7}
    ],

    setup(Routers, Cons),

    io:format("Explicit Prompt Check (Sydney -> Oslo)~n"),
    r8 ! {send, oslo, "Prompt test: Direct intercontinental message Sydney to Oslo"},
    timer:sleep(1000),

    io:format("~nMulti-Hop Transcontinental (Sao Paulo -> Sydney via London)~n"),
    r7 ! {send, sydney, "Primary route: Sao Paulo to Sydney via London"},
    timer:sleep(1000),

    io:format("~nKilling London Router (r2)~n"),
    routy:stop(r2),
    timer:sleep(300),

    io:format("~nRe-converging Surviving Nodes (Broadcast & Update)~n"),
    Surviving = lists:keydelete(r2, 1, Routers),
    broadcast_all(Surviving),
    timer:sleep(500),
    update_all(Surviving),
    timer:sleep(300),

    io:format("~nDynamic Failover (Sao Paulo -> Sydney via Cairo)~n"),
    r7 ! {send, sydney, "Failover route: Sao Paulo to Sydney bypassing dead London"},
    timer:sleep(1000),

    stop_all(Surviving),
    ok.

setup(Routers, Cons) ->
    start_all(Routers),
    connect_routers(Cons, Routers),
    broadcast_all(Routers),
    timer:sleep(500),
    update_all(Routers),
    timer:sleep(300).

start_all(Routers) ->
    lists:foreach(fun({R, Name}) -> routy:start(R, Name) end, Routers).

stop_all(Routers) ->
    lists:foreach(fun({R, _}) -> routy:stop(R) end, Routers).

connect_routers(Cons, Routers) ->
    lists:foreach(fun({SenderReg, RecvrReg}) ->
        {_, RecvrName} = lists:keyfind(RecvrReg, 1, Routers),
        SenderReg ! {add, RecvrName, whereis(RecvrReg)}
    end, Cons).

broadcast_all(Routers) ->
    lists:foreach(fun({R, _}) -> R ! broadcast end, Routers).

update_all(Routers) ->
    lists:foreach(fun({R, _}) -> R ! update end, Routers).