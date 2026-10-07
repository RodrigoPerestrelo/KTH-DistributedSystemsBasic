-module(node3).
-export([start/1, start/2, node/5]).

-define(Stabilize, 1000).
-define(Timeout, 10000).

start(Id) ->
    start(Id, nil).

start(Id, Peer) ->
    timer:start(),
    spawn(fun() -> init(Id, Peer) end).

init(Id, Peer) ->
    Predecessor = nil,
    {ok, Successor} = connect(Id, Peer),
    schedule_stabilize(),
    Store = storage:create(),
    Next = nil,
    node(Id, Predecessor, Successor, Next, Store).

connect(Id, nil) ->
    Ref = monitor(self()),
    {ok, {Id, Ref, self()}};
connect(_Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            Ref = monitor(Peer),
            {ok, {Skey, Ref, Peer}}
    after ?Timeout ->
        io:format("Timeout: no response~n", []),
        exit(timeout)
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

node(Id, Predecessor, Successor, Next, Store) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Next, Store);
        {notify, New} ->
            {Pred, NewStore} = notify(New, Id, Predecessor, Store),
            node(Id, Pred, Successor, Next, NewStore);
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(Id, Predecessor, Successor, Next, Store);
        {status, Pred, Nx} ->
            {Succ, Nxt} = stabilize(Pred, Nx, Id, Successor),
            node(Id, Predecessor, Succ, Nxt, Store);
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Next, Store);
        status ->
            io:format("Node ~p:~n  Predecessor: ~p~n  Successor: ~p~n Next: ~p~n", [Id, Predecessor, Successor, Next]),
            node(Id, Predecessor, Successor, Next, Store);
        terminate ->
            io:format("Node ~p terminating.~n", [Id]),
            ok;

        probe ->
            create_probe(Id, Successor),
            node(Id, Predecessor, Successor, Next, Store);
        {probe, Id, Nodes, T} ->
            remove_probe(T, Nodes),
            node(Id, Predecessor, Successor, Next, Store);
        {probe, Ref, Nodes, T} ->
            forward_probe(Ref, T, Nodes, Id, Successor),
            node(Id, Predecessor, Successor, Next, Store);
        
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Next, Added);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Next, Store);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            node(Id, Predecessor, Successor, Next, Merged);

        {'DOWN', Ref, process, _, _} ->
            {Pred, Succ, Nxt} = down(Ref, Predecessor, Successor, Next),
            node(Id, Pred, Succ, Nxt, Store);
        Strange ->
            io:format("Node ~p received an unknown message: ~p~n", [Id, Strange]),
            node(Id, Predecessor, Successor, Next, Store)
    end.

stabilize({_, _, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor, {Skey, _, Spid}) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil, {Skey, Spid}};
        {Pkey, _, Ppid} ->
            Peer ! {status, {Pkey, Ppid}, {Skey, Spid}}
    end.

stabilize(Pred, Nx, Id, Successor) ->
    {Skey, Sref, Spid} = Successor,
    case Pred of
        nil ->
            Spid ! {notify, {Id, self()}},
            {Successor, Nx};
        {Id, _} ->
            {Successor, Nx};
        {Skey, _} ->
            Spid ! {notify, {Id, self()}},
            {Successor, Nx};
        {Xkey, Xpid} ->
            case key:between(Xkey, Id, Skey) of
                true ->
                    drop(Sref),
                    Xref = monitor(Xpid),
                    Xpid ! {request, self()},
                    {{Xkey, Xref, Xpid}, {Skey, Spid}};
                false ->
                    Spid ! {notify, {Id, self()}},
                    {Successor, Nx}
    end
end.

notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        nil ->
            Keep = handover(Id, Store, Nkey, Npid),
            Nref = monitor(Npid),
            {{Nkey, Nref, Npid}, Keep};
        {Pkey, Pref,  _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    drop(Pref),
                    Keep = handover(Id, Store, Nkey, Npid),
                    Nref = monitor(Npid),
                    {{Nkey, Nref, Npid}, Keep};
                false ->
                    {Predecessor, Store}
            end
    end.

create_probe(Id, {_, _, Spid}) ->
    T = erlang:system_time(microsecond),
    Spid ! {probe, Id, [self()], T}.

remove_probe(T, Nodes) ->
    Elapsed = erlang:system_time(microsecond) - T,
    io:format("Probe returned in ~p microseconds after ~p hops: ~p~n", 
              [Elapsed, length(Nodes), Nodes]).

forward_probe(Ref, T, Nodes, _Id, {_, _, Spid}) ->
    Spid ! {probe, Ref, [self() | Nodes], T}.

add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store) ->
    case Predecessor of
        nil ->
            Client ! {Qref, ok},
            storage:add(Key, Value, Store);
        {Pkey, _, _} ->
            case key:between(Key, Pkey, Id) of
                true ->
                    Client ! {Qref, ok},
                    storage:add(Key, Value, Store);
                false ->
                    {_, _,Spid} = Successor,
                    Spid ! {add, Key, Value, Qref, Client},
                    Store
            end
    end.

lookup(Key, Qref, Client, Id, Predecessor, Successor, Store) ->
    case Predecessor of
        nil ->
            Result = storage:lookup(Key, Store),
            Client ! {Qref, Result};
        {Pkey, _, _} ->
            case key:between(Key, Pkey, Id) of
                true ->
                    Result = storage:lookup(Key, Store),
                    Client ! {Qref, Result};
                false ->
                    {_, _, Spid} = Successor,
                    Spid ! {lookup, Key, Qref, Client}
            end
    end.

handover(Id, Store, Nkey, Npid) ->
    {Keep, Rest} = storage:split(Nkey, Id, Store),
    Npid ! {handover, Rest},
    Keep.

monitor(Pid) ->
    erlang:monitor(process, Pid).

drop(nil) ->
    ok;
drop(Ref) ->
    erlang:demonitor(Ref, [flush]).

down(Ref, {_, Ref, _}, Successor, Next) ->
    %% Predecessor died
    {nil, Successor, Next};
down(Ref, Predecessor, {_, Ref, _}, {Nkey, Npid}) ->
    %% Sucessor died
    drop(Ref),
    Nref = monitor(Npid),
    self() ! stabilize,
    {Predecessor, {Nkey, Nref, Npid}, nil}.