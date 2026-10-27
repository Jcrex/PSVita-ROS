# 13 — Infraestructura del entorno de desarrollo PS Vita ↔ ROS2

**Fecha:** 2026-10-27 · **Estado:** mapa maestro; complementa `docs/12`
(investigación Godot) y `docs/06` (bitácora). Marcas: **[V]** verificado en
fuente o en test · **[I]** inferencia · **[?]** sin confirmar.

Este documento responde: *¿qué piezas componen el entorno completo, cuáles
existen ya, cuáles son las librerías de optimización previstas y qué queda
bloqueado por el hardware o el PC?*

---

## 1. Capas del entorno (de abajo a arriba)

| Capa | Pieza | Estado |
|---|---|---|
| Toolchain | VitaSDK (vdpm), Rust nightly + `build-std`, `cargo-vita`, cmake, scons (solo Godot) | PC: instalado salvo scons **[V bitácora]** |
| Diagnóstico | `tools/vita-doctor.sh` — lista qué falta en cada máquina | **Nuevo, probado en laptop** |
| Módulos duales (C+Rust, paridad en host) | `mem-pool`, `net-udp`, `microros-transport`, **`msg-ring`** | 4/4 verdes; `msg-ring` nuevo (2026-10-27) |
| Cliente micro-ROS | Micro-XRCE-DDS v2.4.3 + Micro-CDR v2.0.1, transporte custom sobre `sceNet` | Hardware OK (Obj. 1 y 2) |
| Agente | `micro-ros-agent:jazzy` en la laptop (`--net=host --ipc=host`) | Hardware OK |
| Gráficos | vitaGL único dueño del GPU (ADR 0007), mini-rviz (ADR 0006) | Etapa B validada en hardware |
| Apps | `vita-app/` (teleop + VIZ) · `godot/` (esqueleto, ADR 0008) | App C OK; Godot sin verificar |
| Observabilidad | netlog UDP, `/monitor` web, MCP `ros2-introspection` | OK (monitor sin probar con Vita real) |
| Web / docs | Astro, publica `docs/**` automáticamente | OK |

Reglas que se mantienen: doble implementación Rust+C tras un header C;
la laptop no instala nada; un commit por hito; sin tests de paridad en rojo.

---

## 2. Objetivos × infraestructura

| # | Objetivo | Estado | Qué lo respalda | Pendiente |
|---|---|---|---|---|
| 1 | Topics ROS2 | **Cerrado** (hardware) | los 3 módulos + XRCE | afinar MTU/streams (§3) |
| 2 | Control de robot | **Cerrado** (hardware) | `teleop.c`, `docs/09` | — |
| 3 | rviz2 en la Vita | **Resuelto como Plan B** (ADR 0006) | auditoría real, mini-rviz | cierre Etapas C–F (docs/10) |
| 4 | Visualizar robots/mapas | En curso | `docs/11`, vitaGL, Etapa D | `msg-cdr`, `viz-math`, `tf-tree` (§4) |
| 5 | Hardware propio (cámara, IMU, trasero) | Diseño en §5 | headers vitasdk **[V]** | todo en hardware |
| 6 | Toolkit publicable | En curso | skills, MCP, paridad, docs, `vita-doctor` | §7 |
| — | **Godot + ROS2** (nuevo) | Investigado | `docs/12`, ADR 0008, `godot/` | P1–P11 de docs/12 §8 |

---

## 3. Optimización del cliente micro-ROS (plan de medición)

Los parámetros y sus defaults reales están en `docs/12` §4. No se cambia
nada "porque sí": **cada ajuste se mide con el netlog** (regla anti-asunción).

**Experimento E1 — latencia ida/vuelta.** Topic `/ping` (Vita→PC) + `/pong`
(PC→Vita), `std_msgs/UInt64` con timestamp `sceKernelGetProcessTimeWide`;
la Vita calcula RTT y lo manda al netlog. Variables a barrer una a una:

| Variable | Valores | Hipótesis [I] |
|---|---|---|
| `UCLIENT_CUSTOM_TRANSPORT_MTU` | 512 → 1024 → 1400 | menos fragmentación en mensajes > 512 B (JointState, TF múltiples) |
| `UCLIENT_MIN_HEARTBEAT_TIME_INTERVAL` | 100 → 50 ms | menor latencia en reliable, algo más de tráfico |
| `STREAM_BUFFER_SIZE`/`HISTORY` (`main.c`) | 4096×4 → 8192×4 | evita rechazos con TF grandes |
| Timeout de `uxr_run_session_time` | 50 → 10 ms | más fluidez del bucle, más CPU |
| best-effort vs reliable para `/tf`, `/cmd_vel` | — | `/cmd_vel` y `/tf` toleran pérdida; baja latencia |

Resultado esperado: una tabla en la bitácora y los valores elegidos como
defaults documentados en `build-xrce-client-vita.sh`. **Bloqueado: Vita + laptop.**

**Mejoras de código que NO requieren hardware** (hechas o preparadas):
- `msg-ring` (hecho): desacopla red y render; contador `dropped` para el netlog.
- `mem-pool` ya acota las asignaciones del cliente; revisar si el cliente
  XRCE lo usa realmente (hoy es un módulo disponible, **[?]** no auditado).
- Evaluar *creación de entidades por referencia* frente a XML: el cliente
  v2.4.3 la soporta (usa `uxr_buffer_create_*_ref` en vez de `_xml`
  **[?]** nombres exactos sin verificar) y reduce memoria **[V buscador]**.

---

## 4. Catálogo de librerías de optimización/infra (módulos duales)

Cada una sigue `skills/vita-dual-module/` y es verificable en host.

| Módulo | Para qué (función clave de ROS2) | Estado | Prioridad |
|---|---|---|---|
| `msg-ring` | Pasar mensajes red→render/Godot sin bloqueo | **Hecho**, paridad + estrés 2 hilos + TSan | — |
| `viz-math` (D1) | vec3/quat/mat4 para TF, cámara y robot | Planificado (`docs/10` §7) | Alta (testeable en host) |
| `msg-cdr` (D2) | Deserializar `TFMessage`, `JointState`, `Marker`, `OccupancyGrid` sin copias | Planificado; **requiere fixtures reales de ROS2** (contenedor `robotnik_dev`) | Alta |
| `tf-tree` (D3) | Último valor por frame + cadenas padre→hijo | Planificado | Alta |
| `ros-facade` (nuevo) | API pequeña `publish/subscribe(topic,type)` sobre XRCE para apps C **y** Godot; oculta `uxr_*` | Idea; define el contrato único que usará `RosNode` | Media (tras medir E1) |
| `cdr-fast` (nuevo) | Serializadores de los mensajes de salida (`Twist`, `Joy`, `Imu`) sin `ucdr` genérico | Idea; solo si el perfil lo justifica | Baja |

Regla de calidad: nada se optimiza sin medir antes; un módulo nuevo solo
entra si lo exige un consumidor real (mini-rviz, Godot, sensores).

**Formato de mensaje interno** (hilo de red → consumidor), usado por
`RosNode` y propuesto para la app C: `[uint16 topic_id LE][CDR del mensaje]`
en una ranura de `msg-ring` (≤ 512 B; los mapas grandes se acumulan aparte).

---

## 5. Objetivo 5 — hardware propio: lo que ya se sabe (headers vitasdk)

Fuente: [`vita-headers/include/psp2/camera.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2/camera.h)
y [`motion.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2/motion.h) **[V]**.

**IMU (giroscopio + acelerómetro)**
- `sceMotionStartSampling()` → `sceMotionGetState(&st)` (estado fusionado) o
  `sceMotionGetSensorState(buf, n)` (registros crudos, con `counter` para
  descartar muestras repetidas — patrón usado por el backend de SDL
  [V buscador]).
- `SceMotionState`: `acceleration`, `angularVelocity`, `deviceQuat`,
  `rotationMatrix`, `timestamp`. Mapa natural: `sensor_msgs/msg/Imu`
  (`orientation` ← `deviceQuat`, `angular_velocity`, `linear_acceleration`).
- **[?]** Unidades de `acceleration` (¿g o m/s²?) y sistema de ejes:
  medir en hardware antes de publicar. `sceMotionReset` + ajuste de
  `sceMotionSetGyroBiasCorrection` / `SetTiltCorrection` para estabilidad.

