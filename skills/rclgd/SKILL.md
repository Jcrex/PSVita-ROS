---
name: rclgd
description: "Use when writing, reviewing or debugging Godot 4 projects that talk to ROS 2 through rclgd (RosNode, RosMsg, RosPublisher/Subscriber, services, actions, TF, QoS, parameters, `ros2 rclgd` CLI, colcon `build_type: rclgd`), or when you need to look up the rclgd API or documentation. Includes scripts to fetch the official docs offline and dump the installed API."
---

# rclgd — ROS 2 nativo en Godot 4

**Qué es:** GDExtension (C++ sobre `rclcpp` + `ros_babel_fish`) que expone ROS 2 a GDScript.
Autor: Ozuba (MIT). Repo: `github.com/Ozuba/rclgd`. Docs: `rclgd.readthedocs.io/en/latest/`
(se generan de `docs/*.rst` y `rclgd/doc_classes/*.xml` del mismo repo).
**Versión estudiada:** fuente de `jazzy@fb12a65` / `rolling@bfbda5c` (2026-10-28): v3.0.0 + cambios
«Forthcoming» (**clases tipadas nativas**), Godot **4.7.1**. El apt `ros-jazzy-rclgd` 3.0.0 aún usa
clases sombra (`references/mensajes-y-tipos.md` §3–§4). Si trabajas con otra versión, **comprueba antes** (paso 0).

## 0. Antes de escribir código: documéntate (comandos)

```bash
S=skills/rclgd/scripts            # ruta de esta skill en el repo PSVita-ROS
$S/rclgd-docs.sh sync jazzy        # clon superficial de las docs oficiales (o rolling)
$S/rclgd-docs.sh version           # versión de rclgd y Godot fijada en esa rama
$S/rclgd-docs.sh cambios 40        # CHANGELOG: cambios incompatibles recientes
$S/rclgd-docs.sh indice            # páginas, clases y tests disponibles
$S/rclgd-docs.sh leer RosNode      # referencia de una clase (o: leer tutorials/basic_usage)
$S/rclgd-docs.sh ejemplos create_service   # código real que pasa los tests
$S/rclgd-docs.sh ramas             # ramas remotas y su commit (¿ha avanzado jazzy?)
```
- Si `rclgd.readthedocs.io` no es accesible, el clon de GitHub tiene **exactamente** el mismo contenido.
- Referencia ya convertida (`jazzy@fb12a65`): `references/api/INDEX.md` (una página por clase).
- API **instalada de verdad** (con Godot y rclgd en la máquina; sin verificar):
  `ros2 run rclgd godot --headless --path <proyecto> --script $S/dump_api.gd`.
- En una máquina con rclgd: `ros2 rclgd doctor` diagnostica toda la cadena.

## 1. Reglas que rompen programas si se olvidan
1. **Todo objeto `Ros*` es `RefCounted`: guarda la referencia** (variable miembro). Un
   `create_subscription`/`create_timer` sin guardar se libera y deja de funcionar en silencio.
2. **Hilos:** suscripciones, timers, clientes y servidores de acción → hilo principal (seguro tocar la
   escena). **Callbacks de servidor de servicio y `goal_callback` de acciones → hilo del executor**:
   rellena la respuesta y usa `call_deferred` para cualquier cambio en la escena.
3. `rclgd.init(args)` una vez antes de crear nodos. En proyectos de `ros2 rclgd create` lo hace el
   autoload `ROS` (`addons/rclgd/ros_init.gd`), que añade `ros/parameters/*` de los ajustes del proyecto
   como `-p clave:=valor`. No llames a `init` otra vez (comprueba `rclgd.ok()`).
4. `RosNode.new()` + `init(nombre, namespace="")` antes de usarlo; `get_logger()` solo tras `init`.
5. **QoS debe casar:** un publicador *best effort* (sensores) no casa con un suscriptor *reliable*.
6. **Ejes:** Godot (-Z adelante, +X derecha, +Y arriba) ≠ ROS REP-103 (+X adelante, +Y izquierda,
   +Z arriba). Usa `rclgd.godot_to_ros_vector/quat` y `ros_to_godot_*`
   (`ros = Vector3(-g.z, -g.x, g.y)`). TF broadcaster/listener ya convierten solos.
7. **Arrays de mensajes:** se leen como copia; para modificar, asigna el array completo (`msg.ranges = arr`); visto en el código fuente (`ros_msg.cpp`, docs/17 del repo PSVita-ROS).
8. Servicio: el cliente hace `var r = await client.async_send_request(req).completed`.
9. **Tipos:** cada `<depend>` de `res://package.xml` da clases nativas (`RosGeometryMsgsTwist`...) que se
   fijan **al cargar**: tras añadir una dependencia, recarga el proyecto. Exportando, incluye
   `package.xml` en el filtro de no-recursos. No hay `addons/rclgd/gen` ni plugin (`mensajes-y-tipos.md` §2).

## 2. Esqueleto mínimo correcto

```gdscript
extends Node
var node: RosNode
var pub: RosPublisher
var sub: RosSubscriber
var timer: RosTimer

func _ready() -> void:
    if not rclgd.ok():            # el autoload ROS normalmente ya lo hizo
        rclgd.init(OS.get_cmdline_user_args())
    node = RosNode.new()
    node.init("mi_nodo", "/robot1")
    pub = node.create_publisher("~/chatter", RosStdMsgsString)   # o "std_msgs/msg/String"
    sub = node.create_subscription("/odom", "nav_msgs/msg/Odometry", _on_odom)
    timer = node.create_timer(0.5, _tick)

func _tick() -> void:
    var msg := RosStdMsgsString.new()     # requiere std_msgs en package.xml (create --dependencies std_msgs)
    msg.data = "hola"
    pub.publish(msg)

func _on_odom(msg: RosNavMsgsOdometry) -> void:   # o msg: RosMsg si el tipo no está en package.xml
    print(msg.pose.pose.position.x)   # acceso anidado directo
```

## 3. Mapa de la API (detalle en `references/api/`)
| Necesito… | Usa |
|---|---|
| Contexto ROS, ejes, sim time, logger sin nodo | singleton `rclgd` |
| Nodo, fábricas, parámetros, `now()`, grafo | `RosNode` |
| Mensaje tipado / dinámico | clases nativas `Ros<Pkg><Tipo>.new()` (de `package.xml`); `RosMsg.from_type` para cualquier tipo; `get_member/set_member` |
| Topics | `create_publisher` → `RosPublisher.publish`; `create_subscription` → `RosSubscriber` |
| Calidad de servicio | `RosQoS` (`set_reliability`, `set_history`, `set_depth`, `set_durability`…) |
| Periódico en reloj ROS | `create_timer` → `RosTimer` (sigue `/clock` con `use_sim_time`) |
| Servicios | `create_client` → `RosClient`/`RosRequest` (`await .completed`); `create_service` → `RosService` |
| Acciones | `create_action_client` → `RosActionClient`/`RosGoalHandle`; `create_action_server` → `RosActionServer`/`RosServerGoalHandle` |
| TF | `create_tf_broadcaster` → `send_transform(t, child, parent, static, stamp)`; `create_tf_listener(cache_s)` → `lookup_transform(target, source, time=null)` |
| Logs | `node.get_logger()` → `RosLogger` (consola + `/rosout`; filtros `{"once":true}`, `{"throttle_duration_sec":1.0}`, `{"skip_first":true}`) |

## 4. Referencias de esta skill (leer según la tarea)
- `references/conceptos.md` — hilos, ciclo de vida, sim time, QoS, TF/ejes, parámetros y tipos.
- `references/tooling.md` — instalación (apt/fuente/docker), `ros2 rclgd`, colcon, lanzamiento, tests headless.
- `references/mensajes-y-tipos.md` — `RosMsg` dinámico, clases tipadas nativas (actual), migración desde
  las clases sombra (3.0.0) y cómo saber cuál tienes.
- `references/versiones.md` — ramas, fijación, cambios incompatibles y cómo detectar uno nuevo.
- `references/errores-comunes.md` — síntomas → causa → arreglo.
- `references/api/*.md` — referencia de las 17 clases (generada de los XML oficiales).
- Para patrones de escenas/nodos Godot (robot, sensores, HMI): skill **`godot4-ros-scripting`**.
- Para la PS Vita (sin rclcpp; módulo `ros2_vita`): skill **`ros2-vita-godot`**.

## 5. Si algo no cuadra
1. `rclgd-docs.sh cambios` y `ramas`: puede que la API haya cambiado (p. ej. las clases nativas
   eliminaron las clases sombra y `RosMsg.gen_editor_support`; el apt 3.0.0 aún las tiene).
2. `rclgd-docs.sh ejemplos <método>`: los tests (`rclgd/test/project/tests/*.gd`) son la verdad ejecutable.
3. Regenera la referencia: `rclgd-docs.sh api skills/rclgd/references/api` y anota la versión en `references/versiones.md`.
