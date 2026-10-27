# Godot 4 esencial para apps ROS (4.7.x; comprobar con `godot --version`)

## Ciclo de vida de un nodo
| Callback | Cuándo | Uso típico con ROS |
|---|---|---|
| `_init()` | al construir el objeto | nada de ROS (aún sin árbol) |
| `_enter_tree()` | entra al árbol | — |
| `_ready()` | hijos listos, una vez | crear `RosNode`, publishers, subs, timers |
| `_process(delta)` | cada fotograma | UI, cosmética |
| `_physics_process(delta)` | cada tick (60 Hz por defecto) | control, odometría |
| `_integrate_forces(state)` (RigidBody) | dentro del paso de física | teleportar, fijar velocidades |
| `_exit_tree()` / `_notification(NOTIFICATION_EXIT_TREE/PREDELETE)` | sale/se destruye | parar hilos antes de que ROS se apague |
| `static func _static_init()` | al cargar el script | el autoload `ROS` inicializa rclgd aquí |

## GDScript 4 que aparece en el código ROS
- Tipado: `var x: float`, `var m := RosMsg.from_type(...)`, `func f(a: int) -> void`, `Array[RosMsg]`.
- Anotaciones: `@export`, `@export_group("ROS 2")`, `@onready var l: Label = %Status` (`%` = nombre único),
  `@tool` (corre en el editor), `@icon(...)`, `@abstract` (clase base no instanciable),
  `@warning_ignore("integer_division")`, `class_name Roomba`.
- Señales: `signal bumper_changed(pressed: bool)`; `bumper_changed.connect(func(p): ...)`; `bumper_changed.emit(true)`.
- Callables y lambdas: `node.create_timer(0.1, _publish)`, `func(): return x`, `f.call_deferred(args)`, `f.callv(arr)`.
- `await`: `await get_tree().physics_frame`, `await get_tree().process_frame`,
  `await get_tree().create_timer(0.5).timeout`, `await request.completed`.
- `match valor: "a": ...`.
- Escenas: `preload("res://x.tscn").instantiate()` + `add_child(n)`; `queue_free()`.

## Transformaciones
- `Transform3D(basis, origin)`, `global_transform`, `transform` (relativa al padre), `affine_inverse()`,
  `basis.get_rotation_quaternion()`, `basis.get_euler().y` (guiñada alrededor de +Y = guiñada ROS en +Z).
- Velocidad en el marco del robot: `global_basis.inverse() * linear_velocity`.
- Adelante en Godot = `-basis.z`.

## Hilos
- `Thread.new().start(callable)`, `wait_to_finish()`; `Mutex.lock()/unlock()`; `Semaphore.post()/wait()`.
- El árbol de escena **no** es seguro entre hilos; `call_deferred` para volver al principal.
- `WorkerThreadPool` existe (en la Vita limitado a 2 hilos).

## UI (HMI)
- `Control` raíz; `Button.button_pressed` (mantener pulsado), señal `pressed` conectada en el editor
  (pestaña Signals) a `_on_dock_pressed`; `Label.text`, `HSlider.value`, `TextureRect.texture`, `modulate`.

## Proyecto y ajustes
- `project.godot`: `[autoload]`, `[editor_plugins]`, `config/features`, renderer
  (`gl_compatibility` para CI/headless o GPUs débiles; obligatorio en la Vita).
- `ProjectSettings.get_setting_with_override("ros/parameters/x")`; `OS.get_cmdline_user_args()`
  (argumentos tras `--`).
- `Engine.is_editor_hint()` para no ejecutar ROS dentro del editor en scripts `@tool`.

## Headless y CLI del motor
- `godot --headless --path <proyecto> --script res://runner.gd -- <args>`; `--import` / `--editor --quit`;
  `--export-release "<preset>" <salida>`; `--doctool <dir>`; `--version`.
