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

%% Helper function to create a process that runs handler function
spawn_worker(Listen) ->
    spawn_link(fun() -> handler(Listen) end).

create_workers(0, _Listen) ->
    [];
create_workers(N, Listen) ->
    Pid = spawn_worker(Listen),
    [Pid | create_workers(N - 1, Listen)].

supervise(Listen, Workers) ->
    receive
        kill ->
            io:format("rudy: stopping listen socket...~n"),
            gen_tcp:close(Listen),
            wait_for_workers(Workers),
            io:format("rudy: all workers finished cleanly.~n"),
            ok;

        %% Handle normal worker exits (ignore)
        {'EXIT', _Pid, normal} ->
            supervise(Listen, Workers);

        %% Auto-restart crashed worker during normal operation
        {'EXIT', DeadPid, Reason} ->
            io:format("rudy: worker ~p crashed (~p). Restarting replacement...~n", [DeadPid, Reason]),
            NewPid = spawn_worker(Listen),
            UpdatedWorkers = [NewPid | lists:delete(DeadPid, Workers)],
            supervise(Listen, UpdatedWorkers)
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
    request(Client, "").

request(Client, Acc) ->
    try
        receive
            {tcp, Client, Str} ->
                %this output is just for testing purposes
                io:format("received chunk of ~p bytes~n", [length(Str)]),
                NewAcc = Acc ++ Str,
                case http:has_header_terminator(NewAcc) of %checkes if recived string has a complete header section
                    false ->
                        inet:setopts(Client, [{active, once}]),
                        request(Client, NewAcc);
                    true ->
                        Request = http:parse_request(NewAcc),
                        {_, Headers, Body} = Request,
                        case lists:keyfind("Content-Length", 1, Headers) of %checks if full body has been received
                            {"Content-Length", LengthStr} ->
                                {ContentLength, _} = string:to_integer(string:trim(LengthStr)),
                                case string:length(Body) >= ContentLength of
                                    true ->
                                        Response = reply(Request),
                                        gen_tcp:send(Client, Response);
                                    false ->
                                        inet:setopts(Client, [{active, once}]),
                                        request(Client, NewAcc)
                                end;
                            false ->
                                Response = reply(Request),
                                gen_tcp:send(Client, Response)
                    end
                end;
            {tcp_closed, Client} ->
                ok;
            {tcp_error, Client, Reason} ->
                io:format("rudy: tcp error: ~w~n", [Reason])
        after 10000 -> %% Timeout if client does not send requests
            io:format("rudy: client request timed out.~n")
        end
    after
        gen_tcp:close(Client)
    end.

reply({{get, URI, _}, _, _}) ->
    timer:sleep(40),
    http:ok("Hello from Rudy! Requested: " ++ URI).