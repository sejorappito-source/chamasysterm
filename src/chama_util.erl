-module(chama_util).

-export([
    new_id/1,
    today/0,
    now_time/0,
    to_bin/1,
    to_number/1
]).

%% Generates a short unique id with the given prefix, e.g. new_id(<<"m">>)
%% -> <<"m1717000000000-482913">>. Uses erlang:unique_integer/1 so ids are
%% guaranteed unique within the node without needing a shared counter.
new_id(Prefix) when is_binary(Prefix) ->
    Unique = erlang:unique_integer([positive, monotonic]),
    Millis = erlang:system_time(millisecond),
    iolist_to_binary([Prefix, integer_to_binary(Millis), <<"-">>, integer_to_binary(Unique)]).

%% Current date as an ISO-8601 date binary, e.g. <<"2026-08-30">>.
today() ->
    {{Y, M, D}, _} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).

%% Current time formatted as e.g. <<"14:05 UTC">>.
now_time() ->
    {_, {H, Mi, _}} = calendar:universal_time(),
    iolist_to_binary(io_lib:format("~2..0B:~2..0B UTC", [H, Mi])).

to_bin(V) when is_binary(V) -> V;
to_bin(V) when is_list(V) -> list_to_binary(V);
to_bin(V) when is_atom(V) -> atom_to_binary(V, utf8);
to_bin(V) when is_integer(V) -> integer_to_binary(V);
to_bin(V) when is_float(V) -> float_to_binary(V, [{decimals, 2}]).

to_number(V) when is_number(V) -> V;
to_number(V) when is_binary(V) ->
    case string:to_float(binary_to_list(V)) of
        {F, []} -> F;
        _ ->
            case string:to_integer(binary_to_list(V)) of
                {I, []} -> I;
                _ -> 0
            end
    end;
to_number(_) -> 0.
