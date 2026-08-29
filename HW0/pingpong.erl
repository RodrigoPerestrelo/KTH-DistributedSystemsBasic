-module(pingpong).
-export([start_pong/0, pong/0, ping/1]).

start_pong() ->
    register(pong_server, spawn(fun pong/0)).

pong() ->
    receive
        {ping, From} ->
            io:format("Pong recebeu ping de ~p~n", [From]),
            From ! pong,
            pong()
    end.

ping(RemoteNode) ->
    {pong_server, RemoteNode} ! {ping, self()},
    receive
        pong ->
            io:format("Ping recebeu resposta de volta!~n", [])
    after 5000 ->
        io:format("Timeout~n", [])
    end.