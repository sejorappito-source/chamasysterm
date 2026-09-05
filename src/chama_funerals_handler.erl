-module(chama_funerals_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% GET  /api/funerals?region=RC          -> list funeral cases
%% POST /api/funerals                     -> record a death, opens a case
%% GET  /api/funerals/:funeral_id         -> fetch one case
%% POST /api/funerals/:funeral_id/expenses -> log an expense against a case
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    FuneralId = cowboy_req:binding(funeral_id, Req0),
    IsExpenses = is_expenses_path(Path),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, FuneralId, IsExpenses, AccountCode, Req0)
    end,
    {ok, Req1, State}.

is_expenses_path(Path) ->
    Size = byte_size(Path),
    Suffix = <<"/expenses">>,
    SLen = byte_size(Suffix),
    Size >= SLen andalso binary:part(Path, Size - SLen, SLen) =:= Suffix.

handle(<<"GET">>, undefined, false, AccountCode, Req) ->
    QsMap = cowboy_req:parse_qs(Req),
    Filters = #{region => proplists:get_value(<<"region">>, QsMap)},
    {ok, Funerals} = chama_store:list_funerals(AccountCode, Filters),
    chama_http:reply_ok(Funerals, Req);

handle(<<"GET">>, FuneralId, false, AccountCode, Req) when FuneralId =/= undefined ->
    case chama_store:get_funeral(AccountCode, FuneralId) of
        {ok, Funeral} -> chama_http:reply_ok(Funeral, Req);
        {error, not_found} -> chama_http:reply_not_found(Req)
    end;

handle(<<"POST">>, undefined, false, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:record_death(AccountCode, Params) of
                {ok, Funeral} -> chama_http:reply_created(Funeral, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(<<"POST">>, FuneralId, true, AccountCode, Req0) when FuneralId =/= undefined ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Expense, Req1} ->
            case chama_store:add_funeral_expense(AccountCode, FuneralId, Expense) of
                {ok, Funeral} -> chama_http:reply_created(Funeral, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(_, _, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
