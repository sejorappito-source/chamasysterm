-module(chama_funerals_handler).

-export([init/2]).

%% GET  /api/funerals?region=RC          -> list funeral cases
%% POST /api/funerals                     -> record a death, opens a case
%% GET  /api/funerals/:funeral_id         -> fetch one case
%% POST /api/funerals/:funeral_id/expenses -> log an expense against a case
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Path = cowboy_req:path(Req0),
    FuneralId = cowboy_req:binding(funeral_id, Req0),
    IsExpenses = is_expenses_path(Path),
    Req1 = handle(Method, FuneralId, IsExpenses, Req0),
    {ok, Req1, State}.

is_expenses_path(Path) ->
    Size = byte_size(Path),
    Suffix = <<"/expenses">>,
    SLen = byte_size(Suffix),
    Size >= SLen andalso binary:part(Path, Size - SLen, SLen) =:= Suffix.

handle(<<"GET">>, undefined, false, Req) ->
    QsMap = cowboy_req:parse_qs(Req),
    Filters = #{region => proplists:get_value(<<"region">>, QsMap)},
    {ok, Funerals} = chama_store:list_funerals(Filters),
    chama_http:reply_ok(Funerals, Req);

handle(<<"GET">>, FuneralId, false, Req) when FuneralId =/= undefined ->
    case chama_store:get_funeral(FuneralId) of
        {ok, Funeral} -> chama_http:reply_ok(Funeral, Req);
        {error, not_found} -> chama_http:reply_not_found(Req)
    end;

handle(<<"POST">>, undefined, false, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:record_death(Params) of
                {ok, Funeral} -> chama_http:reply_created(Funeral, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(<<"POST">>, FuneralId, true, Req0) when FuneralId =/= undefined ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Expense, Req1} ->
            case chama_store:add_funeral_expense(FuneralId, Expense) of
                {ok, Funeral} -> chama_http:reply_created(Funeral, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(_, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