**Cámaras**
- `sceCameraOpen(dev, &info)`, `Start`, `Read`, `Stop`, `Close`; `dev` =
  `FRONT(0)`/`BACK(1)`. Resoluciones: 640×480, 320×240, 160×120, 352×288,
  176×144, 480×272, 640×360; framerates 3…120 fps (120 solo ≤ QVGA);
  formatos YUV422/420 (plano), ARGB/ABGR, RAW8. El frame llega en
  planos Y/U/V (`pIBase/pUBase/pVBase`) **[V]**.
- Presupuesto de ancho de banda **[I]**: 320×240 YUV420 ≈ 115 kB/frame ⇒
  10 fps ≈ 1.1 MB/s (~9 Mbit/s): factible en WiFi pero **muy por encima del
  MTU** (fragmentación XRCE). Plan: empezar en 160×120 a 5 fps con
  `sensor_msgs/Image` mono8 (solo plano Y ≈ 19 kB), medir, y valorar
  `CompressedImage` (JPEG) si hay un codificador disponible en VitaSDK **[?]**.
- Los mensajes grandes **no** pasan por `msg-ring` (ranuras ≤ 512 B): salen
  por stream reliable propio con `UCLIENT_TWEAK_XRCE_WRITE_LIMIT` (ON por
  defecto **[V]**).

**Panel táctil trasero:** `sceTouchPeek(SCE_TOUCH_PORT_BACK, …)` ya es el
patrón del teleop (frontal); extender el mapeo de `docs/09` **[I]**.

Todo lo de esta sección es **diseño**; nada se ha ejecutado.

---

## 6. Pipeline Godot (resumen; detalle en `docs/12` y ADR 0008)

```
tools/build-godot-template.sh   (PC; ≈1–2 h)   godot-vita 3.5 + godot/ros2_vita
   → bin/vita_release.zip (plantilla)  ──►  export-pack game.pck  ──►  .vpk
```

- Vía A (rclgd en el PC), B (rosbridge `ws://`) y C (módulo estático) en `docs/12` §5.
- Arranque recomendado: **primero** desarrollar la escena GDScript en el
  PC con rclgd (sin Vita), **luego** compilar la plantilla con el módulo.

---

## 7. Objetivo 6 — toolkit publicable: qué falta

- [x] Skills `vita-dual-module`, `vita-build-package`, `vita-deploy-logs`.
- [x] MCP `ros2-introspection`, paridad en host, `vita-doctor`.
- [ ] Skill `godot-vita-build` (cuando P2 produzca una receta verificada;
      escribirla antes sería documentar una receta no probada).
- [ ] `docs/` de "empezar desde cero" para terceros (reutilizar guías de `docs/guias-vita/`).
- [ ] CI público: paridad en GitHub Actions (el runner solo necesita gcc+cargo).
      **Hecho en repo: no** (no hay `.github/workflows`; decisión del usuario
      pendiente: el repo es privado/público).
- [ ] Vita3K como banco de pruebas de VPK sin hardware: **[?]** red/sceNet y
      uso headless sin documentar (docs/12 P11).

---

## 8. Lista consolidada de pendientes por dependencia

**Necesitan el PC de desarrollo (VitaSDK):**
1. Cross-compilar `msg-ring` (C y Rust) y añadirlo al crate paraguas.
2. `tools/build-godot-template.sh` (P2) y compilar `godot/ros2_vita` (P4).
3. Instalar `scons`; confirmar paquetes vdpm (`pvr_psp2`, `vita-rss-libdl`).
4. Leer docs bloqueados desde esta sesión: rclgd (P1), Godot módulos (P10).
5. Implementar D1–D3 (`viz-math`, `msg-cdr`, `tf-tree`; los tests corren en la laptop).

**Necesitan la Vita conectada:**
1. Estrés de `msg-ring` en la Cortex-A9 (orden de memoria real).
2. Experimento E1 (MTU, heartbeat, streams) y E2 (FPS del mini-rviz).
3. IMU: unidades/ejes (§5); cámara: ancho de banda real.
4. "Hola mundo" Godot: RAM libre, FPS, `ATTRIBUTE2=12` (P5, P6).
5. Probar `/monitor` con el netlog real de la Vita.

**Necesitan decisión del usuario:**
1. ¿Godot 3.5 (`godot-vita`) o 4.x (`godot4-vita`, editor solo Windows)?
2. ¿Repo público + CI?
3. ¿Evaluar zenoh-pico? (hoy descartado por madurez; ADR futuro).
