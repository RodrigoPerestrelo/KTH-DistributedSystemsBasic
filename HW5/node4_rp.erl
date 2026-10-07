-module(node4).
-export([start/1, start/2, node/6]).

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
    Replica = storage:create(),
    Next = nil,
    node(Id, Predecessor, Successor, Next, Store, Replica).

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

node(Id, Predecessor, Successor, Next, Store, Replica) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {notify, New} ->
            case notify(New, Id, Predecessor, Store) of
                {Pred, NewStore, nil} ->
                    node(Id, Pred, Successor, Next, NewStore, Replica);
                {Pred, NewStore, NewReplica} ->
                    node(Id, Pred, Successor, Next, NewStore, NewReplica)
            end;
        {request, Peer} ->
            request(Peer, Predecessor, Successor),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {status, Pred, Nx} ->
            {Succ, Nxt} = stabilize(Pred, Nx, Id, Successor),
            node(Id, Predecessor, Succ, Nxt, Store, Replica);
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        status ->
            io:format("Node ~p:~n  Predecessor: ~p~n  Successor: ~p~n Next: ~p~n", [Id, Predecessor, Successor, Next]),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        terminate ->
            io:format("Node ~p terminating.~n", [Id]),
            ok;

        probe ->
            create_probe(Id, Successor),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {probe, Id, Nodes, T} ->
            remove_probe(T, Nodes),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {probe, Ref, Nodes, T} ->
            forward_probe(Ref, T, Nodes, Id, Successor),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Next, Added, Replica);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Next, Store, Replica);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            node(Id, Predecessor, Successor, Next, Merged, Replica);

        {replicate, Key, Value, Qref, Client} ->
            NewReplica = storage:add(Key, Value, Replica),
            Client ! {Qref, ok},
            node(Id, Predecessor, Successor, Next, Store, NewReplica);

        {'DOWN', Ref, process, _, _} ->
            {Pred, Succ, Nxt, NewStore, NewReplica} = down(Ref, Predecessor, Successor, Next, Store, Replica),
            node(Id, Pred, Succ, Nxt, NewStore, NewReplica);
        Strange ->
            io:format("Node ~p received an unknown message: ~p~n", [Id, Strange]),
            node(Id, Predecessor, Successor, Next, Store, Replica)
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
            {Keep, Rest} = handover(Id, Store, Nkey, Npid),
            Nref = monitor(Npid),
            {{Nkey, Nref, Npid}, Keep, Rest};
        {Pkey, Pref,  _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    drop(Pref),
                    {Keep, Rest} = handover(Id, Store, Nkey, Npid),
                    Nref = monitor(Npid),
                    {{Nkey, Nref, Npid}, Keep, Rest};
                false ->
                    {Predecessor, Store, nil}
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
                    NewStore = storage:add(Key, Value, Store),
                    {_, _, Spid} = Successor,
                    Spid ! {replicate, Key, Value, Qref, Client},
                    NewStore;
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
    {Keep, Rest}.

monitor(Pid) ->
    erlang:monitor(process, Pid).

drop(nil) ->
    ok;
drop(Ref) ->
    erlang:demonitor(Ref, [flush]).

down(Ref, {_, Ref, _}, Successor, Next, Store, Replica) ->
    %% Predecessor died
    MergedStore = storage:merge(Store, Replica),
    NewReplica = storage:create(),
    {nil, Successor, Next, MergedStore, NewReplica};
down(Ref, Predecessor, {_, Ref, _}, {Nkey, Npid}, Store, Replica) ->
    %% Sucessor died
    drop(Ref),
    Nref = monitor(Npid),
    self() ! stabilize,
    {Predecessor, {Nkey, Nref, Npid}, nil, Store, Replica}.