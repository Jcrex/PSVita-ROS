# RosRequest

Hereda de: `RefCounted`

A handle for an asynchronous ROS 2 service request.

`RosRequest` is returned by `RosClient.async_send_request`. it acts as a promise or future, allowing you to check if a response has been received or await its completion.

## Métodos

### `get_response() -> RosMsg`

Returns the response message received from the service. Returns `null` if the request is not yet completed.

### `is_completed() -> bool`

Returns `true` if the service response has been received.

## Señales

### `completed(response: RosMsg) -> void`

Emitted when the service response is received. The `response` message is passed as an argument.
