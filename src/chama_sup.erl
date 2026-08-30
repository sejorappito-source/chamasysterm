-module(chama_sup).
-behaviour(supervisor).

-export([start_link/0]).
-export([init/1]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => one_for_one,
        intensity => 5,
        period => 10
    },
    ChildSpecs = [
        #{
            id => chama_store,
            start => {chama_store, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [chama_store]
        }
    ],
    {ok, {SupFlags, ChildSpecs}}.
