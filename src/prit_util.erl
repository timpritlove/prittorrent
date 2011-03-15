-module(prit_util).

%-compile(export_all).
-export([read_all/1, to_hex/1, info_hash_representation/1, to_printable_binary/1]).

-include_lib("stdlib/include/qlc.hrl").






% nice output



info_hash_representation(InfoHash) ->
	iolist_to_binary(io_lib:format("~s ~W",[to_hex(InfoHash), InfoHash,5])). % ~P lets you specify the depth where it does the elippsing

to_hex(List) when is_list(List) ->
	to_hex(iolist_to_binary(List));
to_hex(Binary) when is_binary(Binary) ->
	<< <<(to_digit(Nibble1)):8,(to_digit(Nibble2)):8>> || <<Nibble1:4,Nibble2:4>> <= Binary >>.

to_digit(N) when N < 10 -> $0 + N;
to_digit(N)             -> $a + N-10.

to_printable_binary(List) when is_list(List) -> to_printable_binary(iolist_to_binary(List));
to_printable_binary(Binary) ->
	<< <<(ensure_printable_character(Char)):8>> || <<Char:8>> <= Binary >>.

ensure_printable_character(Character) when Character < 16#20; Character > 16#7e -> $_;
ensure_printable_character(Character) -> Character.

% mnesia debugging tools

find(Q) ->
	F = fun() ->
			qlc:e(Q)
	end,
	graceful_transaction(F).

read_all(Table) ->
	Q = qlc:q([X || X <- mnesia:table(Table)]),
	find(Q). 

graceful_transaction(F) ->
	case mnesia:transaction(F) of
		{atomic, Result} ->
			Result;
		{aborted, Reason} ->
			io:format("transaction abort: ~p~n",[Reason]),
			[]
	end.	



