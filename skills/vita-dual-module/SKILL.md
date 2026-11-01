---
name: vita-dual-module
description: "Use when creating a new low-level Vita module that touches hardware, memory, or system — scaffolds the dual Rust + C/C++ structure behind a shared C-ABI header with a parity test."
---

## Cuándo usar esta skill

Invocar esta skill **siempre** que se cree un módulo que toque hardware, memoria o sistema embebido en la PS Vita. Esta es una regla transversal del proyecto: todo código de bajo nivel (red, memoria, sensores, transporte micro-ROS, etc.) debe tener dos implementaciones intercambiables. No se crea un módulo de bajo nivel de otra manera.

Ejemplos de módulos que requieren esta skill:
- `net-udp` — sockets `sceNet` (UDP)
- `microros-transport` — los 4 callbacks del transporte micro-ROS
- `mem-pool` — gestión de memoria acotada
- Cualquier wrapper de API de VitaSDK

Los 8 actuales: `mem-pool`, `net-udp`, `microros-transport`, `msg-ring`, `viz-math`, `msg-cdr`,
`tf-tree`, `msg-schema`.

Módulos que **no** requieren esta skill: lógica de alto nivel, UI, código que solo corre en el PC, herramientas de build.

---

## Estructura que genera

Plantilla real: `modules/msg-ring/` y `modules/msg-schema/` (los más recientes). Dentro de
`modules/<nombre>/`:

```
modules/<nombre>/
├── include/<nombre_>.h       # Contrato C-ABI — la única fuente de verdad
├── impl-c/<nombre_>.c        # Implementación C (#ifdef __vita__ para la parte de VitaSDK)
├── impl-rust/
│   ├── Cargo.toml            # crate-type = ["rlib"] + feature `standalone` (por defecto)
│   └── src/lib.rs            # #![no_std], #[unsafe(no_mangle)] pub extern "C" fn ...
├── tests/
│   ├── parity_test.c         # La MISMA batería se enlaza contra C y contra Rust
│   ├── host_common_flags     # (opcional) flags extra para ambos builds, p. ej. -pthread o -I
│   └── host_c_only           # (opcional) .c de módulos de los que depende, solo build C
└── README.md                 # API, diseño, estado («validar en el PC / en hardware»)
```

(`<nombre_>` = nombre con guion bajo: `msg-ring` → `msg_ring.h`.)

**No hay `CMakeLists.txt` por módulo** (solo lo tienen los tres primeros, de la Fase 1) ni
`crate-type = ["staticlib"]` en el `Cargo.toml`. Regla del repo (CLAUDE.md): los crates de módulo
son `rlib`; la staticlib se produce explícitamente con `cargo rustc --crate-type staticlib`, y
**una sola staticlib Rust por binario** (el crate paraguas `vita-app/rust-modules/`).

---

## Pasos a seguir

### Paso 1 — Preguntar nombre y firma

Antes de escribir ningún archivo, preguntar al usuario:

1. **Nombre del módulo** (en kebab-case, p. ej. `net-udp`). El nombre se usa como prefijo en el header y en todos los archivos.
2. **Firma de las funciones públicas**: nombre, parámetros y tipo de retorno de cada función que expone el módulo. Si el usuario no tiene claro aún la firma completa, proponer un conjunto mínimo de funciones que cubra el caso de uso.
3. **Tipos de datos compartidos** (structs, enums, códigos de error) si los hay.

No avanzar al Paso 2 hasta tener estas respuestas. La firma de funciones es el compromiso más importante: cambiarla después obliga a modificar ambas implementaciones y los tests.

### Paso 2 — Escribir el header C como fuente de verdad

Crear `include/<nombre_>.h`. Este archivo es **la única fuente de verdad** del módulo. Define:

- Guards de inclusión (`#ifndef`, `#define`, `#endif`)
- `#ifdef __cplusplus` / `extern "C"` para compatibilidad C++
- Structs y enums necesarios
- Prototipos de todas las funciones públicas con comentarios breves
- Códigos de error como `enum` o `#define`

El header no incluye implementación. Una vez escrito y aprobado por el usuario, no se modifica su API sin actualizar ambas implementaciones y los tests.

### Paso 3 — Generar stub C que compila

Crear `impl-c/<nombre_>.c`:

- Incluye `"<nombre_>.h"`; lo específico de VitaSDK (`<psp2/net/net.h>`, etc.) va bajo `#ifdef __vita__`, con una rama de host POSIX para que la paridad corra en la laptop.
- Cada función del header tiene una implementación stub que compila: puede devolver un valor de error o un placeholder, pero **no** funciones vacías sin `return` cuando el tipo lo requiere.
- El objetivo de este paso es que compile en el host (`tools/run-parity-tests.sh <nombre>`). La lógica real se rellena después.

### Paso 4 — Generar stub Rust `extern "C"` (crate `rlib`)

Crear `impl-rust/Cargo.toml` copiando el de `modules/msg-ring/impl-rust/Cargo.toml`:
`name = "<nombre_>_rust"`, `edition = "2024"`, `[lib] crate-type = ["rlib"]`,
`[features] default = ["standalone"]`, `panic = "abort"` en `release` y `dev`.

Crear `impl-rust/src/lib.rs`:

- `#![no_std]` (los módulos no usan std; así no arrastran pthread/TLS al `.so` de Godot).
- Cada función del header como `#[unsafe(no_mangle)] pub extern "C" fn ...` con tipos FFI
  exactos (`i32`, `u32`, `*mut u8`, `core::ffi::c_void`...); structs compartidos con `#[repr(C)]`.
- `#[panic_handler]` y `rust_eh_personality` **solo** bajo `#[cfg(feature = "standalone")]`
  (ver el final de `modules/msg-ring/impl-rust/src/lib.rs`): el paraguas desactiva la feature y
  aporta el único panic_handler.
- Usuario principiante en Rust: **comentar cada construcción nueva** (y, si procede, en `docs/rust/`).

Comprobar que compila (en el host; el script usa `cargo` local o docker `rust:1-slim`):
`tools/run-parity-tests.sh <nombre>` (hace `cargo rustc --release --crate-type staticlib`).

### Paso 5 — Generar test de paridad

Crear `tests/parity_test.c`:

- Incluye solo `"<nombre_>.h"`; nunca un archivo de implementación.
- Casos que ejercen cada función pública con entradas representativas y bordes; usa
  `IMPL_NAME` (lo define el script: `"c"` o `"rust"`) para los mensajes.
- No compara las dos implementaciones entre sí en ejecución: **cada una pasa la misma batería**.
- Ejecutar: `tools/run-parity-tests.sh <nombre>` (compila `parity_test.c` + `impl-c/*.c` con
  `gcc -Werror`, y luego contra la staticlib de `impl-rust`). Sin `impl-rust/` el script falla
  («módulo dual incompleto»). Al final, `tools/run-parity-tests.sh` sin argumentos: todo verde.

### Paso 5b — Enlazarlo en la Vita (cuando se use desde Godot 4)

1. Añadir el crate al paraguas: dependencia en `vita-app/rust-modules/Cargo.toml` (con
   `default-features = false`) y `pub use <nombre_>_rust;` en `vita-app/rust-modules/src/lib.rs`.
2. Comprobar en el PC que compila PIC para el `.so` de Godot: `tools/build-c-pic.sh` (compila
   todos los `modules/*/impl-c/*.c`) y `tools/build-rust-pic.sh` (paraguas, sin relocaciones
   MOVW/MOVT_ABS); después `tools/check-vita-imports.py --dynlib … --nm $VITASDK/bin/arm-vita-eabi-nm <lib.a>`
   para que todo import esté en la tabla del loader (docs/18 §3).
3. Añadir el módulo a `godot/ros2_vita/SCsub`: su `include/` en `CPPPATH` y su `impl-c/<nombre_>.c`
   en la rama sin `ros2_vita_rust_lib` (con la staticlib Rust, los símbolos ya vienen dentro).
4. Recompilar la plantilla (skill `vita-build-package`).

### Paso 6 — Recordatorio de paridad

Al finalizar el scaffold, recordar explícitamente al usuario:

> **Invariante de paridad:** cualquier lógica que se añada a `impl-c/<nombre_>.c` debe tener su equivalente en `impl-rust/src/lib.rs`, y viceversa. Si una implementación pasa el test de paridad y la otra no, el módulo no está listo. El respaldo C/C++ debe ser siempre equivalente al Rust, no solo un placeholder.

---

## Antipatrón a evitar

**No implementar lógica antes de fijar el header.**

Si se empieza a escribir código en `impl-c/` o `impl-rust/` antes de que el header esté completo y aprobado, es casi seguro que la API cambiará y habrá que rehacer trabajo en ambos sitios. El header es el contrato; el contrato se firma primero.

Señales de que se está cayendo en este antipatrón:
- "Voy a hacer un prototipo rápido en C y después defino el header."
- "El header lo ajusto cuando vea cómo queda la implementación."
- Escribir `impl-c/` sin que exista `include/<nombre_>.h`.
