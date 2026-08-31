-module(rudy_pool).
-export([start/2, stop/0]).

start(Port, Poolsize) ->
    register(rudy, spawn(fun() -> init(Port, Poolsize) end)).

stop() ->
    case whereis(rudy) of
        undefined ->
            ok;
        Pid ->
            Pid ! kill, %% sends the message kill to the supervisor process
            ok
    end.

init(Port, Poolsize) ->
    %% convert into supervisor process
    %% exit signals arriving to the process are converted to {'EXIT', From, Reason} messages
    process_flag(trap_exit, true),
    Opt = [list, {active, false}, {reuseaddr, true}],
    case gen_tcp:listen(Port, Opt) of
        {ok, Listen} ->
            Workers = create_workers(Poolsize, Listen),
            supervise(Listen, Workers);
        {error, Error} ->
            io:format("rudy: listen error: ~w~n", [Error]),
            error
    end.

create_workers(0, _Listen) ->
    [];
create_workers(N, Listen) ->
    Pid = spawn_link(fun() -> handler(Listen) end),
    [Pid | create_workers(N - 1, Listen)].

supervise(Listen, Workers) ->
    receive
        kill ->
            io:format("rudy: stopping listen socket...~n"),
            gen_tcp:close(Listen),
            wait_for_workers(Workers),
            io:format("rudy: all workers finished cleanly.~n"),
            ok
    end.

wait_for_workers([]) ->
    ok;
wait_for_workers(Workers) ->
    receive
        {'EXIT', Pid, _Reason} ->
            wait_for_workers(lists:delete(Pid, Workers))
    end.

handler(Listen) ->
    case gen_tcp:accept(Listen) of
        {ok, Client} ->
            %% Switch to active-once mode: converts the next TCP packet into a {tcp, Client, Str}
            inet:setopts(Client, [{active, once}]),
            request(Client),
            handler(Listen);
        {error, closed} -> %% Any worker currently waiting at accept wakes up with {error, closed} and exits normally with ok.
            io:format("Worker ~p ending (accept closed)...~n", [self()]),            
            ok;
        {error, _Error} ->
            error
    end.

request(Client) ->
    try
        receive
            {tcp, Client, Str} ->
                Request = http:parse_request(Str),
                Response = reply(Request),
                gen_tcp:send(Client, Response);
            {tcp_closed, Client} ->
                ok;
            {tcp_error, Client, Reason} ->
                io:format("rudy: tcp error: ~w~n", [Reason])
            end
    after
        gen_tcp:close(Client)
    end.

reply({{get, URI, _}, _, _}) ->
    timer:sleep(40),
    http:ok("Hello from Rudy! Requested: " ++ URI).