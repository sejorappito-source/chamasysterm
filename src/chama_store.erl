%% -*- coding: utf-8 -*-
-module(chama_store).
-behaviour(gen_server).

-include("chama.hrl").

%% Public API
-export([
    start_link/0,
    setup_status/0,
    onboard/1,
    signin/1,
    list_regions/0,
    list_members/1,
    get_member/1,
    add_member/1,
    list_transactions/1,
    add_payment/1,
    list_funerals/1,
    get_funeral/1,
    record_death/1,
    add_funeral_expense/2,
    list_audit_log/0,
    dashboard_report/1,
    financial_report/0,
    funeral_report/0,
    reset/0
]).

%% gen_server callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {
    setup = false        :: boolean(),
    association          :: #association{} | undefined,
    regions = []          :: [#region{}],
    members = #{}         :: #{binary() => #member{}},
    transactions = []     :: [#transaction{}],  %% newest first
    funerals = #{}        :: #{binary() => #funeral{}},
    audit_log = []        :: [#audit_entry{}]   %% newest first
}).

%% ============================================================
%% Public API
%% ============================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

setup_status() ->
    gen_server:call(?MODULE, setup_status).

%% Params :: #{name, phone, location, regions => [#{code, name}], chair_password}
onboard(Params) ->
    gen_server:call(?MODULE, {onboard, Params}).

%% Params :: #{role => <<"Chairperson">> | <<"Secretary">>, region_code, secret}
signin(Params) ->
    gen_server:call(?MODULE, {signin, Params}).

list_regions() ->
    gen_server:call(?MODULE, list_regions).

%% Filters :: #{region => binary() | undefined}
list_members(Filters) ->
    gen_server:call(?MODULE, {list_members, Filters}).

get_member(Id) ->
    gen_server:call(?MODULE, {get_member, Id}).

%% Form :: #{nationalId, fullName, phone, region, dateJoined, joiningFee, monthly}
add_member(Form) ->
    gen_server:call(?MODULE, {add_member, Form}).

%% Filters :: #{region, type, method, q => binary() | undefined}
list_transactions(Filters) ->
    gen_server:call(?MODULE, {list_transactions, Filters}).

%% Params :: #{member_id, amount, reference}  (member_id = internal member id)
add_payment(Params) ->
    gen_server:call(?MODULE, {add_payment, Params}).

list_funerals(Filters) ->
    gen_server:call(?MODULE, {list_funerals, Filters}).

get_funeral(Id) ->
    gen_server:call(?MODULE, {get_funeral, Id}).

%% Params :: #{member_id, date_of_death, allocated, notes}
record_death(Params) ->
    gen_server:call(?MODULE, {record_death, Params}).

%% Expense :: #{description, amount}
add_funeral_expense(FuneralId, Expense) ->
    gen_server:call(?MODULE, {add_funeral_expense, FuneralId, Expense}).

list_audit_log() ->
    gen_server:call(?MODULE, list_audit_log).

dashboard_report(RegionCode) ->
    gen_server:call(?MODULE, {dashboard_report, RegionCode}).

financial_report() ->
    gen_server:call(?MODULE, financial_report).

funeral_report() ->
    gen_server:call(?MODULE, funeral_report).

%% Test/dev helper - wipes all state back to "not set up".
reset() ->
    gen_server:call(?MODULE, reset).

%% ============================================================
%% gen_server callbacks
%% ============================================================

init([]) ->
    {ok, #state{}}.

handle_call(setup_status, _From, State) ->
    Reply = case State#state.setup of
        true -> #{
            <<"setup">> => true,
            <<"association">> => chama_view:association_to_map(State#state.association),
            <<"regions">> => [chama_view:region_to_map(R) || R <- State#state.regions]
        };
        false -> #{<<"setup">> => false}
    end,
    {reply, {ok, Reply}, State};

handle_call({onboard, _Params}, _From, State = #state{setup = true}) ->
    {reply, {error, already_setup}, State};

handle_call({onboard, Params}, _From, State) ->
    Name = maps:get(<<"name">>, Params, <<"">>),
    Phone = maps:get(<<"phone">>, Params, <<"">>),
    Location = maps:get(<<"location">>, Params, <<"">>),
    ChairPassword = maps:get(<<"chairPassword">>, Params, <<"">>),
    RegionMaps = maps:get(<<"regions">>, Params, []),
    case {Name, ChairPassword, RegionMaps} of
        {<<"">>, _, _} ->
            {reply, {error, {bad_request, <<"Association name is required">>}}, State};
        {_, <<"">>, _} ->
            {reply, {error, {bad_request, <<"Chairperson password is required">>}}, State};
        {_, _, []} ->
            {reply, {error, {bad_request, <<"At least one region is required">>}}, State};
        _ ->
            Regions = [#region{
                code = maps:get(<<"code">>, R, <<"">>),
                name = maps:get(<<"name">>, R, <<"">>)
            } || R <- RegionMaps],
            Assoc = #association{
                name = Name,
                phone = Phone,
                location = Location,
                chair_password_hash = chama_auth:hash_password(ChairPassword)
            },
            NewState = State#state{setup = true, association = Assoc, regions = Regions},
            Reply = #{
                <<"association">> => chama_view:association_to_map(Assoc),
                <<"regions">> => [chama_view:region_to_map(R) || R <- Regions]
            },
            {reply, {ok, Reply}, NewState}
    end;

handle_call({signin, _Params}, _From, State = #state{setup = false}) ->
    {reply, {error, {bad_request, <<"Association has not completed setup yet">>}}, State};

handle_call({signin, Params}, _From, State) ->
    Role = maps:get(<<"role">>, Params, <<"">>),
    RegionCode = maps:get(<<"regionCode">>, Params, <<"">>),
    Secret = maps:get(<<"secret">>, Params, <<"">>),
    Reply = case Role of
        <<"Chairperson">> ->
            Assoc = State#state.association,
            case chama_auth:verify_password(Secret, Assoc#association.chair_password_hash) of
                true -> {ok, #{<<"role">> => <<"Chairperson">>, <<"regionCode">> => null_or_all()}};
                false -> {error, {unauthorized, <<"Incorrect chairperson password">>}}
            end;
        <<"Secretary">> ->
            case find_region(RegionCode, State#state.regions) of
                undefined ->
                    {error, {bad_request, <<"Unknown region">>}};
                #region{code = Code} ->
                    case string:uppercase(binary_to_list(Secret)) =:= string:uppercase(binary_to_list(Code)) of
                        true -> {ok, #{<<"role">> => <<"Secretary">>, <<"regionCode">> => Code}};
                        false -> {error, {unauthorized, <<"Incorrect region code">>}}
                    end
            end;
        _ ->
            {error, {bad_request, <<"role must be Chairperson or Secretary">>}}
    end,
    {reply, Reply, State};

handle_call(list_regions, _From, State) ->
    {reply, {ok, [chama_view:region_to_map(R) || R <- State#state.regions]}, State};

handle_call({list_members, Filters}, _From, State) ->
    Region = maps:get(region, Filters, undefined),
    Query = maps:get(q, Filters, undefined),
    Members0 = maps:values(State#state.members),
    Members1 = filter_by_region(Members0, Region, fun(M) -> M#member.region end),
    Members2 = filter_members_by_query(Members1, Query),
    Sorted = lists:sort(fun(A, B) -> A#member.full_name =< B#member.full_name end, Members2),
    {reply, {ok, [chama_view:member_to_map(M) || M <- Sorted]}, State};

handle_call({get_member, Id}, _From, State) ->
    Reply = case maps:find(Id, State#state.members) of
        {ok, M} -> {ok, chama_view:member_to_map(M)};
        error -> {error, not_found}
    end,
    {reply, Reply, State};

handle_call({add_member, Form}, _From, State) ->
    case validate_member_form(Form) of
        {error, Reason} ->
            {reply, {error, {bad_request, Reason}}, State};
        ok ->
            Id = chama_util:new_id(<<"m">>),
            Region = maps:get(<<"region">>, Form),
            Member = #member{
                id = Id,
                national_id = maps:get(<<"nationalId">>, Form),
                full_name = maps:get(<<"fullName">>, Form),
                phone = maps:get(<<"phone">>, Form, <<"">>),
                region = Region,
                date_joined = maps:get(<<"dateJoined">>, Form, chama_util:today()),
                joining_fee = chama_util:to_number(maps:get(<<"joiningFee">>, Form, 0)),
                monthly = chama_util:to_number(maps:get(<<"monthly">>, Form, 0)),
                status = active,
                paid_this_month = false
            },
            Entry = #audit_entry{
                user = <<"Secretary">>,
                action = iolist_to_binary([
                    <<"Added member ID ">>, Member#member.national_id,
                    <<" (">>, Member#member.full_name, <<")">>
                ]),
                date = chama_util:today(),
                time = chama_util:now_time(),
                region = region_name(Region, State#state.regions)
            },
            NewState = State#state{
                members = maps:put(Id, Member, State#state.members),
                audit_log = [Entry | State#state.audit_log]
            },
            {reply, {ok, chama_view:member_to_map(Member)}, NewState}
    end;

handle_call({list_transactions, Filters}, _From, State) ->
    Region = maps:get(region, Filters, undefined),
    Type = maps:get(type, Filters, undefined),
    Method = maps:get(method, Filters, undefined),
    Query = maps:get(q, Filters, undefined),
    Tx0 = State#state.transactions,
    Tx1 = filter_by_region(Tx0, Region, fun(T) -> T#transaction.region end),
    Tx2 = case Type of
        undefined -> Tx1;
        <<"All">> -> Tx1;
        _ -> [T || T <- Tx1, tx_type_matches(T#transaction.type, Type)]
    end,
    Tx3 = case Method of
        undefined -> Tx2;
        <<"All">> -> Tx2;
        _ -> [T || T <- Tx2, T#transaction.method =:= Method]
    end,
    Tx4 = filter_tx_by_query(Tx3, Query),
    {reply, {ok, [chama_view:transaction_to_map(T) || T <- Tx4]}, State};

handle_call({add_payment, Params}, _From, State) ->
    MemberId = maps:get(<<"memberId">>, Params, undefined),
    Amount = chama_util:to_number(maps:get(<<"amount">>, Params, 0)),
    Reference = maps:get(<<"reference">>, Params, <<"MANUAL">>),
    case {MemberId, maps:find(MemberId, State#state.members)} of
        {undefined, _} ->
            {reply, {error, {bad_request, <<"memberId is required">>}}, State};
        {_, error} ->
            {reply, {error, not_found}, State};
        {_, {ok, Member}} when Amount =< 0 ->
            {reply, {error, {bad_request, <<"amount must be greater than zero">>}}, State};
        {_, {ok, Member}} ->
            UpdatedMember = Member#member{paid_this_month = true},
            Tx = #transaction{
                id = chama_util:new_id(<<"t">>),
                date = chama_util:today(),
                member_id = Member#member.national_id,
                member_name = Member#member.full_name,
                region = Member#member.region,
                type = payment,
                amount = Amount,
                method = maps:get(<<"method">>, Params, <<"Cash">>),
                recorded_by = <<"Secretary">>,
                status = <<"Completed">>,
                reference = Reference
            },
            Entry = #audit_entry{
                user = <<"Secretary">>,
                action = iolist_to_binary([<<"Recorded payment of KES ">>, amount_bin(Amount), <<" for ">>, Member#member.full_name]),
                date = chama_util:today(),
                time = chama_util:now_time(),
                region = region_name(Member#member.region, State#state.regions)
            },
            NewState = State#state{
                members = maps:put(Member#member.id, UpdatedMember, State#state.members),
                transactions = [Tx | State#state.transactions],
                audit_log = [Entry | State#state.audit_log]
            },
            {reply, {ok, chama_view:transaction_to_map(Tx)}, NewState}
    end;

handle_call({list_funerals, Filters}, _From, State) ->
    Region = maps:get(region, Filters, undefined),
    Funerals0 = maps:values(State#state.funerals),
    Funerals1 = filter_by_region(Funerals0, Region, fun(F) -> F#funeral.region end),
    Sorted = lists:sort(fun(A, B) -> A#funeral.date_of_death >= B#funeral.date_of_death end, Funerals1),
    {reply, {ok, [chama_view:funeral_to_map(F) || F <- Sorted]}, State};

handle_call({get_funeral, Id}, _From, State) ->
    Reply = case maps:find(Id, State#state.funerals) of
        {ok, F} -> {ok, chama_view:funeral_to_map(F)};
        error -> {error, not_found}
    end,
    {reply, Reply, State};

handle_call({record_death, Params}, _From, State) ->
    MemberId = maps:get(<<"memberId">>, Params, undefined),
    case maps:find(MemberId, State#state.members) of
        error ->
            {reply, {error, not_found}, State};
        {ok, Member} ->
            UpdatedMember = Member#member{status = deceased},
            Funeral = #funeral{
                id = chama_util:new_id(<<"f">>),
                member_id = Member#member.id,
                member_name = Member#member.full_name,
                national_id = Member#member.national_id,
                region = Member#member.region,
                date_of_death = maps:get(<<"dateOfDeath">>, Params, chama_util:today()),
                allocated = chama_util:to_number(maps:get(<<"allocated">>, Params, 0)),
                used = 0,
                notes = maps:get(<<"notes">>, Params, <<"">>),
                expenses = []
            },
            Entry = #audit_entry{
                user = <<"Secretary">>,
                action = iolist_to_binary([<<"Recorded death of member ">>, Member#member.full_name]),
                date = chama_util:today(),
                time = chama_util:now_time(),
                region = region_name(Member#member.region, State#state.regions)
            },
            NewState = State#state{
                members = maps:put(Member#member.id, UpdatedMember, State#state.members),
                funerals = maps:put(Funeral#funeral.id, Funeral, State#state.funerals),
                audit_log = [Entry | State#state.audit_log]
            },
            {reply, {ok, chama_view:funeral_to_map(Funeral)}, NewState}
    end;

handle_call({add_funeral_expense, FuneralId, Expense}, _From, State) ->
    case maps:find(FuneralId, State#state.funerals) of
        error ->
            {reply, {error, not_found}, State};
        {ok, Funeral} ->
            Amount = chama_util:to_number(maps:get(<<"amount">>, Expense, 0)),
            Description = maps:get(<<"description">>, Expense, <<"">>),
            case Amount =< 0 of
                true ->
                    {reply, {error, {bad_request, <<"amount must be greater than zero">>}}, State};
                false ->
                    ExpenseRec = #funeral_expense{
                        id = chama_util:new_id(<<"e">>),
                        description = Description,
                        amount = Amount,
                        date = chama_util:today()
                    },
                    UpdatedFuneral = Funeral#funeral{
                        used = Funeral#funeral.used + Amount,
                        expenses = Funeral#funeral.expenses ++ [ExpenseRec]
                    },
                    Tx = #transaction{
                        id = chama_util:new_id(<<"t">>),
                        date = chama_util:today(),
                        member_id = Funeral#funeral.national_id,
                        member_name = Funeral#funeral.member_name,
                        region = Funeral#funeral.region,
                        type = expense,
                        amount = Amount,
                        method = <<"Cash">>,
                        recorded_by = <<"Secretary">>,
                        status = <<"Completed">>,
                        reference = list_to_binary(string:uppercase(binary_to_list(Description)))
                    },
                    Entry = #audit_entry{
                        user = <<"Secretary">>,
                        action = iolist_to_binary([<<"Logged funeral expense — ">>, Description, <<", KES ">>, amount_bin(Amount)]),
                        date = chama_util:today(),
                        time = chama_util:now_time(),
                        region = region_name(Funeral#funeral.region, State#state.regions)
                    },
                    NewState = State#state{
                        funerals = maps:put(FuneralId, UpdatedFuneral, State#state.funerals),
                        transactions = [Tx | State#state.transactions],
                        audit_log = [Entry | State#state.audit_log]
                    },
                    {reply, {ok, chama_view:funeral_to_map(UpdatedFuneral)}, NewState}
            end
    end;

handle_call(list_audit_log, _From, State) ->
    {reply, {ok, [chama_view:audit_to_map(E) || E <- State#state.audit_log]}, State};

handle_call({dashboard_report, RegionCode}, _From, State) ->
    Members = [M || M <- maps:values(State#state.members), M#member.region =:= RegionCode],
    Tx = [T || T <- State#state.transactions, T#transaction.region =:= RegionCode],
    Funerals = [F || F <- maps:values(State#state.funerals), F#funeral.region =:= RegionCode],
    Today = chama_util:today(),
    CurrentMonth = binary:part(Today, 0, 7), %% "YYYY-MM"
    MonthPayments = [T || T <- Tx, T#transaction.type =:= payment, is_prefix(CurrentMonth, T#transaction.date)],
    Collected = lists:sum([T#transaction.amount || T <- MonthPayments]),
    UnpaidCount = length([M || M <- Members, M#member.status =:= active, not M#member.paid_this_month]),
    Report = #{
        <<"regionCode">> => RegionCode,
        <<"totalMembers">> => length([M || M <- Members, M#member.status =:= active]),
        <<"collectedThisMonth">> => Collected,
        <<"unpaidMembers">> => UnpaidCount,
        <<"activeFunerals">> => length([F || F <- Funerals, F#funeral.allocated > F#funeral.used])
    },
    {reply, {ok, Report}, State};

handle_call(financial_report, _From, State) ->
    Tx = State#state.transactions,
    Collected = lists:sum([T#transaction.amount || T <- Tx, T#transaction.type =:= payment]),
    Spent = lists:sum([T#transaction.amount || T <- Tx, T#transaction.type =:= expense]),
    ByRegion = group_amounts_by_region(Tx, State#state.regions),
    Report = #{
        <<"totalCollected">> => Collected,
        <<"totalExpenses">> => Spent,
        <<"netBalance">> => Collected - Spent,
        <<"byRegion">> => ByRegion
    },
    {reply, {ok, Report}, State};

handle_call(funeral_report, _From, State) ->
    Funerals = maps:values(State#state.funerals),
    Report = #{
        <<"totalCases">> => length(Funerals),
        <<"totalAllocated">> => lists:sum([F#funeral.allocated || F <- Funerals]),
        <<"totalUsed">> => lists:sum([F#funeral.used || F <- Funerals]),
        <<"openCases">> => length([F || F <- Funerals, F#funeral.used < F#funeral.allocated]),
        <<"cases">> => [chama_view:funeral_to_map(F) || F <- Funerals]
    },
    {reply, {ok, Report}, State};

handle_call(reset, _From, _State) ->
    {reply, ok, #state{}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% ============================================================
%% Internal helpers
%% ============================================================

null_or_all() -> <<"All">>.

find_region(_Code, []) -> undefined;
find_region(Code, [#region{code = Code} = R | _]) -> R;
find_region(Code, [_ | Rest]) -> find_region(Code, Rest).

region_name(Code, Regions) ->
    case find_region(Code, Regions) of
        undefined -> Code;
        #region{name = Name} -> Name
    end.

filter_by_region(List, undefined, _F) -> List;
filter_by_region(List, <<"All">>, _F) -> List;
filter_by_region(List, Region, F) -> [X || X <- List, F(X) =:= Region].

filter_members_by_query(List, undefined) -> List;
filter_members_by_query(List, <<"">>) -> List;
filter_members_by_query(List, Query) ->
    Needle = string:lowercase(binary_to_list(Query)),
    [M || M <- List,
        string:find(string:lowercase(binary_to_list(M#member.full_name)), Needle) =/= nomatch
        orelse string:find(binary_to_list(M#member.national_id), Needle) =/= nomatch
    ].

filter_tx_by_query(List, undefined) -> List;
filter_tx_by_query(List, <<"">>) -> List;
filter_tx_by_query(List, Query) ->
    Needle = string:lowercase(binary_to_list(Query)),
    [T || T <- List,
        string:find(string:lowercase(binary_to_list(T#transaction.member_name)), Needle) =/= nomatch
        orelse string:find(binary_to_list(T#transaction.reference), Needle) =/= nomatch
    ].

tx_type_matches(payment, <<"Payment">>) -> true;
tx_type_matches(expense, <<"Expense">>) -> true;
tx_type_matches(_, _) -> false.

validate_member_form(Form) ->
    Required = [<<"nationalId">>, <<"fullName">>, <<"region">>],
    Missing = [K || K <- Required, maps:get(K, Form, <<"">>) =:= <<"">>],
    case Missing of
        [] -> ok;
        _ -> {error, iolist_to_binary([<<"Missing required fields: ">>, lists:join(<<", ">>, Missing)])}
    end.

is_prefix(Prefix, Bin) ->
    Len = byte_size(Prefix),
    byte_size(Bin) >= Len andalso binary:part(Bin, 0, Len) =:= Prefix.

amount_bin(Amount) when is_integer(Amount) -> integer_to_binary(Amount);
amount_bin(Amount) when is_float(Amount) -> float_to_binary(Amount, [{decimals, 2}]).

group_amounts_by_region(Tx, Regions) ->
    lists:map(fun(#region{code = Code, name = Name}) ->
        RegionTx = [T || T <- Tx, T#transaction.region =:= Code],
        Collected = lists:sum([T#transaction.amount || T <- RegionTx, T#transaction.type =:= payment]),
        Spent = lists:sum([T#transaction.amount || T <- RegionTx, T#transaction.type =:= expense]),
        #{<<"code">> => Code, <<"name">> => Name, <<"collected">> => Collected, <<"expenses">> => Spent}
    end, Regions).
