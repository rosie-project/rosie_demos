# ROSIE DEMOS

These demos are very similar to some popular ROS2 example packages.
If you just read a ROS2 tutorial on how to write a node, you should be familiar with ROS Messages, Services, Actions and Parameters.

In this repo you will find good examples that show what feature we offer, and how the Erlang API works.

## Minimal Requirements

* [Erlang/OTP](https://www.erlang.org/downloads) [Version > 23] and the latest [Rebar3](https://rebar3.readme.io/)

We tested the demos only on Ubuntu and MacOS.
Windows could give problems when running multiple nodes on the same OS.
So if you are on Windows 10/11 we suggest to use [WSL](https://docs.microsoft.com/en-us/learn/modules/get-started-with-windows-subsystem-for-linux/).

## Additional ROS2 Requirements

* Any Working installation of ROS2 to test the interoperability

We suggest to use [ROS2 galactic](https://docs.ros.org/en/galactic/Installation.html). If you have another ROS2 distro then is best to set cyclone_dds as RMW_IMPLEMENTATION

Please see [Working-with-multiple-RMW-implementations](https://docs.ros.org/en/galactic/How-To-Guides/Working-with-multiple-RMW-implementations.html)

## Tests against ROS2

All examples can let you experiment how ROSiE is able to transparently talk to the official ROS2 nodes. We generate Erlang interfaces to serialize data in the same way ROS2 does. Plus, by sharing the same wire protocol, we can mix ROSiE and ROS2 nodes in the same network.

Here are some examples to test interoperability:

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
