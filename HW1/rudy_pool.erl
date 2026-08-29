-module(rudy_pool).
-export([start/2, stop/0]).

start(Port, Poolsize) ->
    register(rudy, spawn(fun() -> init(Port, Poolsize) end)).

stop() ->
    case whereis(rudy) of
        undefined ->
            ok;
        Pid ->
            exit(Pid, "time to die")
    end.

init(Port, Poolsize) ->
    Opt = [list, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(Port, Opt) of
        {ok, Listen} ->
            create_handlers(Poolsize, Listen),
            keepalive();
        {error, _Error} ->
            error
    end.

keepalive() ->
    receive
        stop ->
            ok
    end.

create_handlers(0, _Listen) ->
    ok;
create_handlers(N, Listen) ->
    spawn_link(fun() -> handler(Listen) end),
    create_handlers(N - 1, Listen).

handler(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Client} ->
            request(Client),
            handler(Listen);
        {error, _Error} ->
            error
    end.

request(Client) ->
    Recv = gen_tcp:recv(Client, 0),
    case Recv of
        {ok, Str} ->
            Request = http:parse_request(Str),
            Response = reply(Request),
            gen_tcp:send(Client, Response);
        {error, Error} ->
            io:format("rudy: error: ~w~n", [Error])
            end,
            gen_tcp:close(Client).

reply({{get, URI, _}, _, _}) ->
    timer:sleep(40),
    http:ok("Hello from Rudy! Requested: " ++ URI).