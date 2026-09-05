-module(chama_members_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% GET  /api/members?region=RC&q=search  -> list members (optionally filtered)
%% POST /api/members                      -> add a member
%% GET  /api/members/:member_id           -> fetch a single member
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    MemberId = cowboy_req:binding(member_id, Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, MemberId, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"GET">>, undefined, AccountCode, Req) ->
    QsMap = cowboy_req:parse_qs(Req),
    Filters = #{
        region => proplists:get_value(<<"region">>, QsMap),
        q => proplists:get_value(<<"q">>, QsMap)
    },
    {ok, Members} = chama_store:list_members(AccountCode, Filters),
    chama_http:reply_ok(Members, Req);

handle(<<"GET">>, MemberId, AccountCode, Req) ->
    case chama_store:get_member(AccountCode, MemberId) of
        {ok, Member} -> chama_http:reply_ok(Member, Req);
        {error, not_found} -> chama_http:reply_not_found(Req)
    end;

handle(<<"POST">>, undefined, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Form, Req1} ->
            case chama_store:add_member(AccountCode, Form) of
                {ok, Member} -> chama_http:reply_created(Member, Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(_, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
