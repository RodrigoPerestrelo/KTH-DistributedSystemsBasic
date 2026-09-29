-module(benchmark).
-export([benchmark/2, benchmark/3]).

%% Runs a sequential benchmark: adds N keys via the Peer node, then looks them all up
benchmark(N, Peer) ->
    Keys = generate_keys(N),
    io:format("Starting addition of ~p elements...~n", [N]),
    T_add_start = erlang:system_time(microsecond),
    add_keys(Keys, Peer),
    T_add_end = erlang:system_time(microsecond),
    Add_Time = T_add_end - T_add_start,
    io:format("Addition completed in ~p us (~p ms)~n", [Add_Time, Add_Time div 1000]),

    io:format("Starting lookup of ~p elements...~n", [N]),
    T_lookup_start = erlang:system_time(microsecond),
    lookup_keys(Keys, Peer),
    T_lookup_end = erlang:system_time(microsecond),
    Lookup_Time = T_lookup_end - T_lookup_start,
    io:format("Lookup completed in ~p us (~p ms)~n", [Lookup_Time, Lookup_Time div 1000]),
    {Add_Time, Lookup_Time}.

%% Concurrent benchmark: spawns multiple client processes to insert and lookup keys in parallel
benchmark(N, Peer, Clients) ->
    KeysPerClient = N div Clients,
    Self = self(),
    io:format("Starting benchmark with ~p clients (~p keys each)...~n", [Clients, KeysPerClient]),
    T_start = erlang:system_time(microsecond),
    Pids = [spawn(fun() -> 
                Keys = generate_keys(KeysPerClient),
                add_keys(Keys, Peer),
                lookup_keys(Keys, Peer),
                Self ! {done, self()}
            end) || _ <- lists:seq(1, Clients)],
    lists:foreach(fun(Pid) -> receive {done, Pid} -> ok end end, Pids),
    T_end = erlang:system_time(microsecond),
    TotalTime = T_end - T_start,
    io:format("Parallel benchmark completed in ~p us (~p ms)~n", [TotalTime, TotalTime div 1000]),
    TotalTime.

%% Generates a list of N random keys using key:generate/0
generate_keys(0) ->
    [];
generate_keys(N) ->
    [key:generate() | generate_keys(N - 1)].

%% Synchronously sends add requests to the ring and waits for an ok response
add_keys([], _Peer) ->
    ok;
add_keys([Key | Rest], Peer) ->
    Qref = make_ref(),
    Peer ! {add, Key, "test_value", Qref, self()},
    receive
        {Qref, ok} ->
            add_keys(Rest, Peer)
    after 10000 ->
        io:format("Timeout while adding key ~p~n", [Key]),
        exit(timeout)
    end.

%% Synchronously sends lookup requests and waits for the matching result
lookup_keys([], _Peer) ->
    ok;
lookup_keys([Key | Rest], Peer) ->
    Qref = make_ref(),
    Peer ! {lookup, Key, Qref, self()},
    receive
        {Qref, {Key, _Value}} ->
            lookup_keys(Rest, Peer);
        {Qref, false} ->
            io:format("Warning: Key ~p was not found!~n", [Key]),
            lookup_keys(Rest, Peer)
    after 10000 ->
        io:format("Timeout while looking up key ~p~n", [Key]),
        exit(timeout)
    end.