-module(chama_schedule_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% GET    /api/schedule                     -> list collection dates
%% POST   /api/schedule                      -> add one: {date, label, expectedAmount}
%% PUT    /api/schedule/:schedule_id         -> edit one
%% DELETE /api/schedule/:schedule_id         -> remove one
%% POST   /api/schedule/generate-year        -> generate a year's worth from a recurring rule:
%%                                              {year, weekday, nth, expectedAmount, label}
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    ScheduleId = cowboy_req:binding(schedule_id, Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, Path, ScheduleId, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"POST">>, <<"/api/schedule/generate-year">>, _Id, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:generate_year_schedule(AccountCode, Params) of
                {ok, Created} -> chama_http:reply_created(Created, Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(<<"GET">>, _Path, undefined, AccountCode, Req) ->
    {ok, Schedule} = chama_store:list_schedule(AccountCode),
    chama_http:reply_ok(Schedule, Req);

handle(<<"POST">>, _Path, undefined, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:add_schedule_date(AccountCode, Params) of
                {ok, Entry} -> chama_http:reply_created(Entry, Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(<<"PUT">>, _Path, ScheduleId, AccountCode, Req0) when ScheduleId =/= undefined ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:update_schedule_date(AccountCode, ScheduleId, Params) of
                {ok, Entry} -> chama_http:reply_ok(Entry, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1)
            end
    end;

handle(<<"DELETE">>, _Path, ScheduleId, AccountCode, Req) when ScheduleId =/= undefined ->
    case chama_store:delete_schedule_date(AccountCode, ScheduleId) of
        ok -> chama_http:reply_ok(#{<<"deleted">> => true}, Req);
        {error, not_found} -> chama_http:reply_not_found(Req)
    end;

handle(_, _, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
