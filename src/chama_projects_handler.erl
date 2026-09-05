-module(chama_projects_handler).

-export([init/2]).

%% Requires X-Account-Code header.
%% GET  /api/projects                    -> list projects
%% POST /api/projects                     -> start a project: {name, description, budget, status, startDate, region}
%% PUT  /api/projects/:project_id/status  -> update status: {status}
init(Req0, State) ->
    Method = cowboy_req:method(Req0),
    ProjectId = cowboy_req:binding(project_id, Req0),
    Req1 = case chama_http:account_code(Req0) of
        {error, missing_account_code} ->
            chama_http:reply_bad_request(<<"Missing X-Account-Code header">>, Req0);
        {ok, AccountCode} ->
            handle(Method, ProjectId, AccountCode, Req0)
    end,
    {ok, Req1, State}.

handle(<<"GET">>, undefined, AccountCode, Req) ->
    {ok, Projects} = chama_store:list_projects(AccountCode),
    chama_http:reply_ok(Projects, Req);

handle(<<"POST">>, undefined, AccountCode, Req0) ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            case chama_store:add_project(AccountCode, Params) of
                {ok, Project} -> chama_http:reply_created(Project, Req1);
                {error, {bad_request, Msg}} -> chama_http:reply_bad_request(Msg, Req1)
            end
    end;

handle(<<"PUT">>, ProjectId, AccountCode, Req0) when ProjectId =/= undefined ->
    case chama_http:read_json(Req0) of
        {error, invalid_json, Req1} ->
            chama_http:reply_bad_request(<<"Invalid JSON body">>, Req1);
        {ok, Params, Req1} ->
            Status = maps:get(<<"status">>, Params, <<"">>),
            case chama_store:update_project_status(AccountCode, ProjectId, Status) of
                {ok, Project} -> chama_http:reply_ok(Project, Req1);
                {error, not_found} -> chama_http:reply_not_found(Req1)
            end
    end;

handle(_, _, _, Req) ->
    chama_http:reply_error(405, <<"Method not allowed">>, Req).
