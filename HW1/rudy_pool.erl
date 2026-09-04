-module(rudy_pool).
-export([start/2, stop/0]).

-define(REQUEST_TIMEOUT, 10000).

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
    try
        request_loop(Client, "")
    after
        gen_tcp:close(Client)
    end.

request_loop(Client, Acc) ->
    receive
        {tcp, Client, Str} ->
            %this output is just for testing purposes
            io:format("received header chunk of ~p bytes~n", [length(Str)]),
            NewAcc = Acc ++ Str,
            case handel_header_chunk(NewAcc) of
                {continue, _} ->
                    inet:setopts(Client, [{active, once}]),
                    request_loop(Client, NewAcc);
                {done, Response} ->
                    io:format("request complete, sending reply\n"),
                    gen_tcp:send(Client, Response);
                {receive_body, Request, ContentLength} ->
                    {RequestLine, Headers, Body} = Request,
                    case body_loop(Client, RequestLine, Headers, Body, ContentLength) of
                        timeout -> ok;
                        Response -> 
                            io:format("request complete, sending reply\n"),
                            gen_tcp:send(Client, Response)
                    end;
                {bad_request, Response} ->
                    io:format("bad request, sending 400\n"),
                    gen_tcp:send(Client, Response)
            end;
        {tcp_closed, Client} ->
            ok;
        {tcp_error, Client, Reason} ->
            io:format("rudy: tcp error: ~w~n", [Reason])
    after ?REQUEST_TIMEOUT -> %% Timeout if client does not send requests
        io:format("rudy: client request timed out.~n")
    end.

handel_header_chunk(NewAcc) ->
    case http:has_header_terminator(NewAcc) of
        false -> {continue, NewAcc};
        true ->
            Request = http:parse_request(NewAcc),
            {_RequestLine, Headers, Body} = Request,
            case content_length(Headers) of
                {ok, ContentLength} when length(Body) < ContentLength -> {receive_body, Request, ContentLength};
                {ok, _ContentLength} -> {done, reply(Request)};
                no_body -> {done, reply(Request)};
                {error, _Reason} -> {bad_request, http:bad_request("Invalid Content Length")}
            end
    end.

content_length(Headers) ->
    case lists:keyfind("Content-Length", 1, Headers) of
        {"Content-Length", LengthStr} ->
            case string:to_integer(LengthStr) of
                {ContentLength, _} when is_integer(ContentLength), ContentLength >= 0 ->
                    {ok, ContentLength};
                _ -> {error, invalid_content_length}
            end;
        false ->
            no_body
    end.

body_loop(Client, RequestLine, Headers, BodyAcc, ContentLength) ->
    inet:setopts(Client, [{active, once}]),
    receive
        {tcp, Client, Str} ->
            io:format("received body chunk of ~p bytes~n", [length(Str)]),
            NewBodyAcc = BodyAcc ++ Str,
            case length(NewBodyAcc) == ContentLength of
                true ->
                    reply({RequestLine, Headers, NewBodyAcc});
                false ->
                    body_loop(Client, RequestLine, Headers, NewBodyAcc, ContentLength)
            end
    after ?REQUEST_TIMEOUT -> %% Timeout if client does not send requests
        io:format("rudy: client request timed out.~n"),
        timeout
    end.

reply({{get, URI, _}, _, _}) ->
    timer:sleep(40),
    http:ok("Hello from Rudy! Requested: " ++ URI).