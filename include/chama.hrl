%% ============================================================
%% Chama domain records
%% Mirrors the data model used by the chama-system.jsx frontend:
%%   Association, Region, Member, Transaction, Funeral (+Expense),
%%   AuditLogEntry.
%% ============================================================

-record(association, {
    account_code      :: binary(),
    name              :: binary(),
    phone             :: binary(),
    location          :: binary(),
    chair_password_hash :: binary()
}).

-record(region, {
    code :: binary(),
    name :: binary(),
    password_hash :: binary() | undefined
}).

-record(member, {
    id            :: binary(),
    national_id   :: binary(),
    full_name     :: binary(),
    phone         :: binary(),
    region        :: binary(),
    date_joined   :: binary(),
    joining_fee   :: number(),
    monthly       :: number(),
    status        :: active | deceased,
    paid_this_month :: boolean()
}).

-record(transaction, {
    id           :: binary(),
    date         :: binary(),
    member_id    :: binary(),   %% national_id
    member_name  :: binary(),
    region       :: binary(),
    type         :: payment | expense,
    amount       :: number(),
    method       :: binary(),   %% <<"Cash">> | <<"M-Pesa">>
    recorded_by  :: binary(),
    status       :: binary(),
    reference    :: binary()
}).

-record(funeral_expense, {
    id          :: binary(),
    description :: binary(),
    amount      :: number(),
    date        :: binary()
}).

-record(funeral, {
    id            :: binary(),
    member_id     :: binary(),  %% member's internal id
    member_name   :: binary(),
    national_id   :: binary(),
    region        :: binary(),
    date_of_death :: binary(),
    allocated     :: number(),
    used          :: number(),
    notes         :: binary(),
    expenses      :: [#funeral_expense{}]
}).

-record(audit_entry, {
    user   :: binary(),
    action :: binary(),
    date   :: binary(),
    time   :: binary(),
    region :: binary()
}).
