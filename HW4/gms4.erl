-module(gms4).
-export([start/1, start/2]).

-define(timeout, 1000).
-define(resend_interval, 300).
-define(arghh, 500).
-define(drop, 100).

%% Start the first process in the group (Leader)
start(Id) ->
    Rnd = rand:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Rnd, Self) end)}.

init(Id, Rnd, Master) ->
    rand:seed(exsss, {Rnd, Rnd, Rnd}),
    erlang:send_after(?resend_interval, self(), resend),
    leader(Id, Master, 0, [], [Master], [], []).

%% MsgBuffer: [{N, Wire}] in ascending order of N, where Wire is the exact message that was sent to the slaves
%% Acks:      [{SlavePid, HighestAckedN}]
leader(Id, Master, N, Slaves, Group, MsgBuffer, Acks) ->
    receive
        {mcast, Msg} ->
            Wire = {msg, N, Msg},
            bcast(Id, Wire, Slaves),
            MsgBuffer2 = MsgBuffer ++ [{N, Wire}],
            Master ! Msg,
            leader(Id, Master, N + 1, Slaves, Group, MsgBuffer2, Acks);
        {join, Wrk, Peer} ->
            Slaves2 = lists:append(Slaves, [Peer]),
            Group2 = lists:append(Group, [Wrk]),
            View = {view, N, [self()|Slaves2], Group2},
            bcast(Id, View, Slaves2),
            MsgBuffer2 = MsgBuffer ++ [{N, View}],
            Acks2 = lists:keystore(Peer, 1, Acks, {Peer, N - 1}),
            Master ! {view, Group2},
            leader(Id, Master, N + 1, Slaves2, Group2, MsgBuffer2, Acks2);
        {ack, From, I} ->
            Old = acked(From, Acks),
            Acks2 = lists:keystore(From, 1, Acks, {From, max(Old, I)}),
            MsgBuffer2 = prune(MsgBuffer, Slaves, Acks2),
            leader(Id, Master, N, Slaves, Group, MsgBuffer2, Acks2);
        resend ->
            resend(Id, MsgBuffer, Slaves, Acks),
            erlang:send_after(?resend_interval, self(), resend),
            leader(Id, Master, N, Slaves, Group, MsgBuffer, Acks);
        stop ->
            ok
    end.

prune(_Buffer, [], _Acks) ->
    [];
prune(Buffer, Slaves, Acks) ->
    Min = lists:min([acked(S, Acks) || S <- Slaves]),
    [{N, Wire} || {N, Wire} <- Buffer, N > Min].

acked(Slave, Acks) ->
    case lists:keyfind(Slave, 1, Acks) of
        {Slave, I} -> I;
        false      -> -1
    end.

resend(Id, Buffer, Slaves, Acks) ->
    lists:foreach(
        fun(S) ->
            Last = acked(S, Acks),
            Missing = [Wire || {N, Wire} <- Buffer, N > Last],
            case Missing of
                [] ->
                    ok;
                _ ->
                    io:format("leader ~w: resending ~w message(s) to ~w~n",
                              [Id, length(Missing), S]),
                    lists:foreach(fun(Wire) -> lossy(S, Wire) end, Missing)
            end
        end,
        Slaves).


%% Start a process joining an existing group (Slave)
start(Id, Grp) ->
    Rnd = rand:uniform(1000),
    Self = self(),
    {ok, spawn_link(fun() -> init(Id, Grp, Rnd, Self) end)}.

init(Id, Grp, Rnd, Master) ->
    rand:seed(exsss, {Rnd, Rnd, Rnd}),
    Self = self(),
    Grp ! {join, Master, Self},
    receive
        {view, N, [Leader | Slaves], Group} ->
            Master ! {view, Group},
            erlang:monitor(process, Leader),
            send_ack(Leader, N),
            Last = {view, N, [Leader | Slaves], Group},
            slave(Id, Master, Leader, N + 1, Last, Slaves, Group)
    after ?timeout ->
        Master ! {error, "no reply from leader"}
    end.

slave(Id, Master, Leader, N, Last, Slaves, Group) ->
    receive
        {mcast, Msg} ->
            Leader ! {mcast, Msg},
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {join, Wrk, Peer} ->
            Leader ! {join, Wrk, Peer},
            slave(Id, Master, Leader, N, Last, Slaves, Group);

        {msg, I, _} when I < N ->
            send_ack(Leader, I),
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {msg, N, Msg} ->
            Master ! Msg,
            send_ack(Leader, N),
            Last2 = {msg, N, Msg},
            slave(Id, Master, Leader, N + 1, Last2, Slaves, Group);

        {view, I, _, _} when I < N ->
            send_ack(Leader, I),
            slave(Id, Master, Leader, N, Last, Slaves, Group);
        {view, N, [Leader|Slaves2], Group2} ->
            Master ! {view, Group2},
            send_ack(Leader, N),
            Last2 = {view, N, [Leader | Slaves2], Group2},
            slave(Id, Master, Leader, N + 1, Last2, Slaves2, Group2);

        {'DOWN', _Ref, process, Leader, _Reason} ->
            election(Id, Master, N, Last, Slaves, Group);
        stop ->
            ok
    end.


bcast(Id, Msg, Nodes) ->
    lists:foreach(fun(Node) -> lossy(Node, Msg), crash(Id) end, Nodes).

send_ack(Leader, I) ->
    lossy(Leader, {ack, self(), I}).

lossy(Node, Msg) ->
    case rand:uniform(?drop) of
        ?drop ->
            io:format("node ~w: dropped a ~w message~n", [Node, element(1, Msg)]);
        _ ->
            Node ! Msg
    end.

crash(Id) ->
    case rand:uniform(?arghh) of
        ?arghh ->
            io:format("leader ~w: crash~n", [Id]),
            exit(no_luck);
        _ ->
            ok
    end.

election(Id, Master, N, Last, Slaves, Group) ->
    Self = self(),
    case Slaves of
        [Self | Rest] ->
            View = {view, N, Slaves, Group},
            bcast(Id, Last, Rest),
            bcast(Id, View, Rest),
            Master ! {view, Group},
            erlang:send_after(?resend_interval, self(), resend),
            leader(Id, Master, N + 1, Rest, Group,
                   [{N - 1, Last}, {N, View}], []);
        [Leader | Rest] ->
            erlang:monitor(process, Leader),
            slave(Id, Master, Leader, N, Last, Rest, Group)
    end.