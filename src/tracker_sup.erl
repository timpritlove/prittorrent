-module(tracker_sup).
-behaviour(supervisor).

%% API
-export([start_link/0]).
%% Supervisor callbacks
-export([init/1]).


-define(SERVER, ?MODULE).

start_link() ->
    supervisor:start_link({local, ?SERVER}, ?MODULE, []).

init([]) ->
    RestartStrategy = one_for_one,
    MaxRestarts = 10,
    MaxSecondsBetweenRestarts = 5,

    SupFlags = {RestartStrategy, MaxRestarts, MaxSecondsBetweenRestarts},

    TrackerWeb = {tracker_web,
	       {tracker_web, start, [[{ip, "0.0.0.0"}, {port, get_port()}]]},
	       permanent, 2000, worker, [tracker_web]},
    TrackerManager = {tracker_manager,
		{tracker_manager, start_link, []},
		permanent, 2000, worker, [tracker_manager]},

    {ok, {SupFlags, [TrackerWeb, TrackerManager]}}.


get_port() ->
    case application:get_env(servtorrent, tracker_port) of
	    {ok,Port} -> Port;
		_ -> 6969 % default if not set
	end.