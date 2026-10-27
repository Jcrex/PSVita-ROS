# RosService

Hereda de: `RefCounted`

A ROS 2 Service Server for handling requests from service clients.

`RosService` allows Godot to act as a server for ROS 2 services. It is created through `RosNode.create_service`.
When a client sends a request to the service, the callback provided during creation is triggered.
The callback signature should be: `func my_service_callback(request: RosMsg, response: RosMsg):`.
The `request` argument contains the incoming data, and the `response` argument is an empty message that should be populated by the callback before it returns.
The service remains active as long as this object is not freed.
**Threading warning:** Unlike subscription and timer callbacks (which are deferred to the main thread), the service callback runs synchronously on the ROS executor thread, because the response must be populated before it is returned to the client. Keep service callbacks self-contained: don't touch the SceneTree or other nodes' state from them without your own synchronization (use `call_deferred` for side effects that don't influence the response). In physics-synchronous mode (`use_separate_thread:=false`) callbacks run on the main thread and this caveat does not apply. For long-running work, prefer an action server (`RosActionServer`), whose execute callback runs on the main thread.
