-module(chama_audit_handler).

-export([init/2]).

%% GET /api/audit-log
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = handle(Method, Req0),
    {ok, Req1, State}.

handle(<<"GET">>, Req) ->
    {ok, Log} = chama_store:list_audit_log(),
    chama_http:reply_ok(Log, Req);

handle(_, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
