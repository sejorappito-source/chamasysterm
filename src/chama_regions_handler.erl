-module(chama_regions_handler).

-export([init/2]).

%% GET /api/regions
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = handle(Method, Req0),
    {ok, Req1, State}.

handle(<<"GET">>, Req) ->
    {ok, Regions} = chama_store:list_regions(),
    chama_http:reply_ok(Regions, Req);

handle(_, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
