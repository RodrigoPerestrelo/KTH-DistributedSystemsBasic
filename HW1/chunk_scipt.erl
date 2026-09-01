-module(chunk_script).
-export([main/1]).

%Sends a long request in 20 byte sized chunks to the server to test
%still missing testitng for some edge cases

main(_Args) ->
    Body = lists:duplicate(5000, $a),
    Req = "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: "
    ++ integer_to_list(length(Body)) ++ "\r\n\r\n" ++ Body,
    test:fragmented_request("localhost", 8080, Req, 20, 20).