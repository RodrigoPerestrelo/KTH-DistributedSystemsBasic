-module(hist).
-export([new/1, update/3]).

new(Name) ->
    [{Name, inf}].

update(Node, N, History) ->
    case lists:keyfind(Node, 1, History) of
        false ->
            {new, [{Node, N} | History]};
        {Node, Counter} when Counter < N ->
            {new, [{Node, N} | lists:keydelete(Node, 1, History)]};
        {Node, Counter} when Counter >= N ->
            old
    end.