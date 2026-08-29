-module(bench_script).
-export([main/1]).

%execute with "escript bench_script.erl <FILENAME>"
%writes result of test to passed file, creates file if non-existent

main([Filename]) ->
    Result = test:bench("localhost", 8080),
    FormattedResult = integer_to_list(Result) ++ "\n",
    {ok, IODevice} = file:open(Filename, [append]),
    ok = file:write(IODevice, FormattedResult),
    ok = file:close(IODevice).