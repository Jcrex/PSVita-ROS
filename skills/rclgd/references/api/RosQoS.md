# RosQoS

Hereda de: `Resource`

Configuration for ROS 2 Quality of Service (QoS) profiles.

`RosQoS` allows configuring the Quality of Service (QoS) settings for ROS 2 publishers and subscribers. QoS profiles control how messages are handled across the network, allowing developers to tune the balance between reliability and performance.
Commonly used for ensuring that critical data is delivered reliably or for optimizing high-frequency sensory data where some packet loss is acceptable.

## Propiedades

### `deadline_seconds: float = 0.0`

The maximum amount of time (in seconds) expected between messages being published to or received from a topic. If a message is not sent or received within this duration, a QoS event is triggered. A value of `0.0` disables the deadline.

### `depth: int = 10`

The size of the message queue. For `KEEP_LAST` history, this determines how many messages are buffered before old entries are discarded.

### `durability: int = 0`

Determines whether messages are persisted by the publisher for late-joining subscribers. See `Durability` for options.

### `history: int = 0`

Determines how messages are buffered in the queue. See `History` for options.

### `lease_duration_seconds: float = 0.0`

The maximum amount of time a publisher may go without asserting liveliness before subscribers consider it lost. Only meaningful when `liveliness` is not `SYSTEM_DEFAULT`. A value of `0.0` leaves the lease duration at the RMW default (infinite).

### `lifespan_seconds: float = 0.0`

The maximum amount of time a message is considered "valid" after being published. Messages older than this duration will be removed from the publisher's queue and ignored by subscribers. A value of `0.0` means messages live forever.

### `liveliness: int = 2`

Determines how a publisher reports that it is still alive. See `Liveliness` for options. Defaults to `SYSTEM_DEFAULT`, which leaves the policy to the underlying RMW implementation.

### `reliability: int = 0`

Determines whether message delivery is guaranteed. See `Reliability` for options.

## Constantes

- `RELIABLE = 0` (enum `Reliability`) — The publisher will attempt to retransmit messages until they are acknowledged by the subscriber. Recommended for critical data.
- `BEST_EFFORT = 1` (enum `Reliability`) — The publisher will send messages once without confirmation. Recommended for high-frequency data where occasional loss is acceptable.
- `VOLATILE = 0` (enum `Durability`) — Messages are not persisted. Late-joining subscribers will only receive messages published after they connect.
- `TRANSIENT_LOCAL = 1` (enum `Durability`) — The publisher retains a set of messages (defined by `depth`) for discovery by late-joining subscribers.
- `KEEP_LAST = 0` (enum `History`) — Only the last `depth` messages are kept in the queue.
- `KEEP_ALL = 1` (enum `History`) — All messages are kept until they are processed, subject to available resources.
- `AUTOMATIC = 0` (enum `Liveliness`) — The system will automatically manage liveliness based on the connection status.
- `MANUAL_BY_TOPIC = 1` (enum `Liveliness`) — Liveliness must be manually asserted by the user for each topic.
- `SYSTEM_DEFAULT = 2` (enum `Liveliness`) — Uses the default liveliness policy of the underlying RMW implementation.
