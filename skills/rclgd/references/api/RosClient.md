# RosClient

Hereda de: `RefCounted`

A ROS 2 Service Client for making requests to a service server.

`RosClient` allows Godot to act as a client for ROS 2 services. It is created through `RosNode.create_client` and is used to send requests and receive responses asynchronously.
Communication follows a request-response pattern: the client sends a `RosMsg` request and receives a `RosMsg` response. Use the `async_send_request` method to send a request which will return
a `RosRequest` object, which acts as a handle for the request. Use this handle to wait for the response or get it when ready.

## Métodos

### `async_send_request(request: RosMsg) -> RosRequest`

Sends a service `request` asynchronously. Returns a `RosRequest` object that can be used to track the progress of the request and retrieve the response.

### `create_request() -> RosMsg`

Creates and returns an empty `RosMsg` of the correct type for this client's service requests.

### `wait_for_service(timeout_sec: float) -> bool`

Blocks until the service server is available or the `timeout_sec` is reached. Returns `true` if the service is available.

### `wait_for_service_async(timeout_sec: float) -> void`

Asynchronously waits for the service server to become available up to `timeout_sec` seconds. Emits the `service_available` signal when the service state changes or the timeout is reached.

## Señales

### `service_available(available: bool) -> void`

Emitted when the service server becomes available or when an asynchronous wait times out.
