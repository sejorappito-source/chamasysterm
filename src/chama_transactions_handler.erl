-module(chama_transactions_handler).

-export([init/2]).

%% GET /api/transactions?region=RC&type=Payment|Expense&method=Cash|M-Pesa&q=search
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = handle(Method, Req0),
    {ok, Req1, State}.

handle(<<"GET">>, Req) ->
    QsMap = cowboy_req:parse_qs(Req),
    Filters = #{
        region => proplists:get_value(<<"region">>, QsMap),
        type => proplists:get_value(<<"type">>, QsMap),
        method => proplists:get_value(<<"method">>, QsMap),
        q => proplists:get_value(<<"q">>, QsMap)
    },
    {ok, Tx} = chama_store:list_transactions(Filters),
    chama_http:reply_ok(Tx, Req);

handle(_, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
