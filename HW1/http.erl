-module(http).
-export([parse_request/1, ok/1, get/1, has_header_terminator/1, bad_request/1]).

has_header_terminator(R0) ->
    case string:split(R0, "\r\n\r\n") of
        [_, _] -> true;
        [_] -> false
    end.

parse_request(R0) ->
    {Request, R1} = request_line(R0),
    {Headers, R2} = headers(R1),
    {Body, _} = message_body(R2),
    {Request, Headers, Body}.

request_line([$G, $E, $T, 32 |R0]) ->
    {URI, R1} = request_uri(R0),
    {Ver, R2} = http_version(R1),
    [13,10|R3] = R2,
    {{get, URI, Ver}, R3}.

request_uri([32|R0])->
    {[], R0};
request_uri([C|R0]) ->
    {Rest, R1} = request_uri(R0),
    {[C|Rest], R1}.

http_version([$H, $T, $T, $P, $/, $1, $., $1 | R0]) ->
    {v11, R0};
http_version([$H, $T, $T, $P, $/, $1, $., $0 | R0]) ->
    {v10, R0}.

headers([13,10|R0]) ->
    {[],R0};
headers(R0) ->
    {HeaderString, R1} = header(R0),
    {Rest, R2} = headers(R1),
    {[parse_header(HeaderString)|Rest], R2}.

parse_header(HeaderString) ->
    [Key, Value] = string:split(HeaderString, ":"),
    {string:trim(Key), string:trim(Value)}.

header([13,10|R0]) ->
    {[], R0};
header([C|R0]) ->
    {Rest, R1} = header(R0),
    {[C|Rest], R1}.

message_body(R) ->
    {R, []}.

ok(Body) ->
    "HTTP/1.1 200 OK\r\n" ++ "\r\n" ++ Body.

bad_request(Reason) ->
    Body = io_lib:format(
        "{\"error\": \"Bad request\", \"message\": \"~s\"}",
        [Reason]
    ),
    BodyBin = iolist_to_binary(Body),
    ContentLength = byte_size(BodyBin),
    Response = io_lib:format(
        "HTTP/1.1 400 Bad Request\r\n"
        "Content-Type: application/json\r\n"
        "Content-Length: ~w\r\n\r\n"
        "~s",
        [ContentLength, BodyBin]
    ),
    iolist_to_binary(Response).

get(URI) ->
    "GET " ++ URI ++ " HTTP/1.1\r\n" ++ "\r\n".