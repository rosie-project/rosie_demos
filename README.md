# ROSIE DEMOS

These demos are very similar to a few popular ROS2 example packages.
If you just read a ROS2 tutorial on how to write a node, you should be familiar with ROS Messages, Services, Actions and Parameters.

In this repo you will find good examples that show what features we offer, and how the Erlang API works.

## Minimal Requirements

* [Erlang/OTP](https://www.erlang.org/downloads) [Version > 23] and the latest [Rebar3](https://rebar3.readme.io/)

We tested the demos only on Ubuntu and MacOS.
Windows could give problems when running multiple nodes on the same OS.
So if you are on Windows 10/11 we suggest to use [WSL](https://docs.microsoft.com/en-us/learn/modules/get-started-with-windows-subsystem-for-linux/).

## Additional ROS2 Requirements

* Any working installation of ROS2 to test the interoperability

We suggest to use [ROS2 galactic](https://docs.ros.org/en/galactic/Installation.html). If you have another ROS2 distro then is best to set cyclone_dds as RMW_IMPLEMENTATION

Please see [Working-with-multiple-RMW-implementations](https://docs.ros.org/en/galactic/How-To-Guides/Working-with-multiple-RMW-implementations.html)

## Tests against ROS2

All examples can let you experiment how ROSiE is able to transparently talk to common ROS2 nodes. We generate Erlang interfaces to serialize data in the same way ROS2 does. Plus, by sharing the same wire protocol, we can mix ROSiE and ROS2 nodes in the same network.

Here are some examples to test the interoperability:

### Test using `rebar3`

#### `listener`

    rebar3 shell --apps listener
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run demo_nodes_py talker

#### `talker`

    rebar3 shell --apps talker
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run demo_nodes_py listener

#### Turtle controller

Write commands on the shell to send them to the turtle on the screen.

    # LAUNCH:
    rebar3 shell --apps turtle_controller
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run turtlesim turtlesim_node
    # USE:
    turtle ! go.
    turtle ! back.
    turtle ! right.
    turtle ! left.

### Test using `colcon-rebar3`

Install `colcon-rebar3` using:

    python -m pip install -U git+https://github.com/rosie-project/colcon-rebar3.git

Create a workspace and download the examples inside it

    mkdir -p ~/erlang_ws/src
    cd ~/erlang_ws
    curl -skL https://raw.githubusercontent.com/rosie-project/rosie_demos/main/ros2_erlang.repos | vcs import src

Type `colcon list` inside the workspace and you should see:

    ~/erlang_ws » colcon list
    rosie_demos	src/rosie_demos	(rebar3)

If the output is something like this now you can build your workspace using `colcon`:

    colcon build --rebar3-release-args="--all"

If the build terminate successfully, you have to activate the workspace and then you can use a ROSiE package like a ROS2 package

    source ~/erlang_ws/install/setup.bash

#### `listener` using ros2cli

    ros2 run rosie_demos listener foreground 
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run demo_nodes_py talker

#### `talker` using ros2cli

    ros2 run rosie_demos talker foreground
    RMW_IMPLEMENTATION=rmw_cyclonedds_cpp ros2 run demo_nodes_py listener
