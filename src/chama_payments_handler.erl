-module(chama_payments_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% POST /api/payments -> { memberId, amount, reference, method }
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"POST">>, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:add_payment(AccountCode, Params) of
                {ok, Tx} -> chama_http:reply_created(Tx, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(_, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
