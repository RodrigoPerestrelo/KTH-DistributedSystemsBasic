-module(chunk_script).
-export([main/1]).

%Sends a long request in 20 byte sized chunks to the server to test
%still missing testitng for some edge cases

main([TestFunction]) ->
    case TestFunction of
        "default" ->
            io:format("sending request in 20 byte chunks with 500 byte body\n"),
            same_sized_chunks();
        "no_body" ->
            io:format("sending request with content-length 0 and no body\n"),
            no_body();
        "cutoff" ->
            io:format("sending request with header ending in two seperate chunks\n"),
            cutoff_crlf();
        "timeout" ->
            io:format("sending request that waits 15s between chunks causing timeout\n"),
            timeout();
        "invalid_content_length" ->
            io:format("sending request with invalid content length"),
            invalid_content_length();
        "all" ->
            io:format("sending request in 20 byte chunks with 500 byte body\n"),
            same_sized_chunks(),
            io:format("sending request with content-length 0 and no body\n"),
            no_body(),
            io:format("sending request with header ending in two seperate chunks\n"),
            cutoff_crlf(),
            io:format("sending request that waits 15s between chunks causing timeout\n"),
            timeout(),
            io:format("sending request with invalid content length"),
            invalid_content_length()
    end.


same_sized_chunks() ->
    Body = lists:duplicate(500, $a),
    Req = "GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: "
    ++ integer_to_list(length(Body)) ++ "\r\n\r\n" ++ Body,
    test:fragmented_request("localhost", 8080, Req, 20, 20).

no_body() ->
    Req = ["GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 0\r\n\r\n"],
    test:chunk_list_request("localhost", 8080, Req, 20).

cutoff_crlf() ->
    Req = ["GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 38\r\n\r","\nHello this is the body of the request!"],
    test:chunk_list_request("localhost", 8080, Req, 20).

timeout() ->
    Req = ["GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: 500\r\n\r","\nHello this is the body of the request!"],
    test:timeout_request("localhost", 8080, Req).

invalid_content_length() ->
    Req = ["GET / HTTP/1.1\r\nHost: localhost\r\nContent-Length: invalid\r\n\r\nHello this is the body of the request!"],
    test:chunk_list_request("localhost", 8080, Req, 20).