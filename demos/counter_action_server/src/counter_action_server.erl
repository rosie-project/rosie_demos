-module(counter_action_server).
-export([start_link/0]).

-behaviour(gen_action_server_listener).
-export([on_execute_goal/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

% We are going to use Fibonacci.action, so we include its header to use record definitions of all of its components.
-include_lib("rosie_demos_msgs/src/_rosie/rosie_demos_msgs_counter_action.hrl").

-record(state, {ros_node, counter_action_server}).

-define(LOCAL_SRV, action).
-define(INITIAL_VALUE, 0).

start_link() ->
    gen_server:start_link({local, ?LOCAL_SRV}, ?MODULE, [], []).

% callbacks for gen_counter_action_server_listener
on_execute_goal(Pid, Goal) ->
    gen_server:cast(Pid, {on_execute_goal, Goal}).

% callbacks for gen_server
init(_) ->
    Node = ros_context:create_node("counter_action_server"),

    % The action uses our Node to create it's services and topics
    CounterActionServer = ros_context:create_action_server(
        Node,
        rosie_demos_msgs_counter_action,
        {?MODULE, self()}
    ),

    {ok, #state{ros_node = Node, counter_action_server = CounterActionServer}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast(
    {on_execute_goal, #rosie_demos_msgs_counter_send_goal_rq{goal_id = UUID, until = UNTIL}}, S
) ->
    io:format("Executing goal: ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    erlang:send_after(
        1000, self(), {next_step, UUID, [?INITIAL_VALUE + 1, ?INITIAL_VALUE], UNTIL - 1}
    ),
    {noreply, S}.

handle_info({next_step, UUID, L, Counter}, #state{counter_action_server = AS} = S) when
    Counter < 0
->
    List = lists:reverse(L),
    io:format("Returning result: ~p\n", [List]),
    ros_action_server:publish_result(AS, UUID, #rosie_demos_msgs_counter_get_result_rp{
        goal_status = 4, sequence = List
    }),
    {noreply, S};
handle_info(
    {next_step, UUID, [H | _] = L, Counter},
    #state{counter_action_server = AS} = S
) ->
    Next = H + 1,
    Step = [Next | L],
    io:format("Publishing feedback: ~p\n", [Next]),
    ros_action_server:publish_feedback(AS, #rosie_demos_msgs_counter_feedback_message{
        goal_id = UUID, current = Next
    }),
    erlang:send_after(1000, self(), {next_step, UUID, Step, Counter - 1}),
    {noreply, S}.
