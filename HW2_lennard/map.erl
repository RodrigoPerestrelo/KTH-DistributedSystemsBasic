-module(map).
-export([new/0, update/3, reachable/2, all_nodes/1]).

new() ->
    Map = [],
    Map.

update(Node, Links, Map) ->
    NewMap = [{Node, Links} |lists:keydelete(Node, 1, Map)],
    NewMap.

reachable(Node, Map) ->
    case lists:keyfind(Node, 1, Map) of
        {_, Links} ->
            Links;
        false ->
            []
    end.

all_nodes(Map) ->
    EmptySet = sets:new(),
    AllNodes = extract_nodes_from_map(EmptySet, Map),
    AllNodes.

extract_nodes_from_map(NodeSet, []) ->
    AllNodes = sets:to_list(NodeSet),
    AllNodes;
extract_nodes_from_map(NodeSet, Map) ->
    [{Node, Links} | NewMap] = Map,
    NodeAndLinksList = [Node |Links],
    NodeAndLinksSet = sets:from_list(NodeAndLinksList),
    NewNodeSet = sets:union([NodeSet, NodeAndLinksSet]),
    extract_nodes_from_map(NewNodeSet, NewMap).
