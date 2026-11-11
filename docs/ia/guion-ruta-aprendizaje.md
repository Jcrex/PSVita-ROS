# Guion para Claude — Ruta de aprendizaje: versión detallada

**Para qué sirve:** que puedas **continuar el proyecto por tu cuenta**, **auditar** lo que escribe
la IA y **explicar en detalle** todo lo hecho: en una defensa, una charla o a un compañero. El
conocimiento tiene que estar en tu cabeza y en estos documentos, no en el contexto de una sesión
de Claude.

**Desde dónde partes (2026-10-31):** sabes usar la interfaz de Godot para poner los nodos de rclgd
en los modelos 3D de los ejemplos. Te falta escribir scripts de Godot, programar ROS 2 y micro-ROS,
entender cómo la Vita reparte memoria, hilos y procesos, y auditar código.

**Cómo está organizada:** 11 **pistas** (P1–P11). Cada una dice qué leer (casi todo ya existe en el
repo), qué practicar y cómo saber que la dominas. Abajo hay un **orden recomendado** que encaja las
pistas con las siguientes puertas del proyecto (G7, G8…). Así aprendes haciendo avanzar el proyecto
real, no con ejercicios sueltos.

---

## 1. El nuevo método de trabajo (tú + Claude)

Hasta G6, Claude escribía, compilaba y probaba, y tú validabas en hardware. A partir de G7:

| Paso de cada hito | Quién | Qué |
|---|---|---|
| 1. Plan | Claude explica, **tú decides** | Qué se va a tocar, por qué y qué alternativas hay, en lenguaje llano y antes de escribir código |
| 2. Código | Claude escribe la base; **tú escribes una parte** | El código lleva comentarios didácticos. Cada hito deja un **reto** de código real para ti (en la lección) |
| 3. Comandos | **Tú los lanzas** | Docker, `ros2`, compilar, exportar, desplegar. Claude te da el comando y te explica cada parte; solo lo ejecuta él si se lo pides |
| 4. Prueba | **Tú** | En el PC primero (modo `demo`) y luego en la Vita |
| 5. Auditoría | **Tú**, con la lista de P10 | Antes del commit lees el `git diff`, y Claude te pregunta qué hace cada parte |
| 6. Lección | Claude escribe, **tú marcas tu progreso** | Cada hito deja una lección en `docs/tutorial/` como la [08](./guion-leccion-08-imu.md) |

Reglas para pedirle cosas a Claude (y no volverte dependiente):

- **Pide primero la explicación y luego el código.** «Explícame cómo harías X» antes de «haz X».
- **Escribe tú el primer intento** y pide revisión: «revisa mi `_publicar`, ¿qué falla?».
- **Pregunta «¿cómo lo sabes?».** Claude debe señalar el archivo y la línea, o la documentación oficial.
  Si no puede, es una hipótesis y debe marcarla como tal.
- **Apunta lo aprendido** en la tabla «Mi progreso» de cada lección y las dudas al final de esta
  página. Lo que no esté escrito no existe la próxima sesión.

## 2. El mapa del sistema en una página

Memoriza este dibujo: casi cualquier pregunta del proyecto se responde sabiendo en qué capa estás.

