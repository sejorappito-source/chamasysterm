-module(chama_debug_handler).

-export([init/2]).

init(Req0, State) ->
    PrivDirResult = case code:priv_dir(chama) of
        {error, Reason} -> iolist_to_binary(io_lib:format("error: ~p", [Reason]));
        Dir -> list_to_binary(Dir)
    end,
    IndexExists = case code:priv_dir(chama) of
        {error, _} -> false;
        Dir3 ->
            Path = filename:join([Dir3, "static", "index.html"]),
            filelib:is_regular(Path)
    end,
    StaticDirListing = case code:priv_dir(chama) of
        {error, _} -> [];
        Dir4 ->
            StaticPath = filename:join([Dir4, "static"]),
            case file:list_dir(StaticPath) of
                {ok, Files} -> [list_to_binary(F) || F <- Files];
                {error, _} -> []
            end
    end,
    Body = jsx:encode(#{
        <<"priv_dir">> => PrivDirResult,
        <<"index_exists">> => IndexExists,
        <<"static_dir_listing">> => StaticDirListing
    }),
    Req = cowboy_req:reply(200, #{<<"content-type">> => <<"application/json">>}, Body, Req0),
    {ok, Req, State}.
