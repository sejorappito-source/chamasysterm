-module(chama_regions_handler).

-export([init/2]).

%% All routes require the X-Account-Code header identifying the tenant.
%% GET    /api/regions               -> list regions
%% POST   /api/regions                -> add a region: {code, name}
%% PUT    /api/regions/:region_code   -> rename/edit a region: {code?, name?}
%% DELETE /api/regions/:region_code   -> delete a region (must have no members)
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    RegionCode = cowboy_req:binding(region_code, Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, RegionCode, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"GET">>, undefined, AccountCode, Req) ->
    {ok, Regions} = chama_store:list_regions(AccountCode),
    chama_http:reply_ok(Regions, Req);

handle(<<"POST">>, undefined, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Form, Req1} ->
            case chama_store:add_region(AccountCode, Form) of
                {ok, Region} -> chama_http:reply_created(Region, Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1);
                {error, {conflict, Msg}} -> chama_http:reply_error(409, Msg, Req1)
            end
    end;

handle(<<"PUT">>, RegionCode, AccountCode, Req0) when RegionCode =/= undefined ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Form, Req1} ->
            case chama_store:update_region(AccountCode, RegionCode, Form) of
                {ok, Region} -> chama_http:reply_ok(Region, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1);
                {error, {conflict, Msg}} -> chama_http:reply_error(409, Msg, Req1)
            end
    end;

handle(<<"DELETE">>, RegionCode, AccountCode, Req) when RegionCode =/= undefined ->
    case chama_store:delete_region(AccountCode, RegionCode) of
        ok -> chama_http:reply_ok(#{<<"deleted">> => true}, Req);
        {error, not_found} -> chama_http:reply_not_found(Req);
        {error, {conflict, Msg}} -> chama_http:reply_error(409, Msg, Req)
    end;

handle(_, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
