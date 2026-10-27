# ADR 0008: Godot en la Vita — módulo C++ estático sobre la capa ROS dual, app separada

- **Estado:** Propuesto — **revisado 2026-10-27** tras estudiar `rclgd`/`roomba_ws` (docs/17): la decisión 5 (versión de Godot) queda **abierta** y recomienda Godot 4 (ver abajo). Pendiente de validar en PC y hardware (docs/12 §8)
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
   SPSC sin bloqueos** (módulo dual `msg-ring`, ya implementado y con
   paridad en host) y se emiten como señales de Godot. Se evita el perfil
   `UCLIENT_PROFILE_MULTITHREAD` salvo que la medición lo exija.
4. **API GDScript objetivo = la de rclgd** (P1 cerrado, `godot/ros2_vita/API_PARITY.md`):
   `RosNode.new().init(name, ns)`, `create_publisher(topic, type, qos)`,
   `create_subscription(topic, type, callable, qos)`, `RosMsg` con propiedades,
   `create_timer`, `now()`, TF. Callbacks al hilo principal. Tipos soportados al inicio:
   `std_msgs/String`, `geometry_msgs/Twist`, `sensor_msgs/Joy`
   (los de Objetivo 2).
5. **Versión de Godot — REVISADA (2026-10-27):** `rclgd` (el estado del arte,
   docs/17) es **solo Godot 4.7** y su API usa `Callable`, lambdas y `await`:
   no corre en 3.5. Para que *el mismo script* funcione en el PC (rclgd) y en la
   Vita hay que apuntar a **`godot4-vita`**. Recomendación: **Godot 4 primero
   para apps 2D/HMI** (lo que mejor soporta el port); 3.5 queda como camino
   alternativo con una API distinta si 4.x no llega a ser viable (P3/P5). Los
   módulos siguen detrás de `godot_compat.h`. **Decisión final del usuario
   pendiente** (docs/17 §10).
6. **Vías de transición:** Vía A (rclgd en PC) y vía B (rosbridge `ws://`)
   sirven para prototipar sin código nativo (docs/12 §5); no sustituyen
   a la vía C.

7. **Una sola base de código para 3.5 y 4.x**: `godot/ros2_vita/godot_compat.h`
   concentra las diferencias de API (2026-10-27). El trabajo avanza en 3.5; 4.x
   se activa cuando se cumpla el criterio de `godot/README.md`.
8. **Sondas antes que supuestos**: `tools/hwprobe/` mide RAM, núcleos y ancho de
   banda (docs/14 §9) antes de fijar presupuestos de la app Godot.

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
