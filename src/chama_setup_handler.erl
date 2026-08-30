-module(chama_setup_handler).

-export([init/2]).

%% GET  /api/setup  -> whether the association has completed onboarding
%% POST /api/setup  -> { name, phone, location, chairPassword, regions: [{code,name}] }
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    Req1 = handle(Method, Req0),
    {ok, Req1, State}.

handle(<<"GET">>, Req) ->
    {ok, Status} = chama_store:setup_status(),
    chama_http:reply_ok(Status, Req);

handle(<<"POST">>, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:onboard(Params) of
                {ok, Result} -> chama_http:reply_created(Result, Req1);
                {error, already_setup} -> chama_http:reply_error(409, <<"Association is already set up">>, Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(_, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
