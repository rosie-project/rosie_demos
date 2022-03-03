# ROSIE DEMOS

## Tests against ROS2

### listener
    rebar3 shell --apps listener
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run demo_nodes_py talker

### talker
    rebar3 shell --apps talker
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run demo_nodes_py listener
### Turtle controller
Write commands on the shell to send them to the turtle on the screen.

    # LAUNCH:
    rebar3 shell --apps turtle_controller
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run turtlesim turtlesim_node
    # USE:
    turtle ! go.
    turtle ! back.
    turtle ! right.
    turtle ! left.
