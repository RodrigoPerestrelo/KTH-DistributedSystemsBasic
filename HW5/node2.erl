-module(node2).
-export([start/1, start/2, node/4]).

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
    node(Id, Predecessor, Successor, Store).

connect(Id, nil) ->
    {ok, {Id, self()}};
connect(_Id, Peer) ->
    Qref = make_ref(),
    Peer ! {key, Qref, self()},
    receive
        {Qref, Skey} ->
            {ok, {Skey, Peer}}
    after ?Timeout ->
        io:format("Timeout: no response~n", []),
        exit(timeout)
    end.

schedule_stabilize() ->
    timer:send_interval(?Stabilize, self(), stabilize).

node(Id, Predecessor, Successor, Store) ->
    receive
        {key, Qref, Peer} ->
            Peer ! {Qref, Id},
            node(Id, Predecessor, Successor, Store);
        {notify, New} ->
            {Pred, NewStore} = notify(New, Id, Predecessor, Store),
            node(Id, Pred, Successor, NewStore);
        {request, Peer} ->
            request(Peer, Predecessor),
            node(Id, Predecessor, Successor, Store);
        {status, Pred} ->
            Succ = stabilize(Pred, Id, Successor),
            node(Id, Predecessor, Succ, Store);
        stabilize ->
            stabilize(Successor),
            node(Id, Predecessor, Successor, Store);
        status ->
            io:format("Node ~p:~n  Predecessor: ~p~n  Successor: ~p~n", [Id, Predecessor, Successor]),
            node(Id, Predecessor, Successor, Store);
        terminate ->
            io:format("Node ~p terminating.~n", [Id]),
            ok;

        probe ->
            create_probe(Id, Successor),
            node(Id, Predecessor, Successor, Store);
        {probe, Id, Nodes, T} ->
            remove_probe(T, Nodes),
            node(Id, Predecessor, Successor, Store);
        {probe, Ref, Nodes, T} ->
            forward_probe(Ref, T, Nodes, Id, Successor),
            node(Id, Predecessor, Successor, Store);
        
        {add, Key, Value, Qref, Client} ->
            Added = add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Added);
        {lookup, Key, Qref, Client} ->
            lookup(Key, Qref, Client, Id, Predecessor, Successor, Store),
            node(Id, Predecessor, Successor, Store);
        {handover, Elements} ->
            Merged = storage:merge(Store, Elements),
            node(Id, Predecessor, Successor, Merged);

        Strange ->
            io:format("Node ~p received an unknown message: ~p~n", [Id, Strange]),
            node(Id, Predecessor, Successor, Store)
    end.

stabilize({_, Spid}) ->
    Spid ! {request, self()}.

request(Peer, Predecessor) ->
    case Predecessor of
        nil ->
            Peer ! {status, nil};
        {Pkey, Ppid} ->
            Peer ! {status, {Pkey, Ppid}}
    end.

stabilize(Pred, Id, Successor) ->
    {Skey, Spid} = Successor,
    case Pred of
        nil ->
            Spid ! {notify, {Id, self()}},
            Successor;
        {Id, _} ->
            Successor; 
        {Skey, _} ->
            Spid ! {notify, {Id, self()}},
            Successor;
        {Xkey, Xpid} ->
            case key:between(Xkey, Id, Skey) of
                true ->
                    Xpid ! {request, self()},
                    {Xkey, Xpid};
                false ->
                    Spid ! {notify, {Id, self()}},
                    Successor
    end
end.

notify({Nkey, Npid}, Id, Predecessor, Store) ->
    case Predecessor of
        nil ->
            Keep = handover(Id, Store, Nkey, Npid),
            {{Nkey, Npid}, Keep};
        {Pkey, _} ->
            case key:between(Nkey, Pkey, Id) of
                true ->
                    Keep = handover(Id, Store, Nkey, Npid),
                    {{Nkey, Npid}, Keep};
                false ->
                    Predecessor
            end
    end.

create_probe(Id, {_, Spid}) ->
    T = erlang:system_time(microsecond),
    Spid ! {probe, Id, [self()], T}.

remove_probe(T, Nodes) ->
    Elapsed = erlang:system_time(microsecond) - T,
    io:format("Probe returned in ~p microseconds after ~p hops: ~p~n", 
              [Elapsed, length(Nodes), Nodes]).

forward_probe(Ref, T, Nodes, _Id, {_, Spid}) ->
    Spid ! {probe, Ref, [self() | Nodes], T}.

add(Key, Value, Qref, Client, Id, Predecessor, Successor, Store) ->
    case Predecessor of
        nil ->
            Client ! {Qref, ok},
            storage:add(Key, Value, Store);
        {Pkey, _} ->
            case key:between(Key, Pkey, Id) of
                true ->
                    Client ! {Qref, ok},
                    storage:add(Key, Value, Store);
                false ->
                    {_, Spid} = Successor,
                    Spid ! {add, Key, Value, Qref, Client},
                    Store
            end
    end.

lookup(Key, Qref, Client, Id, Predecessor, Successor, Store) ->
    case Predecessor of
        nil ->
            Result = storage:lookup(Key, Store),
            Client ! {Qref, Result};
        {Pkey, _} ->
            case key:between(Key, Pkey, Id) of
                true ->
                    Result = storage:lookup(Key, Store),
                    Client ! {Qref, Result};
                false ->
                    {_, Spid} = Successor,
                    Spid ! {lookup, Key, Qref, Client}
            end
    end.

handover(Id, Store, Nkey, Npid) ->
    {Keep, Rest} = storage:split(Nkey, Id, Store),
    Npid ! {handover, Rest},
    Keep.