---
title: "Informe 03 — Mapa de Rust"
description: "Dónde está implementado Rust en el proyecto, qué binarios lo usan y qué huecos quedan."
fecha: 2026-11-01
---

# Mapa de Rust

## Conceptos en una línea

- **Crate**: la unidad de compilación de Rust (una carpeta con `Cargo.toml`).
- **rlib**: formato interno de Rust para que un crate use a otro.
- **staticlib**: un `.a` como los de C, que gcc puede enlazar.
- **FFI**: llamar entre lenguajes; aquí, funciones `extern "C"` con el nombre exacto de la cabecera.
- **Paraguas**: `vita-app/rust-modules/`, un crate que junta los 8 módulos en **un solo** `.a`.

## Dónde está Rust y dónde se usa

| Módulo | Rust completo | Paridad | Quién lo llama |
|---|---|---|---|
| net-udp | sí (único con rama Vita) | verde | vita-app, ros2_vita |
| microros-transport | sí | verde | vita-app, ros2_vita |
| msg-schema | sí | verde | ros2_vita |
| msg-ring | sí | verde | se compila en ros2_vita, **nadie lo llama** |
| mem-pool, viz-math, msg-cdr, tf-tree | sí | verde | **nadie** |

Paridad: 16/16 en verde (8 módulos × C y Rust), ejecutado el 2026-11-01.

| Binario | Por defecto | ¿Rust en hardware? |
|---|---|---|
| `vita-app` `.vpk` (`-DVITA_IMPL=c\|rust`) | **C** | sí (julio 2026) |
| Plantilla Godot 4 (`RUST_PIC_LIB=…`) | **C** | no: G3 pasó en Rust, G4–G6 se hicieron en C |
| Godot 3.5 (histórico) | C | no |

```
modules/*/impl-rust (rlib) → rust-modules (paraguas) → cargo rustc --crate-type staticlib
   ├─ estático + std → vita-app .vpk
   └─ PIC + core (tools/build-rust-pic.sh) → libgodot.so
```

## Huecos

1. `tools/run-parity-tests.sh` **falla en el PC** si no le dices qué toolchain usar. Funciona así (fish):
   ```fish
   set -x RUSTUP_HOME $PWD/toolchains/rustup; set -x CARGO_HOME $PWD/toolchains/cargo
   set -x RUSTUP_TOOLCHAIN nightly; tools/run-parity-tests.sh
   ```
2. `vizm_quat_identity` no tiene prueba de paridad (buen reto corto).
3. Falta probar en hardware la plantilla Godot 4 en Rust.
4. Cuatro módulos y medio sin consumidor: código probado que ningún binario ejecuta.
5. Docs desfasadas: `docs/rust/01` dice que no se usan `Result` ni genéricos (sí se usan); varios sitios dicen «los
   tres módulos» (son 8); `docs/03` describe una selección por módulo que ya no existe.
6. La serie `docs/rust/` no explica: `safe fn` dentro de `unsafe extern`, la edición 2024, enlazar libm, `align(4096)`,
   `default-features = false` y PIC/`-Zbuild-std` (tarea T8.4).

Detalle con archivo:línea: `docs/ia/auditoria/03-mapa-rust.md`.

## Comprueba que lo has entendido

1. ¿Por qué los crates de módulo son `rlib` y no `staticlib`? (Pista: `panic_handler` y el paraguas.)
2. Si compilas `vita-app` sin opciones, ¿qué implementación de `net-udp` lleva el `.vpk`? ¿Qué cambiarías para usar Rust?
3. ¿Por qué la plantilla de Godot necesita Rust **PIC** y la `vita-app` no?
