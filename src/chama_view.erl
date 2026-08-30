-module(chama_view).

-include("chama.hrl").

-export([
    association_to_map/1,
    region_to_map/1,
    member_to_map/1,
    transaction_to_map/1,
    funeral_to_map/1,
    funeral_expense_to_map/1,
    audit_to_map/1
]).

%% Never exposes chair_password_hash to the client.
association_to_map(#association{name = Name, phone = Phone, location = Location}) ->
    #{<<"name">> => Name, <<"phone">> => Phone, <<"location">> => Location}.

region_to_map(#region{code = Code, name = Name}) ->
    #{<<"code">> => Code, <<"name">> => Name}.

member_to_map(#member{
    id = Id, national_id = NationalId, full_name = FullName, phone = Phone,
    region = Region, date_joined = DateJoined, joining_fee = JoiningFee,
    monthly = Monthly, status = Status, paid_this_month = Paid
}) ->
    #{
        <<"id">> => Id,
        <<"nationalId">> => NationalId,
        <<"fullName">> => FullName,
        <<"phone">> => Phone,
        <<"region">> => Region,
        <<"dateJoined">> => DateJoined,
        <<"joiningFee">> => JoiningFee,
        <<"monthly">> => Monthly,
        <<"status">> => status_to_bin(Status),
        <<"paidThisMonth">> => Paid
    }.

status_to_bin(active) -> <<"Active">>;
status_to_bin(deceased) -> <<"Deceased">>.

transaction_to_map(#transaction{
    id = Id, date = Date, member_id = MemberId, member_name = MemberName,
    region = Region, type = Type, amount = Amount, method = Method,
    recorded_by = RecordedBy, status = Status, reference = Reference
}) ->
    #{
        <<"id">> => Id,
        <<"date">> => Date,
        <<"memberId">> => MemberId,
        <<"memberName">> => MemberName,
        <<"region">> => Region,
        <<"type">> => tx_type_to_bin(Type),
        <<"amount">> => Amount,
        <<"method">> => Method,
        <<"recordedBy">> => RecordedBy,
        <<"status">> => Status,
        <<"reference">> => Reference
    }.

tx_type_to_bin(payment) -> <<"Payment">>;
tx_type_to_bin(expense) -> <<"Expense">>.

funeral_expense_to_map(#funeral_expense{id = Id, description = Desc, amount = Amount, date = Date}) ->
    #{<<"id">> => Id, <<"description">> => Desc, <<"amount">> => Amount, <<"date">> => Date}.

funeral_to_map(#funeral{
    id = Id, member_id = MemberId, member_name = MemberName, national_id = NationalId,
    region = Region, date_of_death = Dod, allocated = Allocated, used = Used,
    notes = Notes, expenses = Expenses
}) ->
    #{
        <<"id">> => Id,
        <<"memberId">> => MemberId,
        <<"memberName">> => MemberName,
        <<"nationalId">> => NationalId,
        <<"region">> => Region,
        <<"dateOfDeath">> => Dod,
        <<"allocated">> => Allocated,
        <<"used">> => Used,
        <<"balance">> => Allocated - Used,
        <<"notes">> => Notes,
        <<"expenses">> => [funeral_expense_to_map(E) || E <- Expenses]
    }.

audit_to_map(#audit_entry{user = User, action = Action, date = Date, time = Time, region = Region}) ->
    #{<<"user">> => User, <<"action">> => Action, <<"date">> => Date, <<"time">> => Time, <<"region">> => Region}.
