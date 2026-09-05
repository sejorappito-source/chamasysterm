-module(chama_router).

-export([routes/0]).

%% All API routes live under /api. Every handler is a plain cowboy
%% handler (init/2) that inspects cowboy_req:method/1 itself, so the
%% same path can serve GET (list/read) and POST (create/act).
%%
%% Everything else falls through to the built frontend (the Vite build
%% output copied into priv/static at Docker build time), so the whole
%% app is served from this one cowboy listener - no separate frontend
%% host, no CORS to configure.
routes() ->
    [
        {'_', [
            {"/api/setup",                        chama_setup_handler,    []},
            {"/api/associations",                 chama_associations_handler, []},
            {"/api/associations/:account_code",   chama_associations_handler, []},
            {"/api/auth/signin",                  chama_auth_handler,     []},
            {"/api/regions",                      chama_regions_handler,  []},
            {"/api/regions/:region_code",         chama_regions_handler,  []},
            {"/api/members",                      chama_members_handler,  []},
            {"/api/members/:member_id",           chama_members_handler,  []},
            {"/api/payments",                     chama_payments_handler, []},
            {"/api/transactions",                 chama_transactions_handler, []},
            {"/api/funerals",                     chama_funerals_handler, []},
            {"/api/funerals/:funeral_id",         chama_funerals_handler, []},
            {"/api/funerals/:funeral_id/expenses", chama_funerals_handler, []},
            {"/api/audit-log",                    chama_audit_handler,    []},
            {"/api/projects",                     chama_projects_handler, []},
            {"/api/projects/:project_id/status",  chama_projects_handler, []},
            {"/api/schedule",                     chama_schedule_handler, []},
            {"/api/schedule/generate-year",       chama_schedule_handler, []},
            {"/api/schedule/:schedule_id",        chama_schedule_handler, []},
            {"/api/reports/dashboard",             chama_reports_handler, []},
            {"/api/reports/region/:region_code",   chama_reports_handler, []},
            {"/api/reports/financial",             chama_reports_handler, []},
            {"/api/reports/funerals",              chama_reports_handler, []},

            %% Static frontend (Vite build output, see priv/static/).
            {"/", cowboy_static, {priv_file, chama, "static/index.html"}},
            {"/assets/[...]", cowboy_static, {priv_dir, chama, "static/assets"}},
            {"/favicon.ico", cowboy_static, {priv_file, chama, "static/favicon.ico"}},
            %% Any other unmatched path (no client-side router is used by
            %% this app, but this keeps a hard refresh or bookmark safe)
            %% falls back to index.html.
            {"/[...]", cowboy_static, {priv_file, chama, "static/index.html"}}
        ]}
    ].

