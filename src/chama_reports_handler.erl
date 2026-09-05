-module(chama_reports_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% GET /api/reports/dashboard?region=RC   -> secretary dashboard stats for a region
%% GET /api/reports/region/:region_code   -> same, region code from the path
%% GET /api/reports/financial              -> association-wide financial report
%% GET /api/reports/funerals               -> association-wide funeral fund report
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, Path, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"GET">>, <<"/api/reports/dashboard">>, AccountCode, Req) ->
    QsMap = cowboy_req:parse_qs(Req),
    Region = proplists:get_value(<<"region">>, QsMap, <<"All">>),
    {ok, Report} = chama_store:dashboard_report(AccountCode, Region),
    chama_http:reply_ok(Report, Req);

handle(<<"GET">>, <<"/api/reports/financial">>, AccountCode, Req) ->
    {ok, Report} = chama_store:financial_report(AccountCode),
    chama_http:reply_ok(Report, Req);

handle(<<"GET">>, <<"/api/reports/funerals">>, AccountCode, Req) ->
    {ok, Report} = chama_store:funeral_report(AccountCode),
    chama_http:reply_ok(Report, Req);

handle(<<"GET">>, _RegionPath, AccountCode, Req) ->
    RegionCode = cowboy_req:binding(region_code, Req),
    case RegionCode of
        undefined ->
            chama_http:reply_not_found(Req);
        _ ->
            {ok, Report} = chama_store:dashboard_report(AccountCode, RegionCode),
            chama_http:reply_ok(Report, Req)
    end;

handle(_, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
