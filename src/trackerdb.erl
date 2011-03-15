-module(trackerdb).

-export([init/0, announce/7, remove/3, unix_seconds_since_epoch/0, remove_peers_with_timeout_in_seconds/1]).

-include_lib("stdlib/include/qlc.hrl").

-record(pirate, { id, info_hash, ip, port, peer_id, 
					uploaded, downloaded, left,
					first_seen, last_seen}).

-record(swarm_status, { info_hash, complete, incomplete}). 

init() ->
    mnesia:create_table(pirate,
			[{attributes, record_info(fields, pirate)}, {type, set}, {index, [info_hash]}]).

% using astro's _t to mean needs to be inside of an transaction
swarm_status_t(InfoHash) ->
		{ Complete, Incomplete } = qlc:fold(
			fun(#pirate{left = 0}, { CompleteAcc, IncompleteAcc} ) ->
				{ CompleteAcc + 1, IncompleteAcc };
			(_, { CompleteAcc, IncompleteAcc} ) ->
				{ CompleteAcc , IncompleteAcc + 1 }
			end, 
			{0, 0}, 
			qlc:q([Pirate || Pirate = #pirate{}  <- mnesia:table(pirate), Pirate#pirate.info_hash =:= InfoHash])
		),
		{ok, #swarm_status{info_hash = InfoHash, complete = Complete, incomplete = Incomplete}}.
	

announce(InfoHash, Ip, Port, PeerId, Uploaded, Downloaded, Left) ->
	PrimaryPeerKey = { InfoHash, Ip, Port },
	{atomic, Result} = mnesia:transaction(fun() -> 
		AllPeers = case Left of 
			0 -> % we are seeder
				qlc:e(qlc:q([Pirate || Pirate <- mnesia:table(pirate), Pirate#pirate.left =/= 0]));
			_ -> % we are leecher
				mnesia:index_read(pirate, InfoHash, #pirate.info_hash)
		end,
		Now = unix_seconds_since_epoch(),
		PeerUpdate = case mnesia:read(pirate, PrimaryPeerKey) of
			[Peer = #pirate{ }] -> Peer#pirate { peer_id = PeerId, uploaded = Uploaded,
												 	downloaded = Downloaded, left = Left, last_seen = Now };
			[] -> #pirate{ id = PrimaryPeerKey,
							info_hash = InfoHash, ip = Ip, port = Port, peer_id = PeerId,
							uploaded = Uploaded, downloaded = Downloaded, left = Left,
							first_seen = Now, last_seen = Now }
		end,
		mnesia:write(PeerUpdate),

		{ok, #swarm_status{complete = Complete, incomplete = Incomplete}} = swarm_status_t(InfoHash),

		AvailablePeers = [ { TmpPeerId, TmpIp, TmpPort } ||
							Peer = #pirate{ peer_id = TmpPeerId, ip = TmpIp, port = TmpPort } <- AllPeers, Peer#pirate.id =/= PrimaryPeerKey],
		{ ok, AvailablePeers, Complete, Incomplete }
		end),
	Result.

remove(InfoHash, Ip, Port) ->
	{atomic, Result} = mnesia:transaction(
		fun() -> 
			mnesia:delete({pirate, { InfoHash, Ip, Port } })
		end),
	Result.
	
remove_peers_with_timeout_in_seconds(Seconds) ->
	KillTime = unix_seconds_since_epoch() - Seconds, % all pirates iwth an update date of this and below need to go away
	Q = qlc:q([Pirate || Pirate <- mnesia:table(pirate), Pirate#pirate.last_seen < KillTime]),
	F = fun () ->
		PiratesToKill = qlc:e(Q),
		lists:foreach( fun(Pirate) -> mnesia:delete_object(Pirate) end, PiratesToKill),
		io:format("Killing Pirates: ~p \n",[PiratesToKill]) % should not do this in a transaction…
	end,
	graceful_transaction(F).

graceful_transaction(F) ->
	case mnesia:transaction(F) of
		{atomic, Result} ->
			Result;
		{aborted, Reason} ->
			io:format("transaction abort: ~p~n",[Reason]),
			[]
	end.	


% find(Q) ->
% 	F = fun() ->
% 			qlc:e(Q)
% 	end,
% 	graceful_transaction(F).
% 
% read_all(Table) ->
% 	Q = qlc:q([X || X <- mnesia:table(Table)]),
% 	graceful_transaction(Q). 


unix_seconds_since_epoch() ->
    LocalDateTime = calendar:datetime_to_gregorian_seconds(calendar:universal_time()),
    UnixEpoch = calendar:datetime_to_gregorian_seconds({{1970,1,1},{0,0,0}}),
    LocalDateTime - UnixEpoch.


% make_timestamp(now) ->
% 	{ MegaSeconds, Seconds, MicroSeconds} = erlang:now(),
% 	(MegaSeconds * 1000000 + Seconds) * 1000000 + MicroSeconds.