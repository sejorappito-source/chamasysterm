-module(chama_app).
-behaviour(application).

-export([start/2, stop/1]).

start(_StartType, _StartArgs) ->
    Dispatch = cowboy_router:compile(chama_router:routes()),
    Port = http_port(),
    {ok, _} = cowboy:start_clear(
        chama_http_listener,
        [{port, Port}],
        #{
            env => #{dispatch => Dispatch},
            middlewares => [chama_cors_middleware, cowboy_router, cowboy_handler]
        }
    ),
    error_logger:info_msg("Chama backend listening on port ~p~n", [Port]),
    chama_sup:start_link().

%% Most hosts that run containers (Render, Fly, Heroku-style buildpacks)
%% inject the port to bind to via the $PORT env var rather than letting
%% you pick one - honor it when present, otherwise fall back to
%% config/sys.config's http_port (useful for plain `rebar3 shell`).
http_port() ->
    case os:getenv("PORT") of
        false -> application:get_env(chama, http_port, 8080);
        PortStr -> list_to_integer(PortStr)
    end.

stop(_State) ->
    ok = cowboy:stop_listener(chama_http_listener),
    ok.
