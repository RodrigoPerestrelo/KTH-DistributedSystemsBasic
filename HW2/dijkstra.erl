-module(dijkstra).
-export([table/2, route/2]).

entry(Node, Sorted) ->
    case lists:keyfind(Node, 1, Sorted) of
        {Node, Length, _} -> Length;
        false -> 0
    end.

replace(Node, N, Gateway, Sorted) ->
    UpdatedList = lists:delete(Node, 1, Sorted),
    insert({Node, N, Gateway}, UpdatedList).

insert({Node, N, Gateway}, []) ->
    [{Node, N, Gateway}];
insert({Node, N, Gateway}, [{HNode, HN, HGw} | Rest]) when N < HN ->
    [{Node, N, Gateway}, {HNode, HN, HGw} | Rest];
insert(Entry, [Head | Rest]) ->
    [Head | insert(Entry, Rest)].

update(Node, N, Gateway, Sorted) ->
    ExistingLength = entry(Node, Sorted),
    case ExistingLength of
        0 ->
            Sorted;
        Length when N < Length ->
            replace(Node, N, Gateway, Sorted);
        _ ->
            Sorted
    end.

%% no more entries in the sorted list
iterate([], _Map, Table) ->
    Table;
%% first entry is a dummy entry with an infinite path to a city
iterate([{_Node, inf, _Gateway} | _Tail], _Map, Table) ->
    Table;
%% take the first entry in the sorted list, find the nodes in the
%% map reachable from this entry, and for each of these nodes, update the
%% Sorted list. The entry that you took from the sorted list is added to the routing table.
iterate([{Node, Hops, Gateway} | Tail], Map, Table) ->
    Reachable = map:reachable(Node, Map),
    UpdatedSorted = lists:foldl( fun(Neighbor, Acc) -> update(Neighbor, Hops + 1, Gateway, Acc) end, Tail, Reachable),
    iterate(UpdatedSorted, Map, Table ++ [{Node, Gateway}]).

table(Gateways, Map) ->
    AllNodes = map:all_nodes(Map),
    Sorted = lists:foldl(
        fun(Node, Acc) -> 
            case lists:member(Node, Gateways) of
                true -> [{Node, 0, Node} | Acc];
                false -> Acc ++ [{Node, inf, unknown}]
            end
        end,
        [],
        AllNodes
    ),
    iterate(Sorted, Map, []).

route(Node, Table) -> 
    case lists:member(Node, 1, Table) of
        {Node, Gateway} -> {ok, Gateway};
        false -> notfound
    end.
