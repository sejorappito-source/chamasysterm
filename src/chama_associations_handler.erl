-module(chama_associations_handler).

-export([init/2]).

%% GET /api/associations              -> [{accountCode, name, location}] for the sign-in browse list
%% GET /api/associations/:account_code -> {accountCode, name, regions:[{code,name}]}
%%   Used by the frontend's "open this account" step, before the tenant
%%   header applies (no secrets returned - regions carry no passwords).
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    AccountCode = cowboy_req:binding(account_code, Req0),
    Req1 = handle(Method, AccountCode, Req0),
    {ok, Req1, State}.

handle(<<"GET">>, undefined, Req) ->
    {ok, Associations} = chama_store:list_associations(),
    chama_http:reply_ok(Associations, Req);

handle(<<"GET">>, AccountCode, Req) ->
    case chama_store:get_association_public(AccountCode) of
        {ok, Assoc} -> chama_http:reply_ok(Assoc, Req);
        {error, not_found} -> chama_http:reply_not_found(Req)
    end;

handle(_, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
