% Realiable statefull writer, it manages Reader-proxies sends heatbeats and receives acknacks
-module(rtps_full_writer).

-behaviour(gen_server).

-export([start_link/1,on_change_available/2,new_change/2,get_cache/1,update_matched_readers/2,
        matched_reader_add/2,matched_reader_remove/2,is_acked_by_all/1,receive_acknack/2]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2]).

-include_lib("dds/include/rtps_structure.hrl").
-include_lib("dds/include/rtps_constants.hrl").

-record(state,{
        participant = #participant{},
        entity = #endPoint{},
        datawrite_period= 1000, % default at 1000
        heatbeat_period= 1000, % default at 1000
        heatbeat_count= 1,
        nackResponseDelay= 200, % default at 200
        nackSuppressionDuration= 0,
        push_mode = true,
        history_cache,
        reader_proxies=[],
        last_sequence_number = 0
}).
%API
start_link({Participant,WriterConfig}) -> gen_server:start_link(?MODULE, {Participant,WriterConfig},[]).

new_change(Name,Data) -> 
        [Pid|_] = pg:get_members(Name), 
        gen_server:call(Pid,{new_change,Data}).
on_change_available(Name, ChangeKey) ->         
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {on_change_available, ChangeKey}).
%Adds new locators if missing, removes old locators not specified in the call.
update_matched_readers(Name, R) ->         
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {update_matched_readers, R}).
matched_reader_add(Name, R) ->         
        [Pid|_] = pg:get_members(Name), 
        gen_server:cast(Pid, {matched_reader_add, R}).
matched_reader_remove(Name, R)->         
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {matched_reader_remove, R}).
is_acked_by_all(Name) ->         
        [Pid|_] = pg:get_members(Name), 
        gen_server:call(Pid, is_acked_by_all).
receive_acknack(Name, Acknack) ->         
        [Pid|_] = pg:get_members(Name),
        gen_server:cast(Pid, {receive_acknack, Acknack}).
get_cache(Name) ->
        [Pid|_] = pg:get_members(Name), 
        gen_server:call(Pid,get_cache).

% callbacks
init({Participant,#endPoint{guid=GUID}=WriterConfig}) -> 
        pg:join(GUID, self()),
        %io:format("~p.erl STARTED!\n",[?MODULE]), 
        State = #state{participant = Participant, 
                        entity = WriterConfig,
                        history_cache = {cache_of, GUID}},
        rtps_history_cache:set_listener({cache_of, GUID}, {GUID,?MODULE}),
        
        erlang:send_after(100,self(),heartbeat_loop),
        erlang:send_after(200,self(),write_loop),
        {ok,State}.
terminate(_,_) -> io:format("I FULL WRITER DIED\n").

handle_call({new_change,Data}, _, State) ->  
        {Change, NewState} = h_new_change(Data, State),
        {reply, Change, NewState};
handle_call(get_cache, _, State) -> {reply,State#state.history_cache,State};
handle_call(is_acked_by_all, _, State) -> {reply,h_is_acked_by_all(State),State};
handle_call(_, _, State) -> {reply,ok,State}.
handle_cast({on_change_available, ChangeKey},S) -> {noreply, h_on_change_available(ChangeKey,S)};
handle_cast({update_matched_readers, Proxies}, State) -> {noreply,h_update_matched_readers(Proxies,State)};
handle_cast({matched_reader_add,Proxy}, State) -> {noreply,h_matched_reader_add(Proxy,State)};
handle_cast({matched_reader_remove,Guid}, State) -> {noreply,h_matched_reader_remove(Guid,State)};
handle_cast({receive_acknack, Acknack}, State) -> {noreply, h_receive_acknack(Acknack,State)};
handle_cast(_, State) -> {noreply,State}.

handle_info(heartbeat_loop,State) -> {noreply,heartbeat_loop(State)};
handle_info(write_loop,State) -> {noreply,write_loop(State)}.


%callback helpers

send_to_heatbeat_to_readers(_,_,[]) -> ok;
send_to_heatbeat_to_readers(GuidPrefix, HB, [#reader_proxy{guid = ReaderGUID,unicastLocatorList=[L|_]} | TL]) ->   
        [G|_] = pg:get_members(rtps_gateway),
        SUB_MSG_LIST = [rtps_messages:serialize_heatbeat(HB#heartbeat{readerGUID=ReaderGUID})],
        Datagram = rtps_messages:build_message(GuidPrefix, SUB_MSG_LIST),
        rtps_gateway:send(G, {Datagram,{L#locator.ip,L#locator.port}}),
        send_to_heatbeat_to_readers(GuidPrefix, HB, TL).

% Must send the first HB with min 1 and max 0 to allow first MSG to be considered,
% This triggers an acknack response with final_flag=1 which means the next data is really requested
% This is already done by the rtps_history_cache:get_min_seq_num() and rtps_history_cache:get_max_seq_num()
send_heatbeat(#state{entity=#endPoint{guid=GUID}, history_cache=C, heatbeat_count=Count,reader_proxies=RP}) -> 
        MinSN = rtps_history_cache:get_min_seq_num(C),
        MaxSN = rtps_history_cache:get_max_seq_num(C),
        HB = #heartbeat{
                writerGUID = GUID,
                min_sn = MinSN,
                max_sn = MaxSN,
                count = Count,
                final_flag = 0,
                readerGUID= ?GUID_UNKNOWN
        },
        send_to_heatbeat_to_readers(GUID#guId.prefix,HB,RP).

heartbeat_loop(#state{heatbeat_period=HP,heatbeat_count=C}=S) -> 
        send_heatbeat(S),
        erlang:send_after(1000, self(), heartbeat_loop),
        S#state{heatbeat_count=C+1}.


send_selected_changes([], _, _, #reader_proxy{changes_for_reader=CR}) -> CR;
send_selected_changes(RequestedKeys,Prefix, HC,
                #reader_proxy{guid=#guId{entityId=RID},unicastLocatorList=[L|_],changes_for_reader=CR}) ->

        ToSend = [ rtps_history_cache:get_change(HC,K) || K <- RequestedKeys],
        [G|_] = pg:get_members(rtps_gateway),
        SUB_MSG = [rtps_messages:serialize_info_timestamp()] ++ [ rtps_messages:serialize_data(RID,C) || C <- ToSend ],
        Msg = rtps_messages:build_message(Prefix, SUB_MSG),
        rtps_gateway:send(G,{ Msg,{L#locator.ip, L#locator.port}}),
        
        % mark all sent requests as "unacknowledged" (skipping the "UNDERWAY" status) just for simplicity
        NewCR = lists:map(fun(C) -> 
                case lists:member(C#change_for_reader.change_key, RequestedKeys) of
                        true -> C#change_for_reader{status = unacknowledged};
                        false -> C
                end
        end, CR).

send_changes(Filter, Prefix, _, [],Sent) -> Sent;
send_changes(Filter, Prefix, HC, [#reader_proxy{guid=#guId{entityId=RID},unicastLocatorList=[L|_], changes_for_reader=CR}=P|TL], Sent) -> 
        RequestedKeys = [ K || #change_for_reader{change_key = K, status = S} <- CR, S == Filter],
        % case (Filter == unsent) and (length(RequestedKeys) > 0) of 
        %         true -> io:format("Pushing, ~p\n", [RequestedKeys]);
        %         _ -> ok
        % end,        
        NewCR = send_selected_changes(RequestedKeys, Prefix, HC, P),
        send_changes(Filter, Prefix, HC, TL, [P#reader_proxy{changes_for_reader=NewCR} | Sent]).

send_changes(Filter, Prefix,HC,RP) -> send_changes(Filter, Prefix,HC,RP,[]).

write_loop(#state{entity=#endPoint{guid=#guId{prefix=Prefix}}, history_cache = HC,
                datawrite_period=P, reader_proxies=RP, push_mode = true} = S) ->
        erlang:send_after(P, self(), write_loop),
        send_changes(unsent, Prefix,HC,RP),
        S#state{reader_proxies = send_changes(requested,Prefix,HC,RP)};
write_loop(#state{entity=#endPoint{guid=#guId{prefix=Prefix}}, history_cache = HC,
                datawrite_period=P, reader_proxies=RP, push_mode = false} = S) ->
        erlang:send_after(P, self(), write_loop),
        S#state{reader_proxies = send_changes(requested,Prefix,HC,RP)}.

h_new_change(D,#state{last_sequence_number=Last_SN,entity=E,history_cache=C}=S) -> 
        SN = Last_SN + 1,
        Change = #cacheChange{kind=alive,writerGuid=E#endPoint.guid,
                instanceHandle=0,sequenceNumber=SN, data = D},
        {Change, S#state{last_sequence_number=SN}}.

h_update_matched_readers(Proxies,#state{reader_proxies=RP, history_cache=C} = S) ->
        Valid_GUIDS = [ G || #reader_proxy{guid=G} <- Proxies],
        ProxyStillValid = [ Proxy || #reader_proxy{guid=G}=Proxy <- RP, lists:member(G, Valid_GUIDS) ],
        NewProxies = [Proxy || #reader_proxy{guid=GUID}=Proxy <- Proxies, not lists:member(GUID,[ G || #reader_proxy{guid=G} <- RP])],
        % add cache changes to the unsent list for the new added locators
        Changes = rtps_history_cache:get_all_changes(C),
        S#state{reader_proxies= ProxyStillValid ++ reset_reader_proxies(Changes,NewProxies)}.

h_matched_reader_add(Proxy,#state{reader_proxies=RP, history_cache=C} = S) -> 
        Changes = rtps_history_cache:get_all_changes(C),
        S#state{reader_proxies=RP++reset_reader_proxies(Changes,[Proxy])}.

h_matched_reader_remove(Guid,#state{reader_proxies=RP} = S) -> 
        S#state{reader_proxies=[ P || #reader_proxy{guid=G}=P <- RP, G /= Guid]}.

reset_reader_proxies(Changes,RP) -> reset_reader_proxies(Changes,RP,[]).
reset_reader_proxies(_,[],NewRP) -> NewRP;
reset_reader_proxies(Changes,[RP| TL],NewProxies) ->  
        ChangesForReaders =[ #change_for_reader{change_key={WG,SN}, status=unacknowledged} || 
                #cacheChange{writerGuid=WG,sequenceNumber=SN} <- Changes ],
        N_RP = RP#reader_proxy{changes_for_reader=ChangesForReaders},
        reset_reader_proxies(Changes, TL, [N_RP|NewProxies]).

h_is_acked_by_all(_) -> false.
add_change_to_proxies(Key,Proxies,Push) -> add_change_to_proxies(Key,Proxies,[],Push).
add_change_to_proxies(_,[],NewPR,_) -> NewPR;
add_change_to_proxies(Key,[Proxy| TL],NewProxies, Push=true)->  
        ReaderChange = #change_for_reader{change_key = Key, status = unsent},
        ChangeList = Proxy#reader_proxy.changes_for_reader ++ [ReaderChange],
        New_PR = Proxy#reader_proxy{changes_for_reader = ChangeList},
        add_change_to_proxies(Key, TL, [New_PR|NewProxies],Push);
add_change_to_proxies(Key,[Proxy| TL],NewProxies, Push=false)->  
        ReaderChange = #change_for_reader{change_key = Key, status = unacknowledged},
        ChangeList = Proxy#reader_proxy.changes_for_reader ++ [ReaderChange],
        New_PR = Proxy#reader_proxy{changes_for_reader = ChangeList},
        add_change_to_proxies(Key, TL, [New_PR|NewProxies],Push).

h_on_change_available(Key,#state{history_cache=C,reader_proxies=RP, push_mode=Push}=S) -> 
        S#state{reader_proxies = add_change_to_proxies( Key, RP, Push)}.
update_for_acknack([], _, _, S) -> S;
update_for_acknack([#reader_proxy{changes_for_reader=Changes}=Proxy|_], Others, Missed, S) -> 
        ChangeKeys = [ K || #change_for_reader{change_key=K} <- Changes],
        NewChangeList = lists:map(fun(C) -> 
                {_,SN} = C#change_for_reader.change_key,
                case lists:member(SN, Missed) of
                        true -> C#change_for_reader{status = requested};
                        false -> case SN < lists:min(Missed) of
                                        true -> C#change_for_reader{status = acknowledged};
                                        false -> case SN > lists:max(Missed) of
                                                true -> C#change_for_reader{status = unacknowledged};
                                                false -> C
                                end
                        end
                end
                end, Changes),
        S#state{reader_proxies = Others ++ [Proxy#reader_proxy{changes_for_reader = NewChangeList}]}.
h_receive_acknack(_,#state{reader_proxies=[]} = S) -> S;
h_receive_acknack(#acknack{readerGUID=RID,sn_range=Single},#state{reader_proxies=RP,history_cache=Cache} = S)
        when is_integer(Single) ->
        Others = [ P || #reader_proxy{guid=G}=P <- RP, G /= RID],
        update_for_acknack([ P || #reader_proxy{guid=G}=P <- RP, G == RID], Others, [Single], S);
h_receive_acknack(#acknack{readerGUID=RID,sn_range=Range},#state{reader_proxies=RP,history_cache=Cache} = S) ->
        Others = [ P || #reader_proxy{guid=G}=P <- RP, G /= RID],
        update_for_acknack([ P || #reader_proxy{guid=G}=P <- RP, G == RID], Others, Range, S).
