# 17 — Estado del arte Godot + ROS2: `rclgd` y `roomba_ws` (y qué significa para la Vita)

**Fecha:** 2026-10-27 (ROSCon) · **Estado:** estudio del código fuente completo de
dos repositorios públicos, leídos desde un clon local (no por resúmenes):

| Repo | Commit estudiado | Qué es |
|---|---|---|
| [Ozuba/rclgd](https://github.com/Ozuba/rclgd) | `4d0a8b3` (2026-10-22), paquete v3.0.0, MIT | Librería cliente ROS 2 nativa para Godot (GDExtension sobre `rclcpp`) + tipo de build de colcon + CLI `ros2 rclgd` |
| [Ozuba/roomba_ws](https://github.com/Ozuba/roomba_ws) | `8332acb` (2026-10-26) | Taller de 90 min: un Roomba simulado en Godot conectado a ROS 2 + sensores + HMI |

Marcas: **[V]** verificado en el código/documentos leídos · **[I]** inferencia
mía para la Vita · **[?]** por comprobar. Esto **corrige** `docs/12` en varios
puntos (§9).

---

## 1. Resumen ejecutivo

1. `rclgd` ya es lo que `docs/12` llamaba "vía A", pero **mucho más completo y
   vivo de lo que indicaba el índice ROS** ("UNMAINTAINED"): hay v3.0.0, ramas
   para **Jazzy, Kilted, Lyrical y Rolling** con CI, tests de sistema headless,
   documentación completa, CLI y empaquetado `apt` (`ros-jazzy-rclgd`) **[V]**.
2. No usa rosbridge ni WebSockets: **`rclcpp` dentro de Godot**, y cualquier
   mensaje se maneja en ejecución gracias a **`ros_babel_fish`** (introspección
   de type support) **[V]**. Esa es la pieza que **no existe en la Vita**.
3. Su valor para este proyecto es **la API y los patrones**, no el código:
   `rclcpp`, `tf2_ros`, `ros_babel_fish` y GDExtension son imposibles en la Vita.
   Lo reutilizable es el contrato GDScript (nombres, firmas, reglas de hilos y
   QoS), la convención de ejes Godot↔ROS y el flujo de herramientas.
4. **Hallazgo que cambia el plan:** `rclgd` es **solo Godot 4.7** y su API usa
   `Callable`, lambdas, `await` y tipos de GDScript 2. Los scripts del taller
   **no pueden ejecutarse en Godot 3.5** sin reescribirse. Para que "el mismo
   script corra en el PC y en la Vita" hace falta **Godot 4 en la Vita**
   (`godot4-vita`, 4.8-dev7). Esto obliga a reevaluar el ADR 0008 (§9, §10).
5. Pieza nueva que resulta imprescindible: un **codec CDR genérico guiado por
   esquema** (`msg-schema`), equivalente en la Vita a `ros_babel_fish`. Los
   esquemas se generarían en el PC a partir de las definiciones reales.

---

## 2. Anatomía del repositorio `rclgd` **[V]**

```
rclgd/                (paquete ament_cmake, GDExtension librclgd.so)
  src/rclgd/          rclgd, ros_node, ros_msg, ros_publisher, ros_subscriber,
                      ros_client/service, ros_action_client/server, ros_tf_*,
                      ros_timer, ros_qos, ros_logger, utils/ (tipos, TF, macros)
  doc_classes/*.xml   documentación embebida en el editor de Godot
  test/               proyecto Godot headless + runner.gd (27 tests, 9 ficheros)
  godot-cpp/          submódulo (rama que coincide con Godot 4.7)
colcon_rclgd/         plugin de colcon: build_type "rclgd" para proyectos Godot
rclgd_cli/            `ros2 rclgd create | editor | doctor | list` + plantilla
docs/                 Sphinx (Read the Docs); make_rst.py genera clases desde XML
.github/workflows/    CI por distro: setup-ros + action-ros-ci
```

Decisiones de ingeniería que merece la pena copiar:
- **Versión de Godot fijada con SHA-512**: el CMake descarga el binario de
  Godot (4.7.1) y verifica el hash antes de instalarlo en `lib/rclgd/godot-bin`;
  `godot_version` queda en `share/` para que la CLI lo muestre.
- **El proyecto Godot es un paquete ROS**: `package.xml` con
  `<build_type>rclgd</build_type>`; `colcon build` copia (o enlaza con
  `--symlink-install`) el proyecto a `install/share/<pkg>`, registra el paquete
  en el índice ament, crea un *shim* `install/lib/<pkg>/<pkg>` y lanza una
  **importación headless** de assets. `ros2 run pkg pkg --ros-args ...` funciona
  como cualquier nodo; el shim inserta el `--` que Godot necesita para pasar los
  `--ros-args` a GDScript.
- **Autoload `ROS`** (`ros_init.gd`): inicializa el contexto ROS antes de cargar
  ninguna escena, traduce los ajustes de proyecto `ros/parameters/*` a
  `-p clave:=valor` (sin pisar los de la línea de comandos) y llama a
  `rclgd.shutdown()` al salir.
- **Tests de sistema headless**: copian un proyecto, enlazan la librería,
  fijan `ROS_DOMAIN_ID` aleatorio y `ROS_AUTOMATIC_DISCOVERY_RANGE=LOCALHOST`
  para aislar ejecuciones en paralelo y publican en bucle hasta recibir (el
  *discovery* es asíncrono).

---

## 3. Arquitectura interna **[V]**

### 3.1 Hilos y ciclo de vida
- Singleton `rclgd` (`Object`) crea un **nodo oculto `rclgd_<pid>`** (para
  parámetros de proceso y `/clock`) y un **executor**:
  `MultiThreadedExecutor` en un hilo propio (por defecto) o
  `SingleThreadedExecutor` girado con `spin_some()` en cada *physics tick*
  (`-p use_separate_thread:=false`, determinista).
- **Dónde corre cada callback**:

  | Evento | Hilo |
  |---|---|
  | Suscripción, timer, cliente/servidor de acciones (ejecución) | **Principal** (`call_deferred`; si ya es el principal, llamada directa) |
  | Callback de **servicio servidor** y de **aceptación de goal** | **Hilo del executor** (hay que responder síncronamente) |
  | Cambio de parámetro | Señal `parameter_changed`, diferida |

- Los objetos (`RosNode`, `RosPublisher`, `RosTimer`...) son **`RefCounted`**:
  viven mientras alguien guarde una referencia. Soltar una suscripción o un
  timer la cancela en silencio (la advertencia más repetida de la doc).
- Los callbacks capturan el `Callable` **por valor** (nunca `this`) para no
  dejar punteros colgando si GDScript libera el objeto en pleno callback.
- `SIGINT/SIGTERM`: el *handler* solo levanta un flag; el `quit()` se hace en el
  hilo principal en el siguiente *physics tick* para destruir bien los
  participantes DDS.
- **Tiempo simulado**: `use_sim_time:=true` (seguir `/clock`) y
  `publish_sim_time:=true` (Godot es la fuente de `/clock`, escalado por
  `Engine.time_scale`); los `RosTimer` usan el reloj del nodo, no el del SO.
- Monitor de rendimiento propio en el editor ("ROS/Spin Time") y macros de error
  `RCLGD_FAIL_*` que imprimen con enlace al C++ y pausan el depurador de GDScript
  (ajuste `rclgd/debug/break_on_error`).

### 3.2 Mensajes: `RosMsg` (el corazón)
- Envuelve un `CompoundMessage` de babel_fish (árbol de nodos hasta primitivas).
- Acceso como **propiedades dinámicas** (`_get/_set/_get_property_list`):
  `msg.pose.pose.position.x = 1.0`. Conversión **perezosa y cacheada**:
  solo se convierte el campo que se lee.
- **Subobjetos que comparten buffer** con el padre (`shared_ptr` alias) para que
  `msg.header.stamp = x` escriba en el mensaje correcto. Los **arrays se copian**:
  hay que asignar el array entero (`msg.ranges = arr`), no elementos.
- Mapeo Variant↔ROS con **rutas rápidas** `memcpy` hacia `PackedByteArray`,
  `PackedFloat32/64Array`, `PackedInt32/64Array`; enteros pequeños →
  `PackedInt32Array`; strings → `PackedStringArray`; el resto → `Array`.
- **Clases "sombra" tipadas** generadas en GDScript (`gen_editor_support`): un
  `class_name RosGeometryMsgsTwist extends RosMsg` por tipo, con
  `const ROS_TYPE_NAME = "geometry_msgs/msg/Twist"` y propiedades con `get/set`
  hacia `get_member/set_member`. El *addon* las genera al abrir el editor para
  los paquetes listados en `package.xml` (leyendo el índice ament). Así el editor
  autocompleta y comprueba tipos, y `create_publisher(topic, RosGeometryMsgsTwist)`
  acepta la **clase** además del nombre de tipo (lee `ROS_TYPE_NAME`).
- Nombre de clase: `std_msgs::msg::Header` → `RosStdMsgsHeader`.

### 3.3 TF y ejes
- `RosTfBroadcaster.send_transform(transform, child, parent, is_static)` y
  `RosTfListener.lookup_transform(target, source, time, timeout)` devuelven
  `Transform3D` de Godot ya convertido. Buffer real de `tf2` (con historial).
- **Convención de ejes** (REP-103 ↔ Godot), una sola fuente de verdad:
  `ros = (-g.z, -g.x, g.y)`, `godot = (-r.y, r.z, -r.x)`, cuaterniones
  permutados igual; expuesta como `rclgd.godot_to_ros_vector/quat` y
  `ros_to_godot_*`.
- `~frame` expande al espacio de nombres del nodo y se quita cualquier `/` inicial.

### 3.4 QoS, acciones, servicios, parámetros, logging
- Sin `RosQoS` ⇒ perfil por defecto `KeepLast(10)` **reliable**; sensores usan
  `best_effort`, `KeepLast(5)`, `volatile` (como `SensorDataQoS`) y **el suscriptor
  debe ser best-effort también** o no hay emparejamiento.
- Servicios cliente: `await client.async_send_request(req).completed`;
  `wait_for_service(_async)`. Acciones: `create_action_client/server`,
  `GoalHandle` con señales `accepted/rejected/feedback/completed`; el servidor
  recibe un `RosServerGoalHandle` en el hilo principal y avanza con `await
  get_tree().physics_frame` (nunca bloquea).
- Parámetros tipados por su valor por defecto; `declare_parameter`,
  `get_parameter`, `set_parameter`, señal `parameter_changed`.
- `RosLogger` con la API de `rclpy` (filtros `once`, `throttle_duration_sec`,
  `skip_first` por llamada), hijos con nombre, niveles; publica en `/rosout`.
- Introspección: `get_topic_names_and_types`, `count_publishers/subscribers`.

---

## 4. Lo que enseña `roomba_ws` **[V]**

Estructura: `roomba_rclgd_starter` (mundo y física, sin ROS), `roomba_rclgd`
(resultado), `roomba_hmi` (extra), `docs/tutorial/00–09`, contenedor Docker
(Ubuntu 24.04 + Jazzy + rclgd) y un script `bump_and_turn.py`.

Patrones del robot (`roomba.gd`, ~300 líneas):
1. **Un `RosNode` por robot**, creado en `_ready()`; `/cmd_vel` con *timeout*
   (0.5 s sin órdenes ⇒ parar, como las bases reales); la callback solo llama a
   `drive()`.
2. **Odometría + TF**: pose relativa al origen de `odom`, conversión de ejes con
   los *helpers* de `rclgd`, twist en el frame hijo; `map→odom` estático.
3. **Estado a 10 Hz con `RosTimer`** y además por señal de Godot (`bumper_changed`).
4. **Servicios**: rellenar `res` en el acto; **no tocar el árbol de escena** en la
   callback (hilo del executor): leer antes lo necesario y usar `call_deferred`.
5. **Parámetros** con valor por defecto exportado y relectura tras `declare_parameter`
   (gana el `-p`).
6. **Acción `RotateAbsolute`**: *preemption* comparando el `goal_handle` actual,
   cancelación con `is_cancel_requested()`, avance con `await physics_frame`.

Addon `rclgd-sensors` (lo más reutilizable como *diseño*):
- `RosSensor` (clase base): nodo propio, TF **estático** respecto al padre
  (`~base_link`), QoS de sensor, `_start_sampling(rate)` con **fase aleatoria** para
  que sensores del mismo ritmo no publiquen en el mismo fotograma.
- `PublishQueue`: **hilo de publicación con cola acotada (3)** y orden estricto de
  captura; descarta lo más antiguo si se atrasa; `stop()` antes de cerrar ROS
  (publicar tras `shutdown` aborta el proceso). *Es el mismo problema y casi la
  misma solución que nuestro `msg-ring`.*
- `RosCamera`: `SubViewport` oculto, lectura asíncrona de GPU
  (`texture_get_data_async`), sellos de tiempo propagados como enteros
  (no `RosMsg`, que se liberaría tras descargar la librería), `Image` + `CameraInfo`.
- `RosLidar2D` (rayos de física repartidos por *physics ticks* con distorsión de
  movimiento), `RosLidar` 3D por compute shaders, `RosImu` (derivada de velocidad en
  el punto de montaje, ruido blanco + deriva), `RosGps`, `RosFisheyeCamera`.
- Detalles de calidad: covarianzas no nulas (GTSAM), REP-117 (±inf), cuidado con
  que la IMU publica por *physics step* (elegir ritmos que dividan 60).

**HMI (`roomba_hmi`)** — el caso más cercano a la Vita: un `Control` con
`TextureRect` (cámara), flechas `Button` que **publican `/cmd_vel` a 10 Hz solo
mientras se mantienen pulsadas** (y un único stop al soltar, para convivir con
otros nodos), `HSlider` de velocidad y un botón que hace
`await client.async_send_request(...).completed`. La imagen entra con
`Image.create_from_data(w, h, false, FORMAT_RGBA8, msg.data)`. Se construye casi
todo con el ratón en el editor y ~90 líneas de GDScript.

---

## 5. Qué es reutilizable en la Vita y qué no

| Pieza de rclgd | En la Vita | Nota |
|---|---|---|
| Contrato GDScript (`RosNode`, `create_*`, `RosMsg`, `RosQoS`, `RosTimer`...) | **Adoptar tal cual** | objetivo: mismo script en PC y Vita |
| Reglas de hilos (callbacks al principal; servicios en hilo ROS) | **Adoptar** | cola `msg-ring` + `call_deferred` |
| `~frame`, helpers de ejes, REP-103 | **Adoptar** | trivial, sin dependencias |
| Clases sombra + `ROS_TYPE_NAME` | **Adoptar** | generar en el PC; van al `.pck` |
| `ros_babel_fish` (introspección) | **Imposible** | sustituir por `msg-schema` (esquemas del PC + codec genérico) |
| `rclcpp`/executor | **Imposible** | micro-ROS XRCE + hilo de sesión |
| `tf2_ros` buffer con historial | **Parcial** | `tf-tree` (último valor); documentar la diferencia |
| Parámetros del nodo (servicios `/param`) | **Local** | XRCE-DDS no trae servidor de parámetros; solo locales + ajustes de proyecto |
| Servicios | **Posible** | DDS-RPC (requester/replier) del cliente XRCE **[?]** |
| Acciones | **Más adelante** | cliente XRCE no las trae; habría que montarlas sobre topics/servicios |
| `/rosout` y `RosLogger` | **Posible** | publicar `rcl_interfaces/Log` |
| GDExtension/godot-cpp | **Imposible** | módulo estático (ADR 0008) |
| `colcon`/CLI/`apt` | **PC** | la Vita no lo necesita; el PC genera `.pck`/`.vpk` |
| Sensores simulados (`rclgd-sensors`) | **No aplica** | la Vita *consume* sensores; el Obj. 5 *publica* los reales |
| `PublishQueue` | **Adoptar idea** | = `msg-ring` + hilo productor |
| Tests headless con dominio aleatorio | **Adoptar** | para `godot/test/` en el PC |

---

## 6. Qué cambia en nuestra arquitectura

### 6.1 Prioridad de versión de Godot (revisión del ADR 0008)
`rclgd` exige Godot 4.7: `Callable`, lambdas, `await`, arrays tipados,
`@export`, `.connect(callable)`... **[V]**. En Godot 3.5 (GDScript 1) nada de
eso existe. Dos caminos:
- **A (recomendado, a validar):** apuntar `ros2_vita` a **`godot4-vita`** (4.8-dev7).
  La app HMI es **2D** (Control/Label/TextureRect/Button), justo lo que el port
  4.x renderiza bien; el 3D experimental no hace falta. Mismo GDScript que el taller.
  Riesgos: editor solo en Windows, proyecto joven, límites declarados
  (sin shaders propios, sin GDExtension). Sí admite módulos propios en el árbol
  (`modules/vita_editor`) **[V docs/12]**.
- **B:** mantener 3.5 con una API **distinta** (`create_subscription(topic, type,
  obj, "metodo")`) y reescribir los ejemplos. Se pierde la compatibilidad con el
  PC (`rclgd`), que era el motivo principal de la vía.

### 6.2 Nuevo módulo: `msg-schema` (reemplazo de babel_fish)
- **Generador en el PC** (Python + `rosbags`, ya usado en `msg-cdr`): `.msg` →
  blob binario de esquema compacto (tipos, campos, primitivas, arrays fijos /
  acotados / ilimitados, tipos anidados).
- **Runtime en la Vita** (dual C/Rust, sin malloc): decodificar/codificar CDR
  recorriendo el esquema con **visitor / source** (callbacks), con las mismas
  rutas rápidas para arrays primitivos (puntero + longitud sin copiar).
- Verificación **solo en host**: contra volcados canónicos generados por
  `rosbags` para muchos tipos (Twist, Imu, LaserScan, Image, Odometry, Marker...).
- `msg-cdr` (a mano) queda como camino rápido para los 4 tipos del mini-rviz.
- Estado: implementado y verificado en host (`modules/msg-schema/README.md`).

### 6.3 Contrato `ros2_vita` ≈ `rclgd`
El módulo de Godot debe exponer **los mismos nombres y firmas** (tabla de paridad
en `godot/ros2_vita/API_PARITY.md`). Diferencias aceptadas y documentadas:
sin acciones al principio, parámetros locales, `tf` sin historial, un solo
`RosNode` activo por proceso **[I]** (una sesión XRCE), y `init()` del singleton
que recibe la IP del agente por ajuste de proyecto en lugar de DDS discovery.

### 6.4 Imágenes y ancho de banda (HMI con cámara)
`roomba_hmi` recibe `sensor_msgs/Image` `rgba8`. Con XRCE por WiFi eso es
inviable a 640×480 (1.2 MB/frame). Plan **[I]**: un nodo en el PC que re-publica
`sensor_msgs/CompressedImage` (JPEG) a ~320×240 y 10 fps ⇒ ~10–20 kB/frame;
decodificar en la Vita con el cargador de JPEG de Godot (`Image.load_jpg_from_buffer`).
Coste de CPU en la Vita **[?]** → medir con `hwprobe`/FPS.

---

## 7. Cómo desarrollar con ambos mundos (flujo propuesto)

1. En el **PC**: `ros2 rclgd create vita_hmi` (Godot 4.7 + rclgd). Diseñar la
   escena en el editor y probar contra un robot simulado (`roomba_rclgd`) o real.
2. Aislar lo específico de plataforma en un autoload `Platform.gd` (IP del
   agente, resolución 960×544, entrada táctil/mandos).
3. Exportar el `.pck`; **en la Vita** corre con la plantilla que incluye
   `ros2_vita`. Los scripts no cambian; cambian solo el binario y los esquemas
   (`.rsch`).
4. Pruebas: `godot --headless` con el patrón de `run_tests.sh` (dominio
   aleatorio + LOCALHOST) en el PC; en la Vita, `hwprobe` y netlog.

---

## 8. Estado de lo hecho a raíz de este estudio

| Entregable | Estado |
|---|---|
| Este documento | hecho |
| `docs/12`, ADR 0008, `docs/16` corregidos con los hechos reales | hecho |
| `godot/ros2_vita/API_PARITY.md` (tabla rclgd ↔ Vita) | hecho |
| `modules/msg-schema` (codec genérico dual) | **hecho en host**: 24 tipos reales, decode == volcado de rosbags, encode bit a bit, fuzz C=Rust; falta cross-compilar y medir |
| Migración del esqueleto de `godot/` a Godot 4 | **pendiente** (decisión §6.1 y PC) |
| Probar `godot4-vita` con un `.pck` mínimo | **pendiente** (PC / Vita) |

## 9. Correcciones a documentos anteriores

- `docs/12` §1/§5: rclgd **no** estaba "unmaintained": ver §1.1. Además la versión
  es 3.0.0 (el índice mostraba 2.1.0) y requiere **Godot 4.7**.
- `docs/12` §5, "API compatible con rclgd": ahora **conocida** (P1 cerrado) →
  `godot/ros2_vita/API_PARITY.md`.
- `docs/12` §3: el límite de 5 parámetros de `bind_method` es de Godot 3; en 4 no aplica.
- `docs/16`: las páginas de `rclgd.readthedocs.io` ya no son necesarias (se leyó
  el código y la documentación fuente en el repositorio).

## 10. Preguntas abiertas para el usuario

1. ¿Priorizamos **Godot 4** (`godot4-vita`, editor Windows) para ser compatibles
   con `rclgd`/el taller, o se mantiene 3.5 como primera meta?
2. ¿Hay un Windows disponible (PC o VM) para el editor de `godot4-vita`? **[?]**
3. ¿Interesa una **app HMI de teleop con cámara** como caso de uso piloto
   (Objetivos 2+5), tomando `roomba_hmi` como referencia?
