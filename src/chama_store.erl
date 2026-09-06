%% -*- coding: utf-8 -*-
-module(chama_store).
-behaviour(gen_server).

-include("chama.hrl").
-include_lib("epgsql/include/epgsql.hrl").

%% Public API
-export([
    start_link/0,
    list_associations/0,
    onboard/1,
    signin/1,
    list_regions/1,
    add_region/2,
    update_region/3,
    delete_region/2,
    list_members/2,
    get_member/2,
    add_member/2,
    list_transactions/2,
    add_payment/2,
    list_funerals/2,
    get_funeral/2,
    record_death/2,
    add_funeral_expense/3,
    list_audit_log/1,
    dashboard_report/2,
    financial_report/1,
    funeral_report/1,
    reset_account/1,
    get_association_public/1,
    list_projects/1,
    add_project/2,
    update_project_status/3,
    list_schedule/1,
    add_schedule_date/2,
    update_schedule_date/3,
    delete_schedule_date/2,
    generate_year_schedule/2
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {conn}).

%% ============================================================
%% Public API
%% Every call except list_associations/onboard/signin takes an
%% AccountCode (binary) as its first argument, identifying the tenant.
%% Handlers pull this from the X-Account-Code request header.
%% ============================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

list_associations() ->
    gen_server:call(?MODULE, list_associations).

%% Params :: #{name, phone, location, regions => [#{code, name}], chairPassword}
onboard(Params) ->
    gen_server:call(?MODULE, {onboard, Params}).

%% Params :: #{accountCode, role => <<"Chairperson">> | <<"Secretary">>, regionCode, secret}
signin(Params) ->
    gen_server:call(?MODULE, {signin, Params}).

list_regions(AccountCode) ->
    gen_server:call(?MODULE, {list_regions, AccountCode}).

add_region(AccountCode, Params) ->
    gen_server:call(?MODULE, {add_region, AccountCode, Params}).

update_region(AccountCode, Code, Params) ->
    gen_server:call(?MODULE, {update_region, AccountCode, Code, Params}).

delete_region(AccountCode, Code) ->
    gen_server:call(?MODULE, {delete_region, AccountCode, Code}).

list_members(AccountCode, Filters) ->
    gen_server:call(?MODULE, {list_members, AccountCode, Filters}).

get_member(AccountCode, Id) ->
    gen_server:call(?MODULE, {get_member, AccountCode, Id}).

add_member(AccountCode, Form) ->
    gen_server:call(?MODULE, {add_member, AccountCode, Form}).

list_transactions(AccountCode, Filters) ->
    gen_server:call(?MODULE, {list_transactions, AccountCode, Filters}).

add_payment(AccountCode, Params) ->
    gen_server:call(?MODULE, {add_payment, AccountCode, Params}).

list_funerals(AccountCode, Filters) ->
    gen_server:call(?MODULE, {list_funerals, AccountCode, Filters}).

get_funeral(AccountCode, Id) ->
    gen_server:call(?MODULE, {get_funeral, AccountCode, Id}).

record_death(AccountCode, Params) ->
    gen_server:call(?MODULE, {record_death, AccountCode, Params}).

add_funeral_expense(AccountCode, FuneralId, Expense) ->
    gen_server:call(?MODULE, {add_funeral_expense, AccountCode, FuneralId, Expense}).

list_audit_log(AccountCode) ->
    gen_server:call(?MODULE, {list_audit_log, AccountCode}).

dashboard_report(AccountCode, RegionCode) ->
    gen_server:call(?MODULE, {dashboard_report, AccountCode, RegionCode}).

financial_report(AccountCode) ->
    gen_server:call(?MODULE, {financial_report, AccountCode}).

funeral_report(AccountCode) ->
    gen_server:call(?MODULE, {funeral_report, AccountCode}).

%% Dev helper - wipes only this tenant's data (cascades via FKs).
reset_account(AccountCode) ->
    gen_server:call(?MODULE, {reset_account, AccountCode}).

%% Public lookup used by the sign-in "find my association" step, before
%% the caller has an authenticated session. Returns name + regions
%% (code/name only, no passwords) - no secrets exposed.
get_association_public(AccountCode) ->
    gen_server:call(?MODULE, {get_association_public, AccountCode}).

list_projects(AccountCode) ->
    gen_server:call(?MODULE, {list_projects, AccountCode}).

add_project(AccountCode, Params) ->
    gen_server:call(?MODULE, {add_project, AccountCode, Params}).

update_project_status(AccountCode, ProjectId, Status) ->
    gen_server:call(?MODULE, {update_project_status, AccountCode, ProjectId, Status}).

list_schedule(AccountCode) ->
    gen_server:call(?MODULE, {list_schedule, AccountCode}).

add_schedule_date(AccountCode, Params) ->
    gen_server:call(?MODULE, {add_schedule_date, AccountCode, Params}).

update_schedule_date(AccountCode, Id, Params) ->
    gen_server:call(?MODULE, {update_schedule_date, AccountCode, Id, Params}).

delete_schedule_date(AccountCode, Id) ->
    gen_server:call(?MODULE, {delete_schedule_date, AccountCode, Id}).

generate_year_schedule(AccountCode, Params) ->
    gen_server:call(?MODULE, {generate_year_schedule, AccountCode, Params}).

%% ============================================================
%% gen_server callbacks
%% ============================================================

init([]) ->
    case chama_db:connect() of
        {ok, Conn} ->
            {ok, #state{conn = Conn}};
        {error, Reason} ->
            error_logger:error_msg("chama_store: DB connect failed: ~p~n", [Reason]),
            {ok, #state{conn = undefined}}
    end.

handle_call(Msg, From, State0) ->
    case chama_db:ensure_connected(State0#state.conn) of
        {ok, Conn} ->
            State1 = State0#state{conn = Conn},
            try dispatch(Msg, Conn, State1) of
                {Reply, State2} -> {reply, Reply, State2}
            catch
                Class:Reason:Stack ->
                    error_logger:error_msg("chama_store error on ~p: ~p:~p~n~p~n", [Msg, Class, Reason, Stack]),
                    {reply, {error, {internal_error, iolist_to_binary(io_lib:format("~p", [Reason]))}}, State1}
            end;
        {error, Reason} ->
            error_logger:error_msg("chama_store: DB unavailable: ~p~n", [Reason]),
            {reply, {error, database_unavailable}, State0#state{conn = undefined}}
    end.

handle_cast(_Msg, State) -> {noreply, State}.
handle_info(_Info, State) -> {noreply, State}.
terminate(_Reason, _State) -> ok.
code_change(_OldVsn, State, _Extra) -> {ok, State}.

%% ============================================================
%% Dispatch: {Reply, NewState}
%% ============================================================

dispatch(list_associations, Conn, State) ->
    {ok, _, Rows} = epgsql:squery(Conn, "SELECT account_code, name, location FROM associations ORDER BY name"),
    List = [#{<<"accountCode">> => Code, <<"name">> => Name, <<"location">> => Loc} || {Code, Name, Loc} <- Rows],
    {{ok, List}, State};

dispatch({onboard, Params}, Conn, State) ->
    Name = maps:get(<<"name">>, Params, <<"">>),
    Phone = maps:get(<<"phone">>, Params, <<"">>),
    Location = maps:get(<<"location">>, Params, <<"">>),
    ChairPassword = maps:get(<<"chairPassword">>, Params, <<"">>),
    RegionMaps = maps:get(<<"regions">>, Params, []),
    case {Name, ChairPassword, RegionMaps} of
        {<<"">>, _, _} ->
            {{error, {bad_request, <<"Association name is required">>}}, State};
        {_, <<"">>, _} ->
            {{error, {bad_request, <<"Chairperson password is required">>}}, State};
        {_, _, []} ->
            {{error, {bad_request, <<"At least one region is required">>}}, State};
        _ ->
            case lists:any(fun(R) -> maps:get(<<"password">>, R, <<"">>) =:= <<"">> end, RegionMaps) of
                true ->
                    {{error, {bad_request, <<"Every region needs a secretary password">>}}, State};
                false ->
                    Hash = chama_auth:hash_password(ChairPassword),
                    AccountCode = create_association_with_unique_code(Conn, Name, Phone, Location, Hash, 5),
                    case AccountCode of
                        {error, _} = Err -> {Err, State};
                        _ ->
                            lists:foreach(fun(R) ->
                                Code = upper_bin(maps:get(<<"code">>, R, <<"">>)),
                                RName = maps:get(<<"name">>, R, <<"">>),
                                RPasswordHash = chama_auth:hash_password(maps:get(<<"password">>, R, <<"">>)),
                                {ok, 1} = epgsql:equery(Conn,
                                    "INSERT INTO regions (account_code, code, name, password_hash) VALUES ($1, $2, $3, $4)",
                                    [AccountCode, Code, RName, RPasswordHash])
                            end, RegionMaps),
                            Assoc = #association{account_code = AccountCode, name = Name, phone = Phone, location = Location, chair_password_hash = Hash},
                            Regions = [#region{code = upper_bin(maps:get(<<"code">>, R, <<"">>)), name = maps:get(<<"name">>, R, <<"">>)} || R <- RegionMaps],
                            Reply = #{
                                <<"accountCode">> => AccountCode,
                                <<"association">> => chama_view:association_to_map(Assoc),
                                <<"regions">> => [chama_view:region_to_map(R) || R <- Regions]
                            },
                            {{ok, Reply}, State}
                    end
            end
    end;

dispatch({signin, Params}, Conn, State) ->
    AccountCode = maps:get(<<"accountCode">>, Params, <<"">>),
    Role = maps:get(<<"role">>, Params, <<"">>),
    RegionCode = maps:get(<<"regionCode">>, Params, <<"">>),
    Secret = maps:get(<<"secret">>, Params, <<"">>),
    case get_association(Conn, AccountCode) of
        undefined ->
            {{error, {bad_request, <<"Unknown account code">>}}, State};
        Assoc ->
            Reply = case Role of
                <<"Chairperson">> ->
                    case chama_auth:verify_password(Secret, Assoc#association.chair_password_hash) of
                        true -> {ok, #{<<"role">> => <<"Chairperson">>, <<"accountCode">> => AccountCode, <<"regionCode">> => <<"All">>}};
                        false -> {error, {unauthorized, <<"Incorrect chairperson password">>}}
                    end;
                <<"Secretary">> ->
                    case find_region_row(Conn, AccountCode, RegionCode) of
                        undefined ->
                            {error, {bad_request, <<"Unknown region">>}};
                        #region{code = Code, password_hash = Hash} ->
                            case chama_auth:verify_password(Secret, Hash) of
                                true -> {ok, #{<<"role">> => <<"Secretary">>, <<"accountCode">> => AccountCode, <<"regionCode">> => Code}};
                                false -> {error, {unauthorized, <<"Incorrect password for that region">>}}
                            end
                    end;
                _ ->
                    {error, {bad_request, <<"role must be Chairperson or Secretary">>}}
            end,
            {Reply, State}
    end;

dispatch({list_regions, AccountCode}, Conn, State) ->
    Regions = list_region_rows(Conn, AccountCode),
    {{ok, [chama_view:region_to_map(R) || R <- Regions]}, State};

dispatch({add_region, AccountCode, Params}, Conn, State) ->
    Name = maps:get(<<"name">>, Params, <<"">>),
    Code = upper_bin(maps:get(<<"code">>, Params, <<"">>)),
    Password = maps:get(<<"password">>, Params, <<"">>),
    case {Name, Code, Password} of
        {<<"">>, _, _} -> {{error, {bad_request, <<"Region name is required">>}}, State};
        {_, <<"">>, _} -> {{error, {bad_request, <<"Region code is required">>}}, State};
        {_, _, <<"">>} -> {{error, {bad_request, <<"A secretary password is required">>}}, State};
        _ ->
            case find_region_row(Conn, AccountCode, Code) of
                undefined ->
                    Hash = chama_auth:hash_password(Password),
                    {ok, 1} = epgsql:equery(Conn,
                        "INSERT INTO regions (account_code, code, name, password_hash) VALUES ($1, $2, $3, $4)",
                        [AccountCode, Code, Name, Hash]),
                    write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Added region ">>, Name, <<" (">>, Code, <<")">>]), Name),
                    {{ok, chama_view:region_to_map(#region{code = Code, name = Name})}, State};
                _ ->
                    {{error, {conflict, <<"A region with that code already exists">>}}, State}
            end
    end;

dispatch({update_region, AccountCode, Code, Params}, Conn, State) ->
    case find_region_row(Conn, AccountCode, Code) of
        undefined ->
            {{error, not_found}, State};
        OldRegion ->
            NewName = maps:get(<<"name">>, Params, OldRegion#region.name),
            NewCode = case maps:get(<<"code">>, Params, undefined) of
                undefined -> Code;
                <<"">> -> Code;
                RawNewCode -> upper_bin(RawNewCode)
            end,
            case NewName of
                <<"">> -> {{error, {bad_request, <<"Region name is required">>}}, State};
                _ ->
                    Clash = NewCode =/= Code andalso find_region_row(Conn, AccountCode, NewCode) =/= undefined,
                    case Clash of
                        true -> {{error, {conflict, <<"A region with that code already exists">>}}, State};
                        false ->
                            case maps:get(<<"password">>, Params, <<"">>) of
                                <<"">> ->
                                    {ok, _} = epgsql:equery(Conn,
                                        "UPDATE regions SET code = $1, name = $2 WHERE account_code = $3 AND code = $4",
                                        [NewCode, NewName, AccountCode, Code]);
                                NewPassword ->
                                    NewHash = chama_auth:hash_password(NewPassword),
                                    {ok, _} = epgsql:equery(Conn,
                                        "UPDATE regions SET code = $1, name = $2, password_hash = $3 WHERE account_code = $4 AND code = $5",
                                        [NewCode, NewName, NewHash, AccountCode, Code])
                            end,
                            case NewCode =/= Code of
                                true ->
                                    {ok, _} = epgsql:equery(Conn, "UPDATE members SET region_code = $1 WHERE account_code = $2 AND region_code = $3", [NewCode, AccountCode, Code]),
                                    {ok, _} = epgsql:equery(Conn, "UPDATE transactions SET region_code = $1 WHERE account_code = $2 AND region_code = $3", [NewCode, AccountCode, Code]),
                                    {ok, _} = epgsql:equery(Conn, "UPDATE funerals SET region_code = $1 WHERE account_code = $2 AND region_code = $3", [NewCode, AccountCode, Code]);
                                false -> ok
                            end,
                            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Updated region ">>, Code, <<" -> ">>, NewName, <<" (">>, NewCode, <<")">>]), NewName),
                            {{ok, chama_view:region_to_map(#region{code = NewCode, name = NewName})}, State}
                    end
            end
    end;

dispatch({delete_region, AccountCode, Code}, Conn, State) ->
    case find_region_row(Conn, AccountCode, Code) of
        undefined -> {{error, not_found}, State};
        Region ->
            {ok, _, [{Count}]} = epgsql:equery(Conn, "SELECT count(*) FROM members WHERE account_code = $1 AND region_code = $2", [AccountCode, Code]),
            case Count > 0 of
                true -> {{error, {conflict, <<"Cannot delete a region that still has members. Move or remove its members first.">>}}, State};
                false ->
                    {ok, _} = epgsql:equery(Conn, "DELETE FROM regions WHERE account_code = $1 AND code = $2", [AccountCode, Code]),
                    write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Deleted region ">>, Region#region.name, <<" (">>, Code, <<")">>]), Region#region.name),
                    {ok, State}
            end
    end;

dispatch({list_members, AccountCode, Filters}, Conn, State) ->
    Region = maps:get(region, Filters, undefined),
    Query = maps:get(q, Filters, undefined),
    {Sql, Params} = build_member_query(AccountCode, Region, Query),
    {ok, _, Rows} = epgsql:equery(Conn, Sql, Params),
    Members = [row_to_member(R) || R <- Rows],
    {{ok, [chama_view:member_to_map(M) || M <- Members]}, State};

dispatch({get_member, AccountCode, Id}, Conn, State) ->
    case epgsql:equery(Conn, member_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, Id]) of
        {ok, _, [Row]} -> {{ok, chama_view:member_to_map(row_to_member(Row))}, State};
        {ok, _, []} -> {{error, not_found}, State}
    end;

dispatch({add_member, AccountCode, Form}, Conn, State) ->
    case validate_member_form(Form) of
        {error, Reason} -> {{error, {bad_request, Reason}}, State};
        ok ->
            %% Accepts a client-generated id so the offline queue can
            %% retry this call safely: if the phone already sent this
            %% exact insert once but never saw the response, retrying
            %% with the same id just no-ops instead of duplicating.
            Id = maps:get(<<"id">>, Form, chama_util:new_id(<<"m">>)),
            Region = maps:get(<<"region">>, Form),
            NationalId = maps:get(<<"nationalId">>, Form),
            FullName = maps:get(<<"fullName">>, Form),
            Phone = maps:get(<<"phone">>, Form, <<"">>),
            DateJoined = maps:get(<<"dateJoined">>, Form, chama_util:today()),
            JoiningFee = chama_util:to_number(maps:get(<<"joiningFee">>, Form, 0)),
            Monthly = chama_util:to_number(maps:get(<<"monthly">>, Form, 0)),
            {ok, InsertCount} = epgsql:equery(Conn,
                "INSERT INTO members (id, account_code, national_id, full_name, phone, region_code, date_joined, joining_fee, monthly, status, paid_this_month) "
                "VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,'active',false) ON CONFLICT (id) DO NOTHING",
                [Id, AccountCode, NationalId, FullName, Phone, Region, DateJoined, JoiningFee, Monthly]),
            case InsertCount of
                1 ->
                    RegionName = region_name(Conn, AccountCode, Region),
                    write_audit(Conn, AccountCode, <<"Secretary">>, iolist_to_binary([<<"Added member ID ">>, NationalId, <<" (">>, FullName, <<")">>]), RegionName);
                0 -> ok %% already recorded on a previous attempt - don't duplicate the audit entry
            end,
            case epgsql:equery(Conn, member_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, Id]) of
                {ok, _, [Row]} -> {{ok, chama_view:member_to_map(row_to_member(Row))}, State};
                {ok, _, []} -> {{error, {conflict, <<"That national ID is already registered under a different member">>}}, State}
            end
    end;

dispatch({list_transactions, AccountCode, Filters}, Conn, State) ->
    Region = maps:get(region, Filters, undefined),
    Type = maps:get(type, Filters, undefined),
    Method = maps:get(method, Filters, undefined),
    Query = maps:get(q, Filters, undefined),
    {Sql, Params} = build_transaction_query(AccountCode, Region, Type, Method, Query),
    {ok, _, Rows} = epgsql:equery(Conn, Sql, Params),
    Tx = [row_to_transaction(R) || R <- Rows],
    {{ok, [chama_view:transaction_to_map(T) || T <- Tx]}, State};

dispatch({add_payment, AccountCode, Params}, Conn, State) ->
    MemberId = maps:get(<<"memberId">>, Params, undefined),
    Amount = chama_util:to_number(maps:get(<<"amount">>, Params, 0)),
    Reference = maps:get(<<"reference">>, Params, <<"MANUAL">>),
    Method = maps:get(<<"method">>, Params, <<"Cash">>),
    TxId = maps:get(<<"id">>, Params, chama_util:new_id(<<"t">>)),
    case MemberId of
        undefined -> {{error, {bad_request, <<"memberId is required">>}}, State};
        _ ->
            case epgsql:equery(Conn, member_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, MemberId]) of
                {ok, _, []} -> {{error, not_found}, State};
                {ok, _, [Row]} ->
                    Member = row_to_member(Row),
                    case Amount =< 0 of
                        true -> {{error, {bad_request, <<"amount must be greater than zero">>}}, State};
                        false ->
                            Date = chama_util:today(),
                            {ok, InsertCount} = epgsql:equery(Conn,
                                "INSERT INTO transactions (id, account_code, date, member_id, member_name, region_code, type, amount, method, recorded_by, status, reference) "
                                "VALUES ($1,$2,$3,$4,$5,$6,'payment',$7,$8,'Secretary','Completed',$9) ON CONFLICT (id) DO NOTHING",
                                [TxId, AccountCode, Date, Member#member.national_id, Member#member.full_name, Member#member.region, Amount, Method, Reference]),
                            case InsertCount of
                                1 ->
                                    {ok, _} = epgsql:equery(Conn, "UPDATE members SET paid_this_month = true WHERE account_code = $1 AND id = $2", [AccountCode, MemberId]),
                                    RegionName = region_name(Conn, AccountCode, Member#member.region),
                                    write_audit(Conn, AccountCode, <<"Secretary">>, iolist_to_binary([<<"Recorded payment of KES ">>, amount_bin(Amount), <<" for ">>, Member#member.full_name]), RegionName);
                                0 -> ok %% this exact payment was already recorded on a previous attempt
                            end,
                            {ok, _, [TxRow]} = epgsql:equery(Conn,
                                "SELECT id, date, member_id, member_name, region_code, type, amount, method, recorded_by, status, reference FROM transactions WHERE account_code = $1 AND id = $2",
                                [AccountCode, TxId]),
                            {{ok, chama_view:transaction_to_map(row_to_transaction(TxRow))}, State}
                    end
            end
    end;

dispatch({list_funerals, AccountCode, Filters}, Conn, State) ->
    Region = maps:get(region, Filters, undefined),
    {Sql, Params} = build_funeral_query(AccountCode, Region),
    {ok, _, Rows} = epgsql:equery(Conn, Sql, Params),
    Funerals = [attach_expenses(Conn, row_to_funeral_base(R)) || R <- Rows],
    {{ok, [chama_view:funeral_to_map(F) || F <- Funerals]}, State};

dispatch({get_funeral, AccountCode, Id}, Conn, State) ->
    case epgsql:equery(Conn, funeral_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, Id]) of
        {ok, _, [Row]} -> {{ok, chama_view:funeral_to_map(attach_expenses(Conn, row_to_funeral_base(Row)))}, State};
        {ok, _, []} -> {{error, not_found}, State}
    end;

dispatch({record_death, AccountCode, Params}, Conn, State) ->
    MemberId = maps:get(<<"memberId">>, Params, undefined),
    case epgsql:equery(Conn, member_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, MemberId]) of
        {ok, _, []} -> {{error, not_found}, State};
        {ok, _, [Row]} ->
            Member = row_to_member(Row),
            FuneralId = maps:get(<<"id">>, Params, chama_util:new_id(<<"f">>)),
            Dod = maps:get(<<"dateOfDeath">>, Params, chama_util:today()),
            Allocated = chama_util:to_number(maps:get(<<"allocated">>, Params, 0)),
            Notes = maps:get(<<"notes">>, Params, <<"">>),
            {ok, InsertCount} = epgsql:equery(Conn,
                "INSERT INTO funerals (id, account_code, member_id, member_name, national_id, region_code, date_of_death, allocated, used, notes) "
                "VALUES ($1,$2,$3,$4,$5,$6,$7,$8,0,$9) ON CONFLICT (id) DO NOTHING",
                [FuneralId, AccountCode, Member#member.id, Member#member.full_name, Member#member.national_id, Member#member.region, Dod, Allocated, Notes]),
            {ok, _} = epgsql:equery(Conn, "UPDATE members SET status = 'deceased' WHERE account_code = $1 AND id = $2", [AccountCode, MemberId]),
            case InsertCount of
                1 ->
                    RegionName = region_name(Conn, AccountCode, Member#member.region),
                    write_audit(Conn, AccountCode, <<"Secretary">>, iolist_to_binary([<<"Recorded death of member ">>, Member#member.full_name]), RegionName);
                0 -> ok %% already recorded on a previous attempt
            end,
            {ok, _, [FRow]} = epgsql:equery(Conn, funeral_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, FuneralId]),
            {{ok, chama_view:funeral_to_map(attach_expenses(Conn, row_to_funeral_base(FRow)))}, State}
    end;

dispatch({add_funeral_expense, AccountCode, FuneralId, Expense}, Conn, State) ->
    case epgsql:equery(Conn, funeral_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, FuneralId]) of
        {ok, _, []} -> {{error, not_found}, State};
        {ok, _, [Row]} ->
            Funeral = row_to_funeral_base(Row),
            Amount = chama_util:to_number(maps:get(<<"amount">>, Expense, 0)),
            Description = maps:get(<<"description">>, Expense, <<"">>),
            case Amount =< 0 of
                true -> {{error, {bad_request, <<"amount must be greater than zero">>}}, State};
                false ->
                    ExpenseId = maps:get(<<"id">>, Expense, chama_util:new_id(<<"e">>)),
                    Date = chama_util:today(),
                    {ok, InsertCount} = epgsql:equery(Conn,
                        "INSERT INTO funeral_expenses (id, funeral_id, account_code, description, amount, date) VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT (id) DO NOTHING",
                        [ExpenseId, FuneralId, AccountCode, Description, Amount, Date]),
                    %% Gate every side effect on InsertCount so a retried
                    %% call (same client-generated ExpenseId) can never
                    %% double-count the balance or log a duplicate
                    %% transaction/audit entry.
                    case InsertCount of
                        1 ->
                            {ok, _} = epgsql:equery(Conn, "UPDATE funerals SET used = used + $1 WHERE account_code = $2 AND id = $3", [Amount, AccountCode, FuneralId]),
                            TxId = chama_util:new_id(<<"t">>),
                            {ok, 1} = epgsql:equery(Conn,
                                "INSERT INTO transactions (id, account_code, date, member_id, member_name, region_code, type, amount, method, recorded_by, status, reference) "
                                "VALUES ($1,$2,$3,$4,$5,$6,'expense',$7,'Cash','Secretary','Completed',$8)",
                                [TxId, AccountCode, Date, Funeral#funeral.national_id, Funeral#funeral.member_name, Funeral#funeral.region, Amount, upper_bin(Description)]),
                            RegionName = region_name(Conn, AccountCode, Funeral#funeral.region),
                            write_audit(Conn, AccountCode, <<"Secretary">>, iolist_to_binary([<<"Logged funeral expense — ">>, Description, <<", KES ">>, amount_bin(Amount)]), RegionName);
                        0 -> ok %% already applied on a previous attempt
                    end,
                    {ok, _, [FRow]} = epgsql:equery(Conn, funeral_select() ++ " WHERE account_code = $1 AND id = $2", [AccountCode, FuneralId]),
                    {{ok, chama_view:funeral_to_map(attach_expenses(Conn, row_to_funeral_base(FRow)))}, State}
            end
    end;

dispatch({list_audit_log, AccountCode}, Conn, State) ->
    {ok, _, Rows} = epgsql:equery(Conn,
        "SELECT user_role, action, date, time, region_name FROM audit_log WHERE account_code = $1 ORDER BY id DESC",
        [AccountCode]),
    {{ok, [chama_view:audit_to_map(row_to_audit(R)) || R <- Rows]}, State};

dispatch({dashboard_report, AccountCode, RegionCode}, Conn, State) ->
    Today = chama_util:today(),
    CurrentMonth = binary:part(Today, 0, 7),
    {ok, _, [{TotalMembers}]} = epgsql:equery(Conn,
        "SELECT count(*) FROM members WHERE account_code = $1 AND region_code = $2 AND status = 'active'",
        [AccountCode, RegionCode]),
    {ok, _, [{Collected0}]} = epgsql:equery(Conn,
        "SELECT COALESCE(sum(amount), 0) FROM transactions WHERE account_code = $1 AND region_code = $2 AND type = 'payment' AND date LIKE $3",
        [AccountCode, RegionCode, <<CurrentMonth/binary, "%">>]),
    {ok, _, [{UnpaidCount}]} = epgsql:equery(Conn,
        "SELECT count(*) FROM members WHERE account_code = $1 AND region_code = $2 AND status = 'active' AND paid_this_month = false",
        [AccountCode, RegionCode]),
    {ok, _, [{ActiveFunerals}]} = epgsql:equery(Conn,
        "SELECT count(*) FROM funerals WHERE account_code = $1 AND region_code = $2 AND used < allocated",
        [AccountCode, RegionCode]),
    Report = #{
        <<"regionCode">> => RegionCode,
        <<"totalMembers">> => TotalMembers,
        <<"collectedThisMonth">> => chama_util:to_number(Collected0),
        <<"unpaidMembers">> => UnpaidCount,
        <<"activeFunerals">> => ActiveFunerals
    },
    {{ok, Report}, State};

dispatch({financial_report, AccountCode}, Conn, State) ->
    {ok, _, [{Collected0}]} = epgsql:equery(Conn, "SELECT COALESCE(sum(amount),0) FROM transactions WHERE account_code = $1 AND type = 'payment'", [AccountCode]),
    {ok, _, [{Spent0}]} = epgsql:equery(Conn, "SELECT COALESCE(sum(amount),0) FROM transactions WHERE account_code = $1 AND type = 'expense'", [AccountCode]),
    Collected = chama_util:to_number(Collected0),
    Spent = chama_util:to_number(Spent0),
    Regions = list_region_rows(Conn, AccountCode),
    ByRegion = lists:map(fun(#region{code = Code, name = Name}) ->
        {ok, _, [{C0}]} = epgsql:equery(Conn, "SELECT COALESCE(sum(amount),0) FROM transactions WHERE account_code = $1 AND region_code = $2 AND type = 'payment'", [AccountCode, Code]),
        {ok, _, [{S0}]} = epgsql:equery(Conn, "SELECT COALESCE(sum(amount),0) FROM transactions WHERE account_code = $1 AND region_code = $2 AND type = 'expense'", [AccountCode, Code]),
        #{<<"code">> => Code, <<"name">> => Name, <<"collected">> => chama_util:to_number(C0), <<"expenses">> => chama_util:to_number(S0)}
    end, Regions),
    Report = #{<<"totalCollected">> => Collected, <<"totalExpenses">> => Spent, <<"netBalance">> => Collected - Spent, <<"byRegion">> => ByRegion},
    {{ok, Report}, State};

dispatch({funeral_report, AccountCode}, Conn, State) ->
    {ok, _, Rows} = epgsql:equery(Conn, funeral_select() ++ " WHERE account_code = $1", [AccountCode]),
    Funerals = [attach_expenses(Conn, row_to_funeral_base(R)) || R <- Rows],
    Allocated = lists:sum([F#funeral.allocated || F <- Funerals]),
    Used = lists:sum([F#funeral.used || F <- Funerals]),
    OpenCases = length([F || F <- Funerals, F#funeral.used < F#funeral.allocated]),
    Report = #{
        <<"totalCases">> => length(Funerals),
        <<"totalAllocated">> => Allocated,
        <<"totalUsed">> => Used,
        <<"openCases">> => OpenCases,
        <<"cases">> => [chama_view:funeral_to_map(F) || F <- Funerals]
    },
    {{ok, Report}, State};

dispatch({reset_account, AccountCode}, Conn, State) ->
    {ok, _} = epgsql:equery(Conn, "DELETE FROM associations WHERE account_code = $1", [AccountCode]),
    {ok, State};

dispatch({get_association_public, AccountCode}, Conn, State) ->
    case get_association(Conn, AccountCode) of
        undefined -> {{error, not_found}, State};
        Assoc ->
            Regions = list_region_rows(Conn, AccountCode),
            Reply = #{
                <<"accountCode">> => Assoc#association.account_code,
                <<"name">> => Assoc#association.name,
                <<"regions">> => [chama_view:region_to_map(R) || R <- Regions]
            },
            {{ok, Reply}, State}
    end;

dispatch({list_projects, AccountCode}, Conn, State) ->
    {ok, _, Rows} = epgsql:equery(Conn,
        "SELECT id, name, description, budget, spent, status, start_date, region_code FROM projects WHERE account_code = $1 ORDER BY start_date DESC",
        [AccountCode]),
    {{ok, [row_to_project_map(R) || R <- Rows]}, State};

dispatch({add_project, AccountCode, Params}, Conn, State) ->
    Name = maps:get(<<"name">>, Params, <<"">>),
    Description = maps:get(<<"description">>, Params, <<"">>),
    case {Name, Description} of
        {<<"">>, _} -> {{error, {bad_request, <<"Project name is required">>}}, State};
        {_, <<"">>} -> {{error, {bad_request, <<"A short description of what the project is for is required">>}}, State};
        _ ->
            Id = chama_util:new_id(<<"p">>),
            Budget = chama_util:to_number(maps:get(<<"budget">>, Params, 0)),
            Status = maps:get(<<"status">>, Params, <<"Planned">>),
            StartDate = maps:get(<<"startDate">>, Params, chama_util:today()),
            Region = maps:get(<<"region">>, Params, <<"">>),
            {ok, 1} = epgsql:equery(Conn,
                "INSERT INTO projects (id, account_code, name, description, budget, spent, status, start_date, region_code) VALUES ($1,$2,$3,$4,$5,0,$6,$7,$8)",
                [Id, AccountCode, Name, Description, Budget, Status, StartDate, Region]),
            RegionName = case Region of <<"">> -> <<"All regions">>; _ -> region_name(Conn, AccountCode, Region) end,
            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Started project \"">>, Name, <<"\"">>]), RegionName),
            Row = {Id, Name, Description, Budget, 0, Status, StartDate, Region},
            {{ok, row_to_project_map(Row)}, State}
    end;

dispatch({update_project_status, AccountCode, ProjectId, Status}, Conn, State) ->
    case epgsql:equery(Conn,
        "SELECT id, name, description, budget, spent, status, start_date, region_code FROM projects WHERE account_code = $1 AND id = $2",
        [AccountCode, ProjectId]) of
        {ok, _, []} -> {{error, not_found}, State};
        {ok, _, [{Id, Name, Description, Budget, Spent, _OldStatus, StartDate, Region}]} ->
            {ok, _} = epgsql:equery(Conn, "UPDATE projects SET status = $1 WHERE account_code = $2 AND id = $3", [Status, AccountCode, ProjectId]),
            RegionName = case Region of <<"">> -> <<"All regions">>; _ -> region_name(Conn, AccountCode, Region) end,
            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Marked project \"">>, Name, <<"\" as ">>, Status]), RegionName),
            {{ok, row_to_project_map({Id, Name, Description, Budget, Spent, Status, StartDate, Region})}, State}
    end;

dispatch({list_schedule, AccountCode}, Conn, State) ->
    {ok, _, Rows} = epgsql:equery(Conn,
        "SELECT id, date, label, expected_amount FROM schedule WHERE account_code = $1 ORDER BY date ASC",
        [AccountCode]),
    {{ok, [row_to_schedule_map(R) || R <- Rows]}, State};

dispatch({add_schedule_date, AccountCode, Params}, Conn, State) ->
    Date = maps:get(<<"date">>, Params, <<"">>),
    Amount = chama_util:to_number(maps:get(<<"expectedAmount">>, Params, 0)),
    case {Date, Amount > 0} of
        {<<"">>, _} -> {{error, {bad_request, <<"A collection date is required">>}}, State};
        {_, false} -> {{error, {bad_request, <<"Expected contribution amount is required">>}}, State};
        _ ->
            Id = chama_util:new_id(<<"s">>),
            Label = maps:get(<<"label">>, Params, <<"">>),
            {ok, 1} = epgsql:equery(Conn,
                "INSERT INTO schedule (id, account_code, date, label, expected_amount) VALUES ($1,$2,$3,$4,$5)",
                [Id, AccountCode, Date, Label, Amount]),
            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Added collection date ">>, Date, <<" (expected KES ">>, amount_bin(Amount), <<")">>]), <<"All regions">>),
            {{ok, row_to_schedule_map({Id, Date, Label, Amount})}, State}
    end;

dispatch({update_schedule_date, AccountCode, Id, Params}, Conn, State) ->
    case epgsql:equery(Conn, "SELECT id, date, label, expected_amount FROM schedule WHERE account_code = $1 AND id = $2", [AccountCode, Id]) of
        {ok, _, []} -> {{error, not_found}, State};
        {ok, _, [{_, OldDate, OldLabel, OldAmount}]} ->
            NewDate = maps:get(<<"date">>, Params, OldDate),
            NewLabel = maps:get(<<"label">>, Params, OldLabel),
            NewAmount = case maps:get(<<"expectedAmount">>, Params, undefined) of
                undefined -> OldAmount;
                V -> chama_util:to_number(V)
            end,
            {ok, _} = epgsql:equery(Conn,
                "UPDATE schedule SET date = $1, label = $2, expected_amount = $3 WHERE account_code = $4 AND id = $5",
                [NewDate, NewLabel, NewAmount, AccountCode, Id]),
            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Updated collection date ">>, NewDate]), <<"All regions">>),
            {{ok, row_to_schedule_map({Id, NewDate, NewLabel, NewAmount})}, State}
    end;

dispatch({delete_schedule_date, AccountCode, Id}, Conn, State) ->
    case epgsql:equery(Conn, "SELECT date FROM schedule WHERE account_code = $1 AND id = $2", [AccountCode, Id]) of
        {ok, _, []} -> {{error, not_found}, State};
        {ok, _, [{Date}]} ->
            {ok, _} = epgsql:equery(Conn, "DELETE FROM schedule WHERE account_code = $1 AND id = $2", [AccountCode, Id]),
            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Removed collection date ">>, Date]), <<"All regions">>),
            {ok, State}
    end;

dispatch({generate_year_schedule, AccountCode, Params}, Conn, State) ->
    Amount = chama_util:to_number(maps:get(<<"expectedAmount">>, Params, 0)),
    case Amount > 0 of
        false -> {{error, {bad_request, <<"Expected contribution amount is required">>}}, State};
        true ->
            Year = round(chama_util:to_number(maps:get(<<"year">>, Params, 0))),
            Weekday = round(chama_util:to_number(maps:get(<<"weekday">>, Params, 0))),
            Nth = round(chama_util:to_number(maps:get(<<"nth">>, Params, 1))),
            Label = maps:get(<<"label">>, Params, <<"">>),
            Created = [begin
                Id = chama_util:new_id(<<"s">>),
                Date = nth_weekday_of_month(Year, M, Weekday, Nth),
                {ok, 1} = epgsql:equery(Conn,
                    "INSERT INTO schedule (id, account_code, date, label, expected_amount) VALUES ($1,$2,$3,$4,$5)",
                    [Id, AccountCode, Date, Label, Amount]),
                row_to_schedule_map({Id, Date, Label, Amount})
            end || M <- lists:seq(0, 11)],
            write_audit(Conn, AccountCode, <<"Chairperson">>, iolist_to_binary([<<"Generated ">>, integer_to_binary(length(Created)), <<" collection dates for ">>, integer_to_binary(Year)]), <<"All regions">>),
            {{ok, Created}, State}
    end.

%% ============================================================
%% Internal helpers
%% ============================================================

create_association_with_unique_code(_Conn, _Name, _Phone, _Location, _Hash, 0) ->
    {error, {internal_error, <<"Could not generate a unique account code">>}};
create_association_with_unique_code(Conn, Name, Phone, Location, Hash, Retries) ->
    Code = chama_db:new_account_code(),
    case epgsql:equery(Conn,
        "INSERT INTO associations (account_code, name, phone, location, chair_password_hash) VALUES ($1,$2,$3,$4,$5)",
        [Code, Name, Phone, Location, Hash]) of
        {ok, 1} -> Code;
        {error, #error{codename = unique_violation}} ->
            create_association_with_unique_code(Conn, Name, Phone, Location, Hash, Retries - 1)
    end.

get_association(Conn, AccountCode) ->
    case epgsql:equery(Conn, "SELECT account_code, name, phone, location, chair_password_hash FROM associations WHERE account_code = $1", [AccountCode]) of
        {ok, _, [{Code, Name, Phone, Location, Hash}]} ->
            #association{account_code = Code, name = Name, phone = Phone, location = Location, chair_password_hash = Hash};
        {ok, _, []} ->
            undefined
    end.

list_region_rows(Conn, AccountCode) ->
    {ok, _, Rows} = epgsql:equery(Conn, "SELECT code, name, password_hash FROM regions WHERE account_code = $1 ORDER BY name", [AccountCode]),
    [#region{code = Code, name = Name, password_hash = Hash} || {Code, Name, Hash} <- Rows].

find_region_row(Conn, AccountCode, Code) ->
    case epgsql:equery(Conn, "SELECT code, name, password_hash FROM regions WHERE account_code = $1 AND code = $2", [AccountCode, Code]) of
        {ok, _, [{C, N, H}]} -> #region{code = C, name = N, password_hash = H};
        {ok, _, []} -> undefined
    end.

region_name(Conn, AccountCode, Code) ->
    case find_region_row(Conn, AccountCode, Code) of
        undefined -> Code;
        #region{name = Name} -> Name
    end.

write_audit(Conn, AccountCode, UserRole, Action, RegionName) ->
    {ok, 1} = epgsql:equery(Conn,
        "INSERT INTO audit_log (account_code, user_role, action, date, time, region_name) VALUES ($1,$2,$3,$4,$5,$6)",
        [AccountCode, UserRole, Action, chama_util:today(), chama_util:now_time(), RegionName]).

member_select() ->
    "SELECT id, national_id, full_name, phone, region_code, date_joined, joining_fee, monthly, status, paid_this_month FROM members".

funeral_select() ->
    "SELECT id, member_id, member_name, national_id, region_code, date_of_death, allocated, used, notes FROM funerals".

row_to_member({Id, NationalId, FullName, Phone, Region, DateJoined, JoiningFee, Monthly, Status, Paid}) ->
    #member{
        id = Id, national_id = NationalId, full_name = FullName, phone = Phone, region = Region,
        date_joined = DateJoined, joining_fee = chama_util:to_number(JoiningFee), monthly = chama_util:to_number(Monthly),
        status = status_to_atom(Status), paid_this_month = Paid
    }.

status_to_atom(<<"active">>) -> active;
status_to_atom(<<"deceased">>) -> deceased.

row_to_transaction({Id, Date, MemberId, MemberName, Region, Type, Amount, Method, RecordedBy, Status, Reference}) ->
    #transaction{
        id = Id, date = Date, member_id = MemberId, member_name = MemberName, region = Region,
        type = type_to_atom(Type), amount = chama_util:to_number(Amount), method = Method,
        recorded_by = RecordedBy, status = Status, reference = Reference
    }.

type_to_atom(<<"payment">>) -> payment;
type_to_atom(<<"expense">>) -> expense.

row_to_funeral_base({Id, MemberId, MemberName, NationalId, Region, Dod, Allocated, Used, Notes}) ->
    #funeral{
        id = Id, member_id = MemberId, member_name = MemberName, national_id = NationalId, region = Region,
        date_of_death = Dod, allocated = chama_util:to_number(Allocated), used = chama_util:to_number(Used),
        notes = Notes, expenses = []
    }.

row_to_audit({UserRole, Action, Date, Time, RegionName}) ->
    #audit_entry{user = UserRole, action = Action, date = Date, time = Time, region = RegionName}.

row_to_project_map({Id, Name, Description, Budget, Spent, Status, StartDate, Region}) ->
    B = chama_util:to_number(Budget),
    S = chama_util:to_number(Spent),
    #{
        <<"id">> => Id, <<"name">> => Name, <<"description">> => Description,
        <<"budget">> => B, <<"spent">> => S, <<"balance">> => B - S,
        <<"status">> => Status, <<"startDate">> => StartDate, <<"region">> => Region
    }.

row_to_schedule_map({Id, Date, Label, ExpectedAmount}) ->
    #{<<"id">> => Id, <<"date">> => Date, <<"label">> => Label, <<"expectedAmount">> => chama_util:to_number(ExpectedAmount)}.

%% Mirrors the frontend's nthWeekdayOfMonth: weekday 0=Sun..6=Sat (JS
%% convention, since callers pass Date.getDay()-style values from the
%% UI), nth 1..4, or -1 for "last occurrence in the month".
nth_weekday_of_month(Year, MonthIndex0, Weekday, -1) ->
    Month = MonthIndex0 + 1,
    LastDay = calendar:last_day_of_the_month(Year, Month),
    find_last_weekday(Year, Month, LastDay, Weekday);
nth_weekday_of_month(Year, MonthIndex0, Weekday, Nth) ->
    Month = MonthIndex0 + 1,
    find_nth_weekday(Year, Month, 1, Weekday, Nth, 0).

find_last_weekday(Year, Month, Day, Weekday) ->
    IsoTarget = case Weekday of 0 -> 7; W -> W end,
    case calendar:day_of_the_week(Year, Month, Day) of
        IsoTarget -> format_date(Year, Month, Day);
        _ -> find_last_weekday(Year, Month, Day - 1, Weekday)
    end.

find_nth_weekday(Year, Month, Day, Weekday, Nth, Count) ->
    IsoTarget = case Weekday of 0 -> 7; W -> W end,
    case calendar:day_of_the_week(Year, Month, Day) of
        IsoTarget ->
            Count1 = Count + 1,
            case Count1 of
                Nth -> format_date(Year, Month, Day);
                _ -> find_nth_weekday(Year, Month, Day + 1, Weekday, Nth, Count1)
            end;
        _ -> find_nth_weekday(Year, Month, Day + 1, Weekday, Nth, Count)
    end.

format_date(Y, M, D) ->
    iolist_to_binary(io_lib:format("~4..0B-~2..0B-~2..0B", [Y, M, D])).

attach_expenses(Conn, Funeral) ->
    {ok, _, Rows} = epgsql:equery(Conn,
        "SELECT id, description, amount, date FROM funeral_expenses WHERE funeral_id = $1 ORDER BY id",
        [Funeral#funeral.id]),
    Expenses = [#funeral_expense{id = Id, description = Desc, amount = chama_util:to_number(Amount), date = Date} || {Id, Desc, Amount, Date} <- Rows],
    Funeral#funeral{expenses = Expenses}.

build_member_query(AccountCode, Region, Query) ->
    Base = member_select() ++ " WHERE account_code = $1",
    {Sql1, Params1, N1} = case Region of
        undefined -> {Base, [AccountCode], 1};
        <<"All">> -> {Base, [AccountCode], 1};
        _ -> {Base ++ " AND region_code = $2", [AccountCode, Region], 2}
    end,
    {Sql2, Params2} = case Query of
        undefined -> {Sql1, Params1};
        <<"">> -> {Sql1, Params1};
        _ ->
            Needle = <<"%", Query/binary, "%">>,
            P1 = integer_to_list(N1 + 1),
            P2 = integer_to_list(N1 + 2),
            {Sql1 ++ " AND (full_name ILIKE $" ++ P1 ++ " OR national_id ILIKE $" ++ P2 ++ ")", Params1 ++ [Needle, Needle]}
    end,
    {Sql2 ++ " ORDER BY full_name", Params2}.

build_transaction_query(AccountCode, Region, Type, Method, Query) ->
    {Sql0, Params0, N0} = {"SELECT id, date, member_id, member_name, region_code, type, amount, method, recorded_by, status, reference FROM transactions WHERE account_code = $1", [AccountCode], 1},
    {Sql1, Params1, N1} = case Region of
        undefined -> {Sql0, Params0, N0};
        <<"All">> -> {Sql0, Params0, N0};
        _ -> {Sql0 ++ " AND region_code = $" ++ integer_to_list(N0 + 1), Params0 ++ [Region], N0 + 1}
    end,
    {Sql2, Params2, N2} = case Type of
        undefined -> {Sql1, Params1, N1};
        <<"All">> -> {Sql1, Params1, N1};
        <<"Payment">> -> {Sql1 ++ " AND type = 'payment'", Params1, N1};
        <<"Expense">> -> {Sql1 ++ " AND type = 'expense'", Params1, N1}
    end,
    {Sql3, Params3, N3} = case Method of
        undefined -> {Sql2, Params2, N2};
        <<"All">> -> {Sql2, Params2, N2};
        _ -> {Sql2 ++ " AND method = $" ++ integer_to_list(N2 + 1), Params2 ++ [Method], N2 + 1}
    end,
    {Sql4, Params4} = case Query of
        undefined -> {Sql3, Params3};
        <<"">> -> {Sql3, Params3};
        _ ->
            Needle = <<"%", Query/binary, "%">>,
            P1 = integer_to_list(N3 + 1),
            P2 = integer_to_list(N3 + 2),
            {Sql3 ++ " AND (member_name ILIKE $" ++ P1 ++ " OR reference ILIKE $" ++ P2 ++ ")", Params3 ++ [Needle, Needle]}
    end,
    {Sql4 ++ " ORDER BY date DESC, id DESC", Params4}.

build_funeral_query(AccountCode, Region) ->
    Base = funeral_select() ++ " WHERE account_code = $1",
    case Region of
        undefined -> {Base ++ " ORDER BY date_of_death DESC", [AccountCode]};
        <<"All">> -> {Base ++ " ORDER BY date_of_death DESC", [AccountCode]};
        _ -> {Base ++ " AND region_code = $2 ORDER BY date_of_death DESC", [AccountCode, Region]}
    end.

upper_bin(Bin) when is_binary(Bin) ->
    list_to_binary(string:uppercase(binary_to_list(Bin))).

validate_member_form(Form) ->
    Required = [<<"nationalId">>, <<"fullName">>, <<"region">>],
    Missing = [K || K <- Required, maps:get(K, Form, <<"">>) =:= <<"">>],
    case Missing of
        [] -> ok;
        _ -> {error, iolist_to_binary([<<"Missing required fields: ">>, lists:join(<<", ">>, Missing)])}
    end.

amount_bin(Amount) when is_integer(Amount) -> integer_to_binary(Amount);
amount_bin(Amount) when is_float(Amount) -> float_to_binary(Amount, [{decimals, 2}]).
