-module(server_abort_goals).
-export([start_link/0]).

-behaviour(gen_action_server_listener).
-export([on_execute_goal/2]).

-behaviour(gen_server).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2]).

-include_lib("example_interfaces/src/_rosie/example_interfaces_fibonacci_action.hrl").

-record(state, {ros_node, action_server}).

-define(LOCAL_SRV, action_client).

start_link() ->
    gen_server:start_link({local, ?LOCAL_SRV}, ?MODULE, [], []).

% callbacks for gen_action_server_listener
on_execute_goal(Pid, Goal) ->
    gen_server:cast(Pid, {on_execute_goal, Goal}).


% callbacks for gen_server
init(_) ->
    Node = ros_context:create_node("minimal_action_server"),

    ActionServer = ros_context:create_action_server(Node,
                                         example_interfaces_fibonacci_action,
                                         {?MODULE, self()}),

    {ok, #state{ros_node = Node, action_server = ActionServer}}.

handle_call(_, _, S) ->
    {reply, ok, S}.

handle_cast({on_execute_goal,#example_interfaces_fibonacci_send_goal_rq{goal_id = UUID, order = ORDER}}, S) ->
    io:format("Executing goal: ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    erlang:send_after(3000, self(), {next_step, UUID, [1, 0], ORDER - 2}),
    {noreply, S}.


handle_info({next_step, UUID,[Last_1, Last_2 | _] = L, _},
            #state{action_server = AS} = S) ->
    Step = [Last_1 + Last_2 | L],
    List = lists:reverse(Step),
    io:format("Publishing feedback: ~p\n", [List]),
    ros_action_server:publish_feedback(AS, #example_interfaces_fibonacci_feedback_message{goal_id = UUID, sequence = List}),
    io:format("Aborting goal: ~p\n", [UUID#unique_identifier_msgs_u_u_i_d.uuid]),
    ros_action_server:abort_goal(AS, UUID),
    {noreply, S}.