```
┌──────────────────────────── PS Vita 1000 (ARM Cortex-A9 ×4, 512 MB, sin Linux) ──────────────────┐
│ Tu juego: escenas .tscn + scripts .gd                     ← P3 Godot, P4 rclgd                   │
│   │  RosNode / RosPublisher / RosMsg  (API de rclgd)                                              │
│ ros2_vita (módulo C++ dentro del motor)  godot/ros2_vita/ ← P8                                   │
│   │  RosMsg ⇄ bytes CDR guiado por esquema   modules/msg-schema (C y Rust) ← P7                   │
│   │  XrceTransport → cliente micro-XRCE-DDS (uxr_*)                       ← P5                   │
│   │  microros-transport → net-udp (sockets de la Vita, sceNet*)           ← P6, P7               │
│ Motor godot4-vita (libgodot.so cargado por un cargador; VitaGL → GPU SGX543) ← P8, P9            │
└───────────────────────────────────────── WiFi, UDP 8888 ─────────────────────────────────────────┘
                                               │
┌──────────────────────────── PC CachyOS (docker/) ───────────────────────────────────────────────┐
│ micro-ROS Agent  (traduce XRCE ⇄ DDS)                                         ← P1, P5           │
│ ROS 2 Jazzy: ros2 topic …, rqt, RViz, turtlesim, Gazebo; puente Zenoh hacia la laptop  ← P2      │
└─────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Lecturas del mapa: [docs/02](../02-arquitectura-fase1-microros.md) (por qué micro-ROS),
[docs/12 §4](../12-investigacion-godot-ros2-vita.md) (la pila por dentro),
[docs/18 §0–2](../18-migracion-a-godot4.md) (Godot 4 en la Vita), y
[`godot/README.md`](../../godot/README.md).

---

## 3. Las pistas

Cada pista tiene ✅ **lo dominas cuando…**: frases que deberías poder decir o hacer sin ayuda.

### P1 — Infraestructura de desarrollo

**Objetivo:** saber qué máquina hace qué, mover código entre ellas y levantar todo tú solo.

- Leer: [CLAUDE.md](../../CLAUDE.md) («Machine roles»), [docs/05](../05-setup-entorno-cachyos.md),
  [docs/13 §1](../13-infraestructura-desarrollo-vita.md), [`docker/README.md`](../../docker/README.md),
  la guía [VitaShell](../guias-vita/vitashell.md) y el primer bloque de [docs/06](../06-bitacora-estado.md).
- Practicar:
  - `docker/vita-ros.sh` sin argumentos: lee la ayuda y lanza `up`, `status`, `topics`, `logs agent`,
    `down`.
  - Abre `docker/docker-compose.yml` y `docker/Dockerfile`: ¿qué contenedores hay, qué red usan
    (`network_mode: host`) y por qué?
  - `tools/vita-doctor.sh`: diagnostica el entorno del PC. Lee su salida.
  - El ciclo de git laptop ↔ PC: `git pull`, `git status`, `git log --oneline -10`, `git diff`.
- ✅ Lo dominas cuando: sabes levantar la estación, explicar qué hace cada contenedor, exportar y
  desplegar un `.vpk` sin mirar la chuleta, y decir dónde están los logs de la Vita.

### P2 — ROS 2 desde la línea de órdenes

**Objetivo:** inspeccionar y depurar cualquier sistema ROS 2, no solo el nuestro.

- Leer: tutoriales oficiales de Jazzy, «Beginner: CLI tools» (docs.ros.org/en/jazzy/Tutorials).
  Conceptos clave: nodo, topic, tipo de mensaje, QoS, servicio, acción, parámetro, `tf`.
- Practicar (dentro de `docker/vita-ros.sh shell`):
  ```bash
  ros2 node list ; ros2 topic list -t ; ros2 topic info -v /cmd_vel
  ros2 interface show geometry_msgs/msg/Twist
  ros2 topic echo /odom --field pose.pose.position ; ros2 topic hz /odom ; ros2 topic bw /odom
  ros2 topic pub -r 10 /cmd_vel geometry_msgs/msg/Twist "{linear: {x: 0.5}}"
  ros2 run rqt_graph rqt_graph ; rviz2
  ```
- El MCP `ros2-introspection` del repo hace lo mismo desde Claude. Úsalo para **contrastar** lo que
  ves tú, no como sustituto.
- ✅ Lo dominas cuando: sabes explicar por qué un suscriptor no recibe nada (nombre, tipo, QoS,
  dominio o red) y lo diagnosticas con estos comandos.

### P3 — Godot 4: editor, escenas y GDScript

**Objetivo:** escribir tus propios scripts y escenas, no solo colocar nodos.

- Leer: documentación oficial de Godot 4 («Getting started» → «Step by step» y «Scripting»);
  [`skills/godot4-ros-scripting/references/godot4-esencial.md`](../../skills/godot4-ros-scripting/references/godot4-esencial.md).
  Conceptos: nodo, escena, árbol, `_ready`/`_process`/`_physics_process`/`_input`, señales,
  `@onready`, `@export`, tipos, `await`, `Callable`, recursos (`.tres`).
- Practicar con el repo:
  1. Lección [08](./guion-leccion-08-imu.md) (G7) en el editor `.gui`.
  2. Lee `godot/g6-hmi/main.gd` y explica en voz alta cada función.
  3. Cambia algo visible de la HMI (colores, escala, un dato nuevo en el panel) y pruébalo con `-- demo`.
  4. Rehaz la HMI de G6 usando nodos (`Line2D`, `Polygon2D`, `Camera2D`) en lugar de `_draw()`.
     Ese contraste es la mejor clase de Godot posible.
- ✅ Lo dominas cuando: creas desde cero una escena con dos scripts que se comunican por **señales**
  y la ejecutas en el PC y en la Vita.

### P4 — rclgd (PC) y ros2_vita (Vita): ROS 2 dentro de Godot

**Objetivo:** escribir apps Godot + ROS 2 portables entre el PC y la Vita.

- Leer: [`skills/rclgd/SKILL.md`](../../skills/rclgd/SKILL.md) (reglas y esqueleto),
  [`godot/ros2_vita/API_PARITY.md`](../../godot/ros2_vita/API_PARITY.md) (qué funciona en la Vita),
  [docs/17](../17-rclgd-estado-del-arte-godot-ros2.md) (rclgd y roomba_ws) y
  [`skills/ros2-vita-godot/SKILL.md`](../../skills/ros2-vita-godot/SKILL.md).
- Practicar:
  - Reglas de oro: guardar las referencias `Ros*`, tipos como texto, arrays enteros, callbacks en el
    hilo principal, QoS compatible.
  - Clona `github.com/Ozuba/roomba_ws` (el ejemplo de rclgd estudiado en docs/17) y localiza en sus
    scripts los mismos patrones que en `g6-hmi`. Se abre con el Godot 4.7.1 de rclgd (`godot/rclgd/`).
  - Añadir un tipo al esquema: `tools/gen_msg_schema.py` (lee su cabecera) y regenera `ros/schema.rsch`.
- ✅ Lo dominas cuando: escribes un nodo que se suscribe a un topic y publica otro, lo pruebas en el
  PC y en la Vita sin cambiar el script, y sabes por qué en la Vita no existe `RosSensorMsgsImu`.

### P5 — micro-ROS y XRCE-DDS

**Objetivo:** entender qué pasa entre `publish()` y `ros2 topic echo`, y programar con el cliente
XRCE directamente.

- Conceptos (en este orden): DDS y RTPS → por qué no cabe en la Vita ([docs/01](../01-hardware-y-plataforma.md),
  «Por qué ROS2 completo no entra») → **cliente-agente XRCE**: el agente crea las entidades DDS en
  nombre del cliente → **sesión** (clave de cliente) → **entidades** (participante, topic,
  publisher, datawriter, subscriber, datareader) creadas por XML → **streams** (fiable y best
  effort; historial; MTU) → **transporte propio** (callbacks open/close/write/read).
- Leer el código, en este orden:
  1. `vita-app/src/` (Fase 1, C puro): el ejemplo más pequeño de una sesión XRCE completa.
  2. `modules/microros-transport/` y `modules/net-udp/` (con sus README).
  3. `godot/ros2_vita/xrce_transport.cpp`: lo mismo dentro de Godot, con fragmentación y dos streams.
     Los comentarios explican tres fallos reales de G6.
  4. Documentación oficial de eProsima Micro XRCE-DDS (cliente: API `uxr_*`).
- Practicar: `docker/vita-ros.sh logs agent` mientras arranca la Vita (verás crear la sesión y las
  entidades) y `docker/vita-ros.sh sniff 192.168.1.94` para ver los datagramas.
- ✅ Lo dominas cuando: sabes dibujar el intercambio de mensajes al crear un publicador y explicar
  por qué `/odom` llega en 2 datagramas y qué pasaría con best effort.

> **micro-ROS ≠ micro-XRCE-DDS.** micro-ROS es la pila completa (`rclc` + `rmw_microxrcedds`) para
> microcontroladores. Aquí usamos **solo el cliente XRCE** por debajo, con nuestra propia capa tipo
> rclgd encima. Por qué: [docs/02](../02-arquitectura-fase1-microros.md) y
> [ADR 0008](../adr/0008-godot-via-modulo-estatico.md).

### P6 — El hardware de la Vita: CPU, memoria, hilos, GPU

**Objetivo:** razonar sobre límites (unos 365 MiB para la app, 4 núcleos de los que el sistema se
reserva uno, sin procesos ni memoria virtual al estilo Linux) y decidir dónde va cada trabajo.

- Leer: [docs/01](../01-hardware-y-plataforma.md) y, a fondo,
  [docs/14](../14-hardware-vita-memoria-hilos-optimizacion.md) (CPU, memoria, hilos, GPU, qué
  construir). Luego [`tools/hwprobe/`](../../tools/hwprobe) (la sonda para cerrar los `[?]`).
- Preguntas guía:
  - ¿Por qué el proyecto evita `malloc` en los módulos (mem-pool, buffers estáticos)?
  - ¿Qué es *newlib* y qué falta respecto a Linux (procesos, `fork`, señales)?
  - ¿Por qué `worker_pool/max_threads=2` en `project.godot`?
  - ¿Por qué todo XRCE va en el hilo principal (comentario al inicio de `xrce_transport.cpp`)? ¿Qué
    ganarías y qué arriesgarías moviéndolo a otro hilo con `msg-ring`?
- Practicar: compilar y ejecutar `tools/hwprobe` en la Vita y comparar con docs/14.
- ✅ Lo dominas cuando: sabes estimar si una función (por ejemplo, una cámara a 15 fps) cabe en
  memoria, CPU y red, y decides en qué hilo va.

### P7 — C y Rust de bajo nivel (los módulos duales)

**Objetivo:** leer, cambiar y optimizar los módulos de `modules/` en C y en Rust.

- Lecciones 01–06 de este tutorial (C → Rust → red → transporte → app → `.vpk`) y la serie de
  referencia [docs/rust](../rust/00-herramientas-y-ecosistema.md).
  [docs/03](../03-estrategia-dual-rust-cpp.md) explica el patrón dual.
- Orden de módulos: `mem-pool` → `msg-ring` (hilos y atómicos) → `net-udp` → `microros-transport`
  → `msg-cdr` / `msg-schema` (serialización) → `tf-tree` y `viz-math`.
- Practicar: `tools/run-parity-tests.sh <módulo>` tras cada cambio. Crea un módulo nuevo con la
  skill `vita-dual-module` **escribiéndolo tú**.
- ✅ Lo dominas cuando: explicas `msg-ring` (cola SPSC sin bloqueos) en C y en Rust y por qué los
  `Ordering` son los que son.

### P8 — Godot por dentro: el módulo C++, el cargador y la compilación

**Objetivo:** tocar `ros2_vita` (C++) y recompilar la plantilla de la Vita sin ayuda.

- Leer: [docs/18](../18-migracion-a-godot4.md) entero (sobre todo §2, «cómo funciona por dentro»,
  y §4, «cierre de imports»), [`godot/README.md`](../../godot/README.md) y
  [docs/15 §10](../15-rust-nativo-y-optimizacion-vita.md) (Rust dentro de `libgodot.so`).
- Conceptos: módulo en árbol frente a GDExtension (la Vita no admite GDExtension), `ClassDB` y
  `_bind_methods` (cómo una función C++ aparece en GDScript), `libgodot.so` cargado por un cargador
  con una **tabla de imports** (por qué cada función nueva del SDK necesita entrada), PIC.
- Practicar: añade un método trivial a `RosNode` (por ejemplo `get_publisher_count()`), compílalo
  en el editor de host (unos 15 s), úsalo desde GDScript y luego recompila la plantilla
  (`tools/build-godot-template.sh`, debe salir `PASS`).
- ✅ Lo dominas cuando: sabes explicar el camino de `pub.publish(m)` desde GDScript hasta `sendto()`
  señalando cada función (la lección 08 §2 es el guion).

### P9 — 3D en la Vita

**Objetivo:** llevar modelos 3D (robots, URDF/mallas) a una app de la Vita sin hundir los fps.

- Hechos de partida: renderizador **GL Compatibility** sobre VitaGL; 960×544; GPU con memoria
  propia limitada (docs/14 §5).
- Leer: [docs/11](../11-diseno-mini-rviz.md) (mini-rviz, presupuestos), docs/18 (estado del
  renderizado del port) y la documentación de Godot sobre importar **glTF** y LOD.
- Practicar (cuando lleguemos a la puerta 3D): una escena 3D con un modelo del ejemplo de rclgd en
  el PC → exportar a la Vita → medir fps (`Engine.get_frames_per_second()`) → reducir polígonos y
  texturas hasta llegar a 30 fps.
- Pendiente de medir en el proyecto (T7.3/T7.4 de docs/19): fps y coste de texturas en la Vita.
  Lo que diga cualquier guía genérica es una hipótesis hasta medirlo aquí.
- ✅ Lo dominas cuando: sabes decir cuántos triángulos y qué texturas aguanta una escena a 30 fps,
  **medido**.

### P10 — Auditar código

**Objetivo:** revisar lo que escribe la IA (o cualquiera) y encontrar fallos antes que el hardware.

Lista de comprobación. Pásala sobre cada `git diff` antes de un commit:

**General**
- [ ] ¿Entiendo qué hace cada línea cambiada? Si no, pregunto antes de aceptar.
- [ ] ¿Coincide con lo que se pidió? ¿Hay cambios que nadie pidió?
- [ ] ¿Qué está probado y dónde (PC, Vita), y qué está marcado «validar en hardware»?

**GDScript / Godot**
- [ ] Objetos `Ros*` guardados en variables del script (no locales).
- [ ] Nada pesado en `_process` (que no se cree un `RosMsg` por fotograma sin necesidad).
- [ ] Errores visibles en pantalla (en la Vita no hay consola).
- [ ] Tipos declarados (`var x: float`, `-> void`): el editor detecta más fallos.

**ROS 2**
- [ ] Nombre del topic, tipo y QoS coherentes con quien lo consume.
- [ ] Unidades SI y ejes REP-103; `frame_id` puesto; covarianzas según la convención del mensaje.
- [ ] Frecuencia razonable para la WiFi (mira `ros2 topic bw`).

**micro-ROS / red**
- [ ] ¿El mensaje cabe en la MTU (512)? Si no, ¿va por el stream fiable?
- [ ] ¿Qué pasa si el agente se cae o la WiFi se corta?

**C / C++ / Rust**
- [ ] Límites de buffers (cada `memcpy`, índice o longitud).
- [ ] Quién reserva y quién libera cada memoria. ¿Hay `malloc` en un camino caliente?
- [ ] Datos compartidos entre hilos: ¿atómicos o cola? ¿Qué hilo escribe?
- [ ] En la Vita: ¿la función del SDK nueva está en la tabla del cargador (`tools/check-vita-imports.py`)?
- [ ] Paridad C ↔ Rust: `tools/run-parity-tests.sh` en verde.

Herramientas: `git diff`, `git log -p <archivo>`, `git blame`, la skill `/code-review` (como
**segunda** opinión, después de la tuya) y los tests de host (`godot/test/run_host_tests.sh`).

- ✅ Lo dominas cuando: en una revisión encuentras algo que la IA no señaló, y lo justificas con la
  lista.

### P11 — Diseñar a gran escala

**Objetivo:** pasar de demos de una pantalla a apps grandes y mantenibles.

- Temas: separar la app en escenas reutilizables (robot, sensor, HMI), autoload ROS (un único
  `rclgd.init`), parámetros en `project.godot` frente a la línea de órdenes, muchos topics con un
  ancho de banda limitado, pruebas automáticas (`godot/test/`, `skills/godot4-ros-scripting/templates/test_runner.gd`),
  CI ([docs/19](../19-plan-multiagente-migracion-godot4.md) T4.7) y documentación (ADRs en `docs/adr/`).
- Leer: [docs/19](../19-plan-multiagente-migracion-godot4.md) (el mapa de todo lo que falta) y los
  ADRs (`docs/adr/`): cada uno explica una decisión grande y su porqué.
- ✅ Lo dominas cuando: sabes escribir un ADR propio para una decisión (por ejemplo, la cámara en
  G7) con alternativas, costes y criterio.

---

## 4. Orden recomendado (encajado con el proyecto)

| Etapa | Hito del proyecto | Pistas | Lección / práctica |
|---|---|---|---|
| 1 | **G7a — IMU** (código escrito, falta hardware) | P1, P2, P3, P4 | [08](./guion-leccion-08-imu.md): retos 1–4 |
| 2 | G7b — botones como `Joy` + panel trasero | P3, P4, P8 | Reto 4 de la 08; panel trasero = parche C++ en `display_server_vita.cpp` (P8) |
| 3 | Repaso de bajo nivel | P7 | Lecciones 01–06 (C y Rust) |
| 4 | G7c — decisión sobre la cámara | P6, P5, P11 | Escribir **tú** el ADR de la cámara (memoria, fps, ancho de banda) |
| 5 | Comprender la red a fondo | P5 | Leer `xrce_transport.cpp` con la lección 08 §2; `sniff` y `logs agent` |
| 6 | Escena 3D en la Vita | P9 | Robot 3D + `/odom` en la Vita, con fps medidos |
| 7 | Optimizar | P6, P7 | `hwprobe`; mover trabajo a Rust o C donde se mida un cuello de botella |
| 8 | App grande | P11 | Combinar teleop, sensores y 3D; ADRs; pruebas |

## 5. Autoevaluación final: «explícalo como si lo defendieras»

Cuando puedas responder todo esto **de memoria y con referencias al código**, podrás explicar el
proyecto en detalle:

1. ¿Por qué no se puede ejecutar ROS 2 completo en la Vita y qué se hizo en su lugar?
2. Dibuja el camino de un `Twist` desde el stick de la Vita hasta la tortuga de turtlesim.
3. ¿Qué es el agente micro-ROS, dónde corre y qué pasa si se reinicia?
4. ¿Por qué Godot 4 en la Vita usa un módulo en árbol y no GDExtension? ¿Qué es la tabla de imports?
5. ¿Qué es el `.rsch` y por qué la Vita no puede usar la introspección de tipos de ROS 2?
6. ¿Por qué hay dos implementaciones (C y Rust) de cada módulo y cómo se garantiza que hacen lo mismo?
7. ¿Qué limita más a la Vita en este proyecto: la CPU, la memoria, la GPU o la WiFi? Justifícalo con
   medidas (G6: `/cmd_vel` a 19,5 Hz, `/odom` a 62,5 Hz y 720 B por mensaje).
8. ¿Qué tres fallos aparecieron en G6 y cómo se arreglaron?
9. ¿Qué queda pendiente y en qué orden lo harías? (docs/06 y docs/19)

## 6. Mis dudas abiertas

Apunta aquí lo que no entiendas para preguntarlo en la próxima sesión (y luego escribe la respuesta):

| Fecha | Duda | Respuesta (con archivo:línea) |
|---|---|---|
| | | |
