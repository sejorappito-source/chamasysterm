-module(chama_http).

-export([
    read_json/1,
    reply_json/3,
    reply_ok/2,
    reply_created/2,
    reply_error/3,
    reply_not_found/1,
    reply_bad_request/2,
    reply_unauthorized/2,
    binding/3,
    qs_val/3
]).

%% Reads and decodes a JSON request body. Returns {ok, Map, Req2} or
%% {error, invalid_json, Req2}.
read_json(Req0) ->
    {ok, Body, Req1} = cowboy_req:read_body(Req0),
    case Body of
        <<>> -> {ok, #{}, Req1};
        _ ->
            try
                Decoded = jsx:decode(Body, [return_maps]),
                {ok, Decoded, Req1}
            catch
                _:_ -> {error, invalid_json, Req1}
            end
    end.

reply_json(Status, Payload, Req) ->
    Body = jsx:encode(Payload),
    cowboy_req:reply(
        Status,
        #{<<"content-type">> => <<"application/json">>},
        Body,
        Req
    ).

reply_ok(Payload, Req) ->
    reply_json(200, Payload, Req).

reply_created(Payload, Req) ->
    reply_json(201, Payload, Req).

reply_error(Status, Message, Req) when is_binary(Message) ->
    reply_json(Status, #{<<"error">> => Message}, Req).

reply_not_found(Req) ->
    reply_error(404, <<"Not found">>, Req).

reply_bad_request(Message, Req) ->
    reply_error(400, Message, Req).

reply_unauthorized(Message, Req) ->
    reply_error(401, Message, Req).

%% Fetch a path binding with a default value.
binding(Name, Req, Default) ->
    case cowboy_req:binding(Name, Req) of
        undefined -> Default;
        Value -> Value
    end.

%% Fetch a query-string value with a default value.
qs_val(Name, Req, Default) ->
    case cowboy_req:match_qs([{Name, [], Default}], Req) of
        #{} = Map -> maps:get(Name, Map, Default)
    end.
