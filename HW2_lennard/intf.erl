-module(intf).
-export([new/0, add/4, remove/2, lookup/2, ref/2, name/2, list/1, broadcast/2]).

new() ->
    Intf = [],
    Intf.

add(Name, Ref, Pid, Intf) ->
    NewIntf = [{Name, Ref, Pid} | Intf],
    NewIntf.

remove(Name, Intf) ->
    NewIntf = lists:keydelete(Name, 1, Intf),
    NewIntf.

lookup(Name, Intf) ->
    case lists:keyfind(Name, 1, Intf) of
        false -> notfound;
        {_, _, Pid} -> {ok, Pid}
    end.

ref(Name, Intf) ->
    case lists:keyfind(Name, 1, Intf) of
        false -> notfound;
        {_, Ref, _} -> {ok, Ref}
    end.

name(Ref, Intf) ->
    case lists:keyfind(Ref, 2, Intf) of
        false -> notfound;
        {Name, _, _} -> {ok, Name}
    end.

list(Intf) ->
    Names = lists:foldl(
        fun({Name, _, _}, Acc) ->
            [Name | Acc]
        end,
        [],
        Intf),
    Names.

broadcast(Message, Intf) ->
    lists:foreach(
        fun({_, _, Pid}) ->
            Pid ! Message
        end,
        Intf).
