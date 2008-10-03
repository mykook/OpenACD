-module(call_queue).

-ifdef(EUNIT).
-include_lib("eunit/include/eunit.hrl").
-endif.

-behaviour(gen_server).
-include("call.hrl").
-export([start/1, start_link/1, add/3, ask/1, print/1, remove/2, stop/1, grab/1]).

%gen_server support
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

start(Name) ->
	gen_server:start(?MODULE, [Name], []).

start_link(Name) ->
	gen_server:start_link(?MODULE, [Name], []).

init([Name]) -> 
	put(name, Name),
	{ok, gb_trees:empty()}.

add(Priority, Calldata, Pid) -> 
	gen_server:call(Pid, {add, Priority, Calldata}, infinity).

ask(Pid) -> 
	gen_server:call(Pid, ask).

grab(Pid) -> 
	gen_server:call(Pid, grab).

print(Pid) ->
	gen_server:call(Pid, print).

remove(Calldata, Pid) -> 
	gen_server:call(Pid, {remove, Calldata}).

stop(Pid) ->
	gen_server:call(Pid, stop).

find_unbound(none, _From) -> 
	none;
find_unbound({Key, #call{bound = []} = Value, _Iter}, _From) ->
	{Key, Value};
find_unbound({Key, #call{bound = B} = Value, Iter}, {From, _}) ->
	case lists:filter(fun(Pid) -> node(Pid) =:= node(From) end, B ) of
		[] ->
			{Key, Value};
		_ -> 
			find_unbound(gb_trees:next(Iter), {From, foo})
	end.

find_key(Needle, {Key, #call{idnum = Needle}, _Iter}) ->
	Key;
find_key(Needle, {_Key, _Value, Iter}) ->
	find_key(Needle, gb_trees:next(Iter));
find_key(_Needle, none) -> 
	none.

handle_call({add, Priority, Calldata}, _From, State) -> 
	{reply, ok, gb_trees:insert({Priority,now()}, Calldata, State)};
handle_call(ask, From, State) ->
	%generate a call in queue excluding those already bound
	% return a tuple:  {key, val}
	{reply, find_unbound(gb_trees:next(gb_trees:iterator(State)), From), State};
handle_call(grab, From, State) ->
	% ask and bind in one handy step
	io:format("From:  ~p~n", [From]),
	case find_unbound(gb_trees:next(gb_trees:iterator(State)), From) of
		none -> 
			{reply, none, State};
		{Key, Value} ->
			{Realfrom, _} = From, 
			State2 = gb_trees:update(Key, Value#call{bound=lists:append(Value#call.bound, [Realfrom])}, State),
			{reply, {Key, Value}, State2}
	end;

handle_call(print, _From, State) ->
	{reply, State, State};
handle_call({remove, #call{} = Calldata}, _From, State) -> 
	Key = find_key(Calldata#call.idnum, gb_trees:next(gb_trees:iterator(State))),
	%io:format("Key:  ~p~n", [Key]),
	State2 = gb_trees:delete_any(Key, State),
	{reply, ok, State2};
handle_call({remove, Id}, _From, State) ->
	Key = find_key(Id, gb_trees:next(gb_trees:iterator(State))),
	State2 = gb_trees:delete_any(Key, State),
	{reply, ok, State2};
handle_call(stop, _From, State) ->
	{stop, nicestop, please, State};
handle_call(_Request, _From, State) ->
	{reply, ok, State}.

handle_cast(_Msg, State) ->
	{noreply, State}.

handle_info(_Info, State) -> 
	{noreply, State}.

terminate(_Reason, _State) -> 
	ok.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

% begin the defintions of the tests.

-ifdef(TEST).

add_test() ->
	{_, Pid} = start(goober),
	C1 = #call{idnum="C1"},
	?assert(add(1, C1, Pid) =:= ok),
	?assertMatch({{1, _Time}, C1}, ask(Pid)).
	
remove_test() ->
	{_, Pid} = start(goober),
	C1 = #call{idnum="C1"},
	C2 = #call{idnum="C2"},
	add(1, C1, Pid),
	add(1, C2, Pid),
	remove(C1, Pid),
	?assertMatch({_Key, C2}, grab(Pid)).
	
remove_id_test() ->
	{_, Pid} = start(goober),
	C1 = #call{idnum="C1"},
	add(1, C1, Pid),
	?assertMatch(ok, remove("C1", Pid)),
	?assertMatch(none, grab(Pid)).

remove_nil_test() ->
	{_, Pid} = start(goober), 
	?assertMatch(ok, remove("C1", Pid)).

find_key_test() ->
	{_, Pid} = start(goober),
	C1 = #call{idnum="C1"},
	C2 = #call{idnum="C2", bound=[self()]},
	add(1, C1, Pid),
	?assertMatch(ok, remove(C2, Pid)).

bound_test() ->
	{_, Node} = slave:start(net_adm:localhost(), goober),
	Pid = spawn(Node, fun() -> true end),
	C1 = #call{idnum="C1", bound=[Pid]},
	{_, Qpid} = start(foobar),
	add(1, C1, Qpid),
	?assertMatch({_Key, C1}, grab(Qpid)),
	?assertMatch(none, grab(Qpid)).

grab_test() -> 
	C1 = #call{idnum="C1"},
	C2 = #call{idnum="C2", bound=[self()]},
	C3 = #call{idnum="C3"},
	{_, Pid} = start(goober),
	add(1, C1, Pid),
	add(0, C2, Pid),
	add(1, C3, Pid),
	?assertMatch({_Key, C1}, grab(Pid)),
	?assertMatch({_Key, C3}, grab(Pid)),
	?assert(grab(Pid) =:= none).

grab_empty_test() -> 
	{_, Pid} = start(goober),
	?assert(grab(Pid) =:= none).
-endif.
