# W12 — LT5 sensores simulados y LT7 visión en la PS Vita (borrador)

> Investigador: sensores simulados y visión embebida. Posts: `W12-sensores-vision.json`.
> Etiquetas: [V] verificado en código/SDK, [I] inferencia, [?] sin datos.
> Prefijos: `rs:` = clon `rclgd_sensors/addons/rclgd-sensors/`; `pv:` = `toolchains/godot4-vita/engine/platform/vita/`.

## 1. LT5 — dónde corre cada sensor

| Sensor | Vita | PC rclgd | Mismo script | Evidencia / nota |
|---|---|---|---|---|
| IMU (ruido, deriva, LPF) | ✅ 50 Hz | ✅ 100 Hz | ✅ | lógica pura `rs:ros_imu/ros_imu.gd:49-94` [V]; Imu 316 B ⇒ BE (W2) [V] |
| GPS (error correlacionado) | ✅ 10 Hz | ✅ | ✅ | `rs:ros_gps/ros_gps.gd:47-69` [V]; NavSatFix ~130 B [I] |
| Odometría de ruedas | ✅ como `/vita/pose2d` 40 B | ✅ Odometry | ✅ (salida distinta) | Odometry 724 B > 488 (W2) [V] |
| Motores diferenciales | ✅ cinemático | ✅ también RigidBody+joints | ✅ cinemático | coste de joints en Vita [?] |
| LiDAR 2D por rayos | ⚠️ ~180 rayos/10 Hz | ✅ | ✅ (tasa por `has_feature`) | §2 |
| LiDAR 3D | ❌ | ✅ | — | 57 600 rayos/s; PointCloud2 no cabe (W2) |
| Cámara RGB/profundidad/ojo de pez | ❌ | ✅ | — | SubViewport/RenderingDevice (`rs:ros_camera/ros_camera.gd:27-125`) [V]; sin 3D offscreen (W7) [V] |

## 2. LiDAR 2D con `intersect_ray`

- Margen real: g7c ≈ 17 ms/fotograma, render ≈ 11,6 ms (`docs/06-bitacora-estado.md:56`) [V] ⇒ a 30 FPS sobran ~15 ms.
- El render lanza hasta 96 rayos de sombra (`pv:rasterizer_scene_gxm_vita.inc:550,869`) [V], solo con luces omni/spot y StaticBody3D ⇒ luz direccional o `shadow_rays=0`.
- Estimación [I]: 50–130 µs/rayo desde GDScript (20–50 µs de núcleo + Dictionary) ⇒ 4 ms = 30–80 rayos/fotograma ⇒ 180 rayos a 10 Hz repartidos en 3 fotogramas: justo.
- Mejoras: capa de colisión propia, rango ≤ 8 m, helper C++ `scan()` sin Dictionary (2–3× [I]), o DDA sobre rejilla en C (2–5 µs/rayo [I]).
- **Microbenchmark `w12-raybench`**: 20/100 cajas, N ∈ {16…256}, 3 variantes (intersect_ray, RayCast3D+`force_raycast_update`, C++), `Time.get_ticks_usec()`, publica `/w12/bench`, se cruza con `[vita-prof] physics3d`.

## 3. «El mismo script» PC ↔ Vita

`OS.has_feature("vita")` existe (`pv:os_vita.cpp:178`) [V]. Huecos que tapar:

| Hueco | PC | Vita | Solución |
|---|---|---|---|
| Mensajes tipados | `RosSensorMsgsImu` | no existen | fábrica `Msg.make(tipo)`: `ClassDB.instantiate` / `RosMsg.new().init()` (`ros_msg.cpp:723`) |
| TF broadcaster | sí | no registrado (T-W4-1) | `has_method()` y degradar |
| `PublishQueue` (Thread) | sí | pool a 0, XRCE en hilo principal (W1) | publicar en línea |
| Tasa | 100 Hz | 50 Hz | `const HZ` por `has_feature` |
| Sensores GPU | sí | no | `queue_free()` + aviso en la Vita |

## 4. Sensores reales de la Vita

| Fuente | Estado | Publicaría | Coste |
|---|---|---|---|
| IMU | hecho G7 (`pv:display_server_vita.cpp:262-271`) | Imu 30 Hz BE | ya medido, 59 FPS |
| Panel trasero | port solo lee FRONT (`:107,178`); `sceTouchPeek` ya en el loader (`loader/default_dynlib.c:1282-1284`) [V] | Float32[≤9] 30–60 Hz | S, despreciable |
| Cámaras | `psp2/camera.h:251-288` [V]; sin entradas en el loader [V]; CameraServer de Godot no compila para Vita [V] | JPEG 160×120 troceado | M–L (parche loader + C + relay) |
| GPS | `psp2/gps.h` [V]; solo PCH-1100 3G | NavSatFix 1 Hz | [?] |
| Micrófono | `psp2/audioin.h:52-57` [V], no en el loader | RMS o PCM 32 KB/s | M (hilo C) |

## 5. LT7 — imagen, JPEG, detecciones, inferencia

- **Recepción**: relay trocea JPEG 160×120 q40 (~2–4 KB) en UInt8MultiArray ≤ 488 B con `[frame, idx, total]`; modo degradado mono 80×60 (4,8 KB).
- **JPEG**: libjpeg-turbo enlazado (`tj3Decompress8` en `out/libgodot.so`) [V] ⇒ `Image.load_jpg_from_buffer` debería ir [I]; ~1–2 ms a 160×120, 3,5–7 ms a 320×240, + `ImageTexture.update` 1–3 ms [I]. Hardware: `sceJpegDecodeMJpegYCbCr` (`psp2/jpeg.h:40-60`) [V], requiere parche del loader.
- **Detection2D**: ~450 B por detección [I] ⇒ compacto Float32 `[clase,score,cx,cy,w,h]` ⇒ ≤ 19 por mensaje BE; clases por topic TRANSIENT_LOCAL; dibujo con `draw_rect`/`draw_string` (validados en hardware).
- **Inferencia local**: color en C < 1 ms [I] (en GDScript por píxel, 40–100 ms: no); ArUco/AprilTag 30–80 ms [I] en hilo C; red int8 96×96 20–80 ms con NEON [?]; SSD/YOLO no.

## 6. Alternativas

A1 inferencia en el PC + cajas a la Vita (recomendada) · A2 Vita cámara → PC → cajas · A3 color local en C · A4 simulación completa en PC, Vita visor · A5 LiDAR por DDA en C · A6 sceJpeg · A7 imagen cruda mono.

## 7. Gates

| Gate | Verde |
|---|---|
| G-W12-1 raybench | µs/rayo × 3 variantes; N_max con FPS ≥ 30 sostenido 60 s |
| G-W12-2 sensores portables | mismo `.gd`; `/sim/imu` 50 Hz y `/sim/gps` 10 Hz ±10 %; FPS ≥ 55 |
| G-W12-3 LiDAR 2D | 180 rayos 10 Hz → relay → LaserScan en RViz; hz ≥ 9,5; FPS ≥ 30 |
| G-W12-4 imagen | ≥ 90 % de fotogramas completos en 120 s; decodificación p95 ≤ 5 ms |
| G-W12-5 overlays | 20 cajas 10 Hz; caída de FPS ≤ 5 %; latencia < 150 ms |
| G-W12-6 cámara Vita | `/vita/camara/compressed` ≥ 10 Hz en el PC |
| G-W12-7 panel trasero | 30 Hz, 4 dedos, coordenadas en rango |
| G-W12-8 visión local | detector de color en C ≤ 2 ms a 160×120 |
