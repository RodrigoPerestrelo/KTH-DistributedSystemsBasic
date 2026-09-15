-module(dijkstra).
-export([table/2, route/2]).

route(Node, Table) ->
    case lists:keyfind(Node, 1, Table) of
        false -> notfound;
        {_, Gateway} -> {ok, Gateway}
    end.

table(Gateways, Map) ->
    AllNodes = map:all_nodes(Map),
    NewSorted = lists:foldl(
    fun(Node, Acc) ->
        replace(Node, inf, unknown, Acc)
    end,
    [],
    AllNodes),
    AllNodesAndGateways = lists:foldl(
    fun(Gateway, Acc) ->
        replace(Gateway, 0, Gateway, Acc)
    end,
    NewSorted,
    Gateways),
    iterate(AllNodesAndGateways, Map, []).


iterate([], _Map, Table) ->
    Table;
iterate([{_, inf, _}|_Rest], _Map, Table) ->
    Table;
iterate(Sorted, Map, Table) ->
    [{Node, Length, Gateway} |RestSorted] = Sorted,
    Reachable = map:reachable(Node, Map),
    NewSorted = lists:foldl(
    fun(Neighbor, Acc) ->
        update(Neighbor, Length+1, Gateway, Acc)
    end,
    RestSorted,
    Reachable),
    NewTable = [{Node, Gateway} |Table],
    iterate(NewSorted, Map, NewTable).


entry(Node, Sorted) ->
    case lists:keyfind(Node, 1, Sorted) of
        false ->
            0;
        {_, Length, _} ->
            Length
    end.

replace(Node, N, Gateway, Sorted) ->
    NewList = [{Node, N, Gateway} | lists:keydelete(Node, 1, Sorted)],
    lists:sort(fun sorting_by_length/2, NewList).

sorting_by_length(A, B) ->
    {_, LengthA, _} = A,
    {_, LengthB, _} = B,
    LengthA =< LengthB.

update(Node, N, Gateway, Sorted) ->
    case entry(Node, Sorted) of
        0 ->
            Sorted;
        Length when Length > N ->
            replace(Node, N, Gateway, Sorted);
        Length when Length =< N ->
            Sorted
    end.