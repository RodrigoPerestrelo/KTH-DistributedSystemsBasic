-module(map).
-export([new/0, update/3, reachable/2, all_nodes/1]).

new() ->
    [].

update(Node, Links, Map) ->
    [{Node, Links} | lists:keydelete(Node, 1, Map)].

reachable(Node, Map) ->
    case lists:keyfind(Node, 1, Map) of
        {Node, Links} -> Links;
        false         -> []
    end.

%% Returns a distinct list of all nodes (sources and destinations)
all_nodes(Map) ->
    lists:foldl( fun({Node, Links}, Acc) -> lists:usort([Node | Links] ++ Acc) end, [], Map).
