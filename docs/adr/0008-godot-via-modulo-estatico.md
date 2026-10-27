# ADR 0008: Godot en la Vita — módulo C++ estático sobre la capa ROS dual, app separada

- **Estado:** Aceptado el 2026-10-27 (usuario: priorizar Godot 4) — **la ejecución sigue sin validar** en PC y hardware (puertas G1–G7, docs/18 §8). Historia: propuesto con 3.5; revisado tras estudiar `rclgd`/`roomba_ws` (docs/17).
- **Fecha:** 2026-10-27

## Contexto

Se quiere poder desarrollar aplicaciones de Vita con Godot que usen ROS2
(`docs/12-investigacion-godot-ros2-vita.md`). Hechos verificados:

1. Existen dos ports no oficiales: `godot-vita` (3.5, GLES2 vía PVR_PSP2)
   y `godot4-vita` (4.x, GXM nativo).
2. Ninguno soporta GDExtension; Rust no soporta enlace dinámico en la
   Vita; por tanto el código nativo debe ir **compilado dentro del motor**.
3. Nuestra pila ROS2 ya funciona en hardware y es modular: header C +
   staticlib (C o Rust) → XRCE → `microros-transport` → `net-udp` (sceNet).
4. ADR 0007: vitaGL es dueño exclusivo del GPU en nuestra app; Godot
   inicializa el GPU por su cuenta → no pueden vivir en el mismo proceso.

## Decisión

1. **Integración = módulo estático de Godot `ros2_vita`** (C++ delgado)
   que llama **solo** a los headers C de `modules/*/include/` y al cliente
   XRCE. Sin lógica propia de ROS en C++: así la implementación Rust o C
   sigue siendo intercambiable (regla transversal del repo).
2. **Dos aplicaciones separadas** que comparten la capa ROS:
   `vita-ros2` (C + vitaGL, existente) y `vita-ros2-godot` (nueva).
   No se intenta incrustar vitaGL/mini-rviz dentro de Godot.
3. **Hilos:** la sesión XRCE (`uxr_run_session_*`) corre en un hilo propio;
   los mensajes entrantes pasan al hilo principal de Godot por una **cola
   acotada** (descarta el más antiguo y cuenta `get_dropped()`) y se entregan
   por `Callable` en `process_frame`. El esqueleto usa `Mutex` + `List`; el
   anillo SPSC sin bloqueos `msg-ring` (paridad en host) queda reservado para
   el camino caliente del hilo XRCE si la medición lo exige. Se evita
   `UCLIENT_PROFILE_MULTITHREAD` salvo que haga falta.
4. **API GDScript objetivo = la de rclgd** (P1 cerrado, `godot/ros2_vita/API_PARITY.md`):
   `RosNode.new().init(name, ns)`, `create_publisher(topic, type, qos)`,
   `create_subscription(topic, type, callable, qos)`, `RosMsg` con propiedades,
   `create_timer`, `now()`, TF. Callbacks al hilo principal. Tipos soportados al inicio:
   `std_msgs/String`, `geometry_msgs/Twist`, `sensor_msgs/Joy`
   (los de Objetivo 2).
5. **Versión de Godot — DECIDIDA (2026-10-27): Godot 4 (`godot4-vita`, 4.8-dev7).** `rclgd`
   (el estado del arte, docs/17) es solo Godot 4 (`Callable`, lambdas, `await`); así *el mismo
   script* corre en el PC y en la Vita. Se descarta Godot 3.5. Alcance: apps **2D/HMI** (la ruta
   GXM 2D es la validada del port); el 3D de la Vita se queda en `vita-app/` (ADR 0007). El módulo
   está reescrito para la API in-tree de Godot 4 (docs/18 §6).
6. **Vías de transición:** la vía A (rclgd en el PC) sirve para desarrollar sin Vita. La vía B
   (rosbridge `ws://`) **ya no existe**: `godot4-vita` desactiva `websocket` y `mbedtls` (docs/18 §2.4).

7. **Reglas de enlace (docs/18 §3.2):** el módulo vive dentro de un `libgodot.so` PIC sin libc: código PIC,
   cierre de imports contra `default_dynlib.c` del loader (parche `godot/loader-patches/`), sin TLS, y
   las bibliotecas `.a` se pasan a SCons como *File* (la plataforma descarta las cadenas).
8. **Sondas antes que supuestos**: `tools/hwprobe/` mide RAM, núcleos y ancho de
   banda (docs/14 §9) antes de fijar presupuestos de la app Godot.

8b. **Entorno del usuario y fork (2026-10-27):** solo Linux (CachyOS); no hay Windows. Desarrollo con el editor
   4.7.1 que descarga rclgd; export con un segundo editor 4.8-dev7 (Linux) y el addon `psvita`. Se anota el
   **fork de godot4-vita** como tarea (M19) pero se prioriza lo máximo posible el entorno estándar: módulo
   fuera del árbol, parches mínimos y proponibles a upstream (docs/18 §11).
8c. **Red = opción A (usuario, 2026-10-27):** `net-udp` inicializa `sceNet` dentro de `libgodot.so`; el motor
   no se modifica para la red (docs/18 §4.3). Plan de ejecución multiagente: `docs/19`.
9. **Esquemas en lugar de introspección:** la Vita no tiene `ros_babel_fish`
   (introspección de type support de `rclcpp`). Se sustituye por esquemas
   generados en el PC y un codec CDR genérico (`modules/msg-schema`, docs/17 §6.2).

## Alternativas descartadas

- **GDExtension / godot-rust (gdext):** imposible sin enlace dinámico.
- **Port propio de Godot:** coste enorme y sin NDA/SDK oficial; ya existen
  dos ports.
- **Godot sobre vitaGL propio + mini-rviz dentro de Godot:** conflicto de
  GPU y el 3D de godot4-vita es experimental (sin shaders propios).
- **Reimplementar XRCE en GDScript sobre `PacketPeerUDP`:** frágil, lento,
  y la plantilla 3.5 oficial no trae sockets.

## Consecuencias

- Se añade `msg-ring` (cola dual) como pieza reutilizable también por
  la app C (red → render del mini-rviz).
- Hay que mantener una **plantilla de exportación propia** (build de
  1–2 h) → script y CI en el PC (pendiente, docs/13 §6).
- El módulo C++ **no es verificable en la laptop**: todo su código lleva
  el marcador "validar en el PC / en hardware".
- Riesgo asumido: ambos ports son proyectos de terceros pequeños; se
  fijará un commit exacto (P2) y se versionarán las plantillas.
