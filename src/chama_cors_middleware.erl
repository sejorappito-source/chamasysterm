-module(chama_cors_middleware).
-behaviour(cowboy_middleware).

-export([execute/2]).

%% Allows requests from any origin, including the Claude artifact
%% preview (a different origin from wherever this backend is hosted).
%% If you later want to lock this down to just your production
%% frontend's origin, replace the "*" below with that exact origin.
execute(Req0, Env) ->
    Req1 = cowboy_req:set_resp_header(<<"access-control-allow-origin">>, <<"*">>, Req0),
    Req2 = cowboy_req:set_resp_header(<<"access-control-allow-methods">>, <<"GET, POST, PUT, DELETE, OPTIONS">>, Req1),
    Req3 = cowboy_req:set_resp_header(<<"access-control-allow-headers">>, <<"content-type, x-account-code">>, Req2),
    Req4 = cowboy_req:set_resp_header(<<"access-control-max-age">>, <<"86400">>, Req3),
    case cowboy_req:method(Req4) of
        <<"OPTIONS">> ->
            Req5 = cowboy_req:reply(204, Req4),
            {stop, Req5};
        _ ->
            {ok, Req4, Env}
    end.
