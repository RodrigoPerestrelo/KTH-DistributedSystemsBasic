-module(test).
-export([bench/2, fragmented_request/5]).

bench(Host, Port) ->
    Start = erlang:system_time(micro_seconds),
    run(100, Host, Port),
    Finish = erlang:system_time(micro_seconds),
    Finish - Start.

run(N, Host, Port) ->
    if
        N == 0 ->
            ok;
        true ->
            request(Host, Port),
            run(N-1, Host, Port)
    end.

request(Host, Port) ->
    Opt = [list, {active, false}, {reuseaddr, true}],
    {ok, Server} = gen_tcp:connect(Host, Port, Opt),
    gen_tcp:send(Server, http:get("foo")),
    Recv = gen_tcp:recv(Server, 0),
    case Recv of
        {ok, _} ->
            ok;
        {error, Error} ->
            io:format("test: error: ~w~n", [Error])
            end,
            gen_tcp:close(Server).


fragmented_request(Host, Port, Data, ChunkSize, DelayMs) ->
    {ok, Sock} = gen_tcp:connect(Host, Port, [list, {active, false}]),
    send_chunks(Sock, Data, ChunkSize, DelayMs),
    {ok, Response} = gen_tcp:recv(Sock, 0),
    io:format("~s~n", [Response]),
    gen_tcp:close(Sock).

send_chunks(Sock, [], _ChunkSize, _DelayMs) ->
    ok;
send_chunks(Sock, Data, ChunkSize, DelayMs) ->
    {Chunk, Rest} = case length(Data) =< ChunkSize of
        true -> {Data, []};
        false -> lists:split(ChunkSize, Data)
    end,
    gen_tcp:send(Sock, Chunk),
    timer:sleep(DelayMs),
    send_chunks(Sock, Rest, ChunkSize, DelayMs).