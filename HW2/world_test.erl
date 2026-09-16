-module(world_test).
-export([setup_world/0, route_message/3, list_routers/0, teardown_world/0, kill_router/1, get_network_status/0]).

routers() ->
    [
        {r1, stockholm}, {r2, goteborg}, {r3, malmo},
        {r4, hamburg}, {r5, berlin}, {r6, frankfurt},
        {r7, paris}, {r8, toulouse},
        {r9, madrid}, {r10, barcelona},
        {r11, porto}, {r12, lisbon}, {r13, coimbra},
        {r14, milano}
    ].

cons() ->
    [
        {r1, r2}, {r2, r1}, % stockhol <> goteborg
        {r2, r3}, {r3, r2}, % goteborg <> malmo
        {r1, r3}, {r3, r1}, % stockholm <> malmo
        {r3, r4}, {r4, r3}, % malmo <> hamburg
        {r4, r5}, {r5, r4}, % hamburg <> berlin
        {r4, r6}, {r6, r4}, % hamburg <> frankfurt
        {r5, r6}, {r6, r5}, % berlin <> frankfurt
        {r6, r7}, {r7, r6}, % frankfurt <> paris
        {r6, r14}, {r14, r6}, % frankfurt <> milano
        {r5, r14}, {r14, r5}, % berlin <> milano
        {r7, r8}, {r8, r7}, % paris <> toulouse
        {r7, r10}, {r10, r7}, % paris <> barcelona
        {r8, r10}, {r10, r8}, % toulouse <> barcelona
        {r8, r9}, {r9, r8}, % toulouse <> madrid
        {r10, r9}, {r9, r10}, % barcelona <> madrid
        {r9, r11}, {r11, r9}, % madrid <> porto
        {r9, r12}, {r12, r9}, % madrid <> lisbon
        {r11, r12}, {r12, r11}, % porto <> lisbon
        {r11, r13}, {r13, r11}, % porto <> coimbra
        {r13, r12}, {r12, r13} % coimbra <> lisbon
    ].

setup_world() ->
    Routers = routers(),
    Cons = cons(),
    test:setup(Routers, Cons),
    ok.

teardown_world() ->
    Routers = routers(),
    test:stop_all(Routers).

kill_router(Name) ->
    {Pid, _} = lists:keyfind(Name, 2, routers()),
    Pid ! stop.

list_routers() ->
    Routers = routers(),
    lists:foldl( fun({_Pid, Name}, Acc) -> lists:usort([Name] ++ Acc) end, [], Routers).

route_message(From, To, Msg) ->
    {SenderPid, _} = lists:keyfind(From, 2, routers()),
    io:format("routing message: \"~s\"~nfrom: ~w~nto: ~w~n",[Msg, From, To]),
    SenderPid ! {send, To, Msg},
    timer:sleep(1000).

get_network_status() ->
    lists:foreach(fun({Pid, Name}) -> 
        try 
            routy:send_status_msg(Pid)
        catch _ ->
            io:format("could not reach ~s~n", [Name])
        end
        
    end, routers()).