-module(chama_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile(chama_router:routes()),
    Port = application:get_env(chama, http_port, 8080),
    {ok, _} = cowboy:start_clear(
        chama_http_listener,
        [{port, Port}],
        #{env => #{dispatch => Dispatch}}
    ),
    error_logger:info_msg("Chama backend listening on port ~p~n", [Port]),
    chama_sup:start_link().

stop(_State) ->
    ok = cowboy:stop_listener(chama_http_listener),
    ok.
