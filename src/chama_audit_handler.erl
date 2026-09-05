-module(chama_audit_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% GET /api/audit-log
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"GET">>, AccountCode, Req) ->
    {ok, Log} = chama_store:list_audit_log(AccountCode),
    chama_http:reply_ok(Log, Req);

handle(_, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
