# `godot/` — módulo `ros2_vita` para Godot 4 (godot4-vita 4.8-dev7)

> **Estado: SIN COMPILAR NI EJECUTAR.** La laptop no pudo compilar el motor de terceros (el
> entorno bloqueó ejecutar los scripts de SCons de ese repositorio) y no hay Vita conectada.
> Todo lleva el marcador **validar en el PC / en hardware**. Decisión y razones:
> `docs/adr/0008-godot-via-modulo-estatico.md`; investigación y plan: **`docs/18-migracion-a-godot4.md`**.

## Qué es

Un módulo C++ **estático** del motor (la Vita no admite GDExtension) que expone a GDScript la API de
[`rclgd`](https://github.com/Ozuba/rclgd) (`docs/17`): `RosNode`, `RosPublisher`, `RosSubscriber`,
`RosTimer`, `RosQoS`, `RosMsg` y el singleton `rclgd` — para que **el mismo script corra en el PC
(rclgd, Godot 4.7.1) y en la Vita (`ros2_vita`, 4.8-dev7)**. Tabla de paridad: `ros2_vita/API_PARITY.md`.

```
GDScript ── RosNode / RosPublisher / RosSubscriber / RosMsg ──►  ros_runtime.cpp / ros_msg.cpp
                                                                    │ msg-schema (CDR guiado por esquema)
                                       transporte intercambiable ◄──┘ modules/ (C o Rust, header C único)
                                         loopback (host)  |  xrce (Vita, pendiente)
```

## Contenido

| Ruta | Qué es |
|---|---|
| `ros2_vita/` | El módulo: `config.py`, `SCsub`, `register_types.*`, `ros_msg.*` (mensajes dinámicos), `ros_runtime.*` (singleton, nodo, pub/sub/timer, transportes) |
| `ros2_vita/API_PARITY.md` | rclgd ↔ Vita, método a método |
| `test/` | Pruebas de host en GDScript (`runner.gd`) + `run_host_tests.sh` |
| `loader-patches/0001-ros2-vita-imports.patch` | Imports que faltan en `default_dynlib.c` del loader (red y helpers); **aplica en `d1a5f29`** |
| `../tools/build-godot-template.sh` | Receta completa: clonar, parchear, compilar con el módulo, verificar, empaquetar |
| `../tools/build-rust-pic.sh` | Staticlib Rust PIC `core` para enlazar en `libgodot.so` (opcional) |
| `../tools/check-vita-imports.py` | Comprueba los imports de cualquier `.a/.o` contra la tabla del loader |

## Puertas de verificación (docs/18 §8)

1. **G1 — host (PC):** compilar el módulo con un Godot de host y correr las pruebas:
   ```bash
   cd <godot4-vita>
   python3 -m SCons platform=linuxbsd target=editor custom_modules=<repo>/godot \
        x11=no wayland=no vulkan=no opengl3=no
   godot/test/run_host_tests.sh <godot4-vita>/bin/godot.linuxbsd.editor.x86_64
   ```
   Prueba: `RosMsg` ↔ CDR **bit a bit** con los 24 tipos de `modules/msg-schema/tests/fixtures`,
   propiedades anidadas, pub/sub por *loopback*, timers, parámetros y ejes.
2. **G2/G3 — PC (cruzada):** `tools/build-godot-template.sh` (necesita VitaSDK, SCons, VitaGL parcheado).
3. **G4+ — Vita:** `.pck` mínimo, luego transporte XRCE, luego HMI piloto.

## Reglas heredadas de rclgd (mantener)
- Callbacks de suscripciones y timers: **hilo principal** (`process_frame`).
- Los objetos `Ros*` son `RefCounted`: **guardar la referencia** o se cancelan.
- Convención de ejes REP-103 ↔ Godot idéntica (`rclgd.godot_to_ros_vector`...).
- Los *arrays* de un mensaje son copias: asignar el array entero.

## Pendientes (docs/18 §10)
M5 compilar en host · M6 cruzada · M7 red + transporte XRCE · M8 exportación de `.rsch` y clases sombra ·
M9 HMI piloto · M10 panel trasero/cámara · M11 TF · M12 servicios · M15 sesgo 4.7.1↔4.8-dev7.

> La versión anterior de este directorio apuntaba a Godot 3.5 (`godot-vita`): se descartó el 2026-10-27
> porque `rclgd` exige Godot 4 (`Callable`/`await`). Sigue en el historial de git.
