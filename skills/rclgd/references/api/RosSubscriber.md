# RosSubscriber

Hereda de: `RefCounted`

A ROS 2 Subscriber for receiving messages from a topic.

`RosSubscriber` allows Godot to listen for `RosMsg` data from other ROS 2 nodes. It is created through `RosNode.create_subscription`.
When a new message is received on the topic, the callback provided during creation is triggered, passing a `RosMsg` instance as its only argument.
The subscription remains active as long as this object is not freed.
