-module(world_test).
-export([setup_world/0, route_message/3, list_routers/0, teardown_world/0, kill_router/1, get_network_status/0, start_router/1]).

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

%% Resolves a router process PID across shells or locally.
%% Accepts either a registration tag (e.g. 'r1') or a city name (e.g. 'stockholm').
whereis_remote(Key) ->
    City = case lists:keyfind(Key, 1, routers()) of
        {_Reg, Name} -> Name;
        false ->
            case lists:keyfind(Key, 2, routers()) of
                {_Reg, Name} -> Name;
                false -> Key
            end
    end,
    {Reg, _} = lists:keyfind(City, 2, routers()),

    %% Check the current shell first; if absent, query the remote Erlang node
    case whereis(Reg) of
        Pid when is_pid(Pid) -> 
            Pid;
        undefined ->
            case node() of
                'nonode@nohost' -> undefined;
                CurrentNode ->
                    Host = hd(tl(string:tokens(atom_to_list(CurrentNode), "@"))),
                    RemoteNode = list_to_atom(atom_to_list(City) ++ "@" ++ Host),
                    net_adm:ping(RemoteNode),
                    rpc:call(RemoteNode, erlang, whereis, [Reg])
            end
    end.

start_router(Name) ->
    {Reg, Name} = lists:keyfind(Name, 2, routers()),
    routy:start(Reg, Name).

%% Wires the network topology. Supports both execution environments:
%% 1. Single-shell fallback: uses test:setup/2 to start and link all nodes locally.
%% 2. Distributed multi-shell: discovers remote PIDs across nodes and adds interfaces.
setup_world() ->
    Routers = routers(),
    Cons = cons(),
    case node() of
        'nonode@nohost' -> 
            test:setup(Routers, Cons);
        _ ->
            lists:foreach(fun({R1, R2}) ->
                {R2, Name2} = lists:keyfind(R2, 1, routers()),
                (whereis_remote(R1)) ! {add, Name2, whereis_remote(R2)}
            end, Cons),
            timer:sleep(2000),
            ok
    end.

teardown_world() ->
    Routers = routers(),
    test:stop_all(Routers).

kill_router(Name) ->
    {Reg, _} = lists:keyfind(Name, 2, routers()),
    Pid = whereis_remote(Reg),
    Pid ! stop.

list_routers() ->
    Routers = routers(),
    lists:foldl( fun({_Pid, Name}, Acc) -> lists:usort([Name] ++ Acc) end, [], Routers).

route_message(From, To, Msg) ->
    {Reg, _} = lists:keyfind(From, 2, routers()),
    SenderPid = whereis_remote(Reg),
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