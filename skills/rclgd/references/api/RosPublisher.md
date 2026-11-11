# RosPublisher

Hereda de: `RefCounted`

A ROS 2 Publisher for sending messages to a topic.

`RosPublisher` allows Godot to send `RosMsg` data to other ROS 2 nodes. It is created through `RosNode.create_publisher` and is tied to a specific topic and message type.

## Métodos

### `publish(msg: RosMsg) -> void`

Publishes the data contained in `msg` to the associated topic. The `RosMsg` type must match the type specified when the publisher was created.
