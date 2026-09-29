-module(storage).
-export([create/0, add/3, lookup/2, split/3, merge/2]).

create() ->
    [].

add(Key, Value, Store) ->
    lists:keystore(Key, 1, Store, {Key, Value}).

lookup(Key, Store) ->
    lists:keyfind(Key, 1, Store).

split(From, To, Store) ->
    lists:partition(fun({K, _}) -> key:between(K, From, To) end, Store).

merge(Entries, Store) ->
    lists:foldl(fun({K, V}, Acc) -> add(K, V, Acc) end, Store, Entries).