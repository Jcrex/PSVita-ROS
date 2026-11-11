# RosLogger

Hereda de: `RefCounted`

A named ROS 2 logger, with the same API as rclpy's logger.

`RosLogger` writes messages through the ROS 2 logging system, so they get the standard severity formatting, honour `--ros-args --log-level` and `RCUTILS_CONSOLE_OUTPUT_FORMAT`, and can be inspected with ROS tooling. Its API mirrors rclpy's logger: `debug`, `info`, `warning`, `error` and `fatal` take the message and an optional `Dictionary` standing in for rclpy's keyword arguments.
It cannot be created with `new()`; get one from `RosNode.get_logger` (published on `/rosout`), from `get_child`, or from `rclgd.get_logger` (console only, no node needed).

```gdscript
var logger := ros_node.get_logger()
logger.info("Simulation started")
logger.warning("Wheel slip detected", {"throttle_duration_sec": 1.0})
logger.debug("First contact", {"once": true})

var lidar_logger := logger.get_child("lidar")
lidar_logger.set_level(RosLogger.DEBUG)

```

**Filters:** The keyword dictionary accepts `once` (log only the first time), `skip_first` (skip the first time) and `throttle_duration_sec` (log at most once per period, measured on a steady clock). `once` cannot be combined with the others. As in rclpy, filter state is kept per call site, so the same line is throttled independently of other lines. Script call stacks are not tracked in release exports unless `debug/settings/gdscript/always_track_call_stacks` is enabled; filters then key on the message text instead (with a one-time warning), and log locations are omitted.

## Métodos

### `debug(message: String, kwargs: Dictionary = {}) -> bool`

Logs `message` at `DEBUG` severity. See `log` for `kwargs` and the return value.

### `error(message: String, kwargs: Dictionary = {}) -> bool`

Logs `message` at `ERROR` severity. See `log` for `kwargs` and the return value.

### `fatal(message: String, kwargs: Dictionary = {}) -> bool`

Logs `message` at `FATAL` severity. See `log` for `kwargs` and the return value.

### `get_child(name: String) -> RosLogger` *(const)*

Returns a child logger named `<this logger's name>.<name>`. Its level can be set independently, and it inherits this logger's level while unset. A child of a node's logger is also published on `/rosout`. `name` must not be empty.

### `get_effective_level() -> RosLogger.LoggingSeverity` *(const)*

Returns the severity threshold this logger actually uses: its own level if set, otherwise the nearest ancestor's, otherwise the default level (`INFO` unless changed).

### `info(message: String, kwargs: Dictionary = {}) -> bool`

Logs `message` at `INFO` severity. See `log` for `kwargs` and the return value.

### `is_enabled_for(severity: RosLogger.LoggingSeverity) -> bool` *(const)*

Returns `true` if a message of `severity` would be emitted by this logger. Use it to skip building expensive messages.

### `log(message: String, severity: RosLogger.LoggingSeverity, kwargs: Dictionary = {}) -> bool`

Logs `message` at `severity`, which must be `DEBUG`, `INFO`, `WARN`, `ERROR` or `FATAL`. `kwargs` takes the optional filters `once`, `skip_first` and `throttle_duration_sec` (see the class description). Any other key, or a value of the wrong type, is an error.
Returns `true` if the message was emitted, and `false` if it was below the logger's level or suppressed by a filter.

### `set_level(level: RosLogger.LoggingSeverity) -> void`

Sets the minimum severity this logger emits. Pass `UNSET` to inherit the level from its ancestors again. Equivalent to `--ros-args --log-level <name>:=<level>`.

### `warning(message: String, kwargs: Dictionary = {}) -> bool`

Logs `message` at `WARN` severity. See `log` for `kwargs` and the return value.

## Propiedades

### `name: String`

The logger's fully qualified name, e.g. `my_node` or `my_node.lidar`. Read-only.

## Constantes

- `UNSET = 0` (enum `LoggingSeverity`) — No level set; the logger inherits its level from its ancestors.
- `DEBUG = 10` (enum `LoggingSeverity`) — Debug severity.
- `INFO = 20` (enum `LoggingSeverity`) — Info severity. This is the default level.
- `WARN = 30` (enum `LoggingSeverity`) — Warning severity.
- `ERROR = 40` (enum `LoggingSeverity`) — Error severity.
- `FATAL = 50` (enum `LoggingSeverity`) — Fatal severity.
