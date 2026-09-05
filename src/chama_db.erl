-module(chama_db).

-export([connect/0, ensure_connected/1, new_account_code/0]).

%% Connects using the DATABASE_URL env var, e.g.:
%%   postgres://user:pass@host:5432/dbname
%% Render's "Internal Database URL" matches this format (port may be
%% omitted, defaults to 5432). Falls back to {error, no_database_url}
%% if the env var isn't set, so the app can still boot and log a clear
%% error rather than crash-looping with no explanation.
connect() ->
    case os:getenv("DATABASE_URL") of
        false ->
            {error, no_database_url};
        Url ->
            case parse_url(list_to_binary(Url)) of
                {ok, Opts} -> epgsql:connect(Opts);
                {error, _} = Err -> Err
            end
    end.

%% Given a possibly-dead connection, returns a live one (reconnecting
%% if needed). chama_store keeps one connection in its gen_server state
%% and calls are already serialized by the gen_server, so a single
%% connection is sufficient for this app's scale.
ensure_connected(undefined) ->
    connect();
ensure_connected(Conn) ->
    case epgsql:squery(Conn, "SELECT 1") of
        {ok, _, _} -> {ok, Conn};
        _ -> connect()
    end.

%% Short, human-typeable account code, e.g. <<"CH-7F3K9Q">>.
new_account_code() ->
    Alphabet = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789", %% no 0/O/1/I ambiguity
    Chars = [lists:nth(rand:uniform(length(Alphabet)), Alphabet) || _ <- lists:seq(1, 6)],
    iolist_to_binary([<<"CH-">>, Chars]).

%% ============================================================
%% URL parsing
%% ============================================================

parse_url(Url) ->
    try
        <<"postgres", Rest0/binary>> = Url,
        Rest1 = strip_scheme_suffix(Rest0), %% handles "://" or "ql://"
        {UserInfo, HostPart} = split_once(Rest1, $@),
        {User, Pass} = case split_once(UserInfo, $:) of
            {U, P} -> {U, P};
            error -> {UserInfo, <<"">>}
        end,
        {HostPort, DbAndQuery} = split_once(HostPart, $/),
        {Host, Port} = case split_once(HostPort, $:) of
            {H, PBin} -> {binary_to_list(H), binary_to_integer(PBin)};
            error -> {binary_to_list(HostPort), 5432}
        end,
        {DbName, _Query} = case split_once(DbAndQuery, $?) of
            {D, Q} -> {D, Q};
            error -> {DbAndQuery, <<"">>}
        end,
        {ok, #{
            host => Host,
            port => Port,
            username => binary_to_list(User),
            password => binary_to_list(Pass),
            database => binary_to_list(DbName),
            timeout => 5000,
            ssl => false
        }}
    catch
        _:_ -> {error, invalid_database_url}
    end.

strip_scheme_suffix(<<"ql://", Rest/binary>>) -> Rest;
strip_scheme_suffix(<<"://", Rest/binary>>) -> Rest;
strip_scheme_suffix(Bin) -> Bin.

split_once(Bin, Char) ->
    case binary:split(Bin, <<Char>>) of
        [A, B] -> {A, B};
        [_] -> error
    end.
