---
name: vita-dual-module
description: Use when creating a new low-level Vita module that touches hardware, memory, or system — scaffolds the dual Rust + C/C++ structure behind a shared C-ABI header with a parity test.
---

## Cuándo usar esta skill

Invocar esta skill **siempre** que se cree un módulo que toque hardware, memoria o sistema embebido en la PS Vita. Esta es una regla transversal del proyecto: todo código de bajo nivel (red, memoria, sensores, transporte micro-ROS, etc.) debe tener dos implementaciones intercambiables. No se crea un módulo de bajo nivel de otra manera.

Ejemplos de módulos que requieren esta skill:
- `net-udp` — sockets `sceNet` (UDP)
- `microros-transport` — los 4 callbacks del transporte micro-ROS
- `mem-pool` — gestión de memoria acotada
- Cualquier wrapper de API de VitaSDK

Módulos que **no** requieren esta skill: lógica de alto nivel, UI, código que solo corre en el PC, herramientas de build.

---

## Estructura que genera

El scaffold produce la siguiente estructura dentro del directorio `modules/<nombre>/` en el PC de desarrollo:

```
modules/<nombre>/
├── include/<nombre>.h        # Contrato C-ABI — la única fuente de verdad
├── impl-c/<nombre>.c         # Implementación C/C++ sobre VitaSDK
├── impl-rust/
│   ├── Cargo.toml            # crate-type = ["staticlib"], target Vita
│   └── src/lib.rs            # extern "C" + #[no_mangle], compila a staticlib
├── tests/parity_test.c       # Batería de tests que ejerce ambas implementaciones
└── CMakeLists.txt            # Opción -DVITA_IMPL=c|rust selecciona implementación
```

El `CMakeLists.txt` incluye la variable de build `VITA_IMPL` con valores `c` (por defecto) y `rust`. En modo `rust` enlaza el staticlib generado por `cargo-vita`; en modo `c` compila directamente el `.c`.

---

## Pasos a seguir

### Paso 1 — Preguntar nombre y firma

Antes de escribir ningún archivo, preguntar al usuario:

1. **Nombre del módulo** (en kebab-case, p. ej. `net-udp`). El nombre se usa como prefijo en el header y en todos los archivos.
2. **Firma de las funciones públicas**: nombre, parámetros y tipo de retorno de cada función que expone el módulo. Si el usuario no tiene claro aún la firma completa, proponer un conjunto mínimo de funciones que cubra el caso de uso.
3. **Tipos de datos compartidos** (structs, enums, códigos de error) si los hay.

No avanzar al Paso 2 hasta tener estas respuestas. La firma de funciones es el compromiso más importante: cambiarla después obliga a modificar ambas implementaciones y los tests.

### Paso 2 — Escribir el header C como fuente de verdad

Crear `include/<nombre>.h`. Este archivo es **la única fuente de verdad** del módulo. Define:

- Guards de inclusión (`#ifndef`, `#define`, `#endif`)
- `#ifdef __cplusplus` / `extern "C"` para compatibilidad C++
- Structs y enums necesarios
- Prototipos de todas las funciones públicas con comentarios breves
- Códigos de error como `enum` o `#define`

El header no incluye implementación. Una vez escrito y aprobado por el usuario, no se modifica su API sin actualizar ambas implementaciones y los tests.

### Paso 3 — Generar stub C que compila

Crear `impl-c/<nombre>.c`:

- Incluye `"<nombre>.h"` e incluye VitaSDK según necesidad (`<psp2/net/net.h>`, etc.)
- Cada función del header tiene una implementación stub que compila: puede devolver un valor de error o un placeholder, pero **no** funciones vacías sin `return` cuando el tipo lo requiere.
- El objetivo de este paso es que `cmake -DVITA_IMPL=c` compile sin errores. La lógica real se rellena después.

### Paso 4 — Generar stub Rust `extern "C"` que compila a staticlib

Crear `impl-rust/src/lib.rs`:

- `#![no_std]` (la Vita usa newlib, no std de Rust)
- Cada función pública del header se declara con `#[no_mangle]` y `pub extern "C"`, con la firma exacta en tipos FFI (`c_int`, `*mut u8`, `u32`, etc.)
- Devuelve valores de error o placeholder; no implementación real aún.
- `Cargo.toml` declara `crate-type = ["staticlib"]` y el target `armv7-sony-vita-newlibeabihf`.

El objetivo de este paso es que `cargo vita build --release` compile sin errores.

### Paso 5 — Generar test de paridad

Crear `tests/parity_test.c`:

- Incluye `"<nombre>.h"` — no incluye ningún archivo de implementación directamente.
- Contiene casos de test que ejercen cada función pública con entradas representativas.
- Compara la salida contra valores esperados o contra criterios de corrección (no compara las dos implementaciones entre sí en tiempo de ejecución, sino que cada una pasa el mismo conjunto de casos).
- El `CMakeLists.txt` crea dos targets de test: `parity_test_c` (con `VITA_IMPL=c`) y `parity_test_rust` (con `VITA_IMPL=rust`). Ambos deben pasar.

### Paso 6 — Recordatorio de paridad

Al finalizar el scaffold, recordar explícitamente al usuario:

> **Invariante de paridad:** cualquier lógica que se añada a `impl-c/<nombre>.c` debe tener su equivalente en `impl-rust/src/lib.rs`, y viceversa. Si una implementación pasa el test de paridad y la otra no, el módulo no está listo. El respaldo C/C++ debe ser siempre equivalente al Rust, no solo un placeholder.

---

## Antipatrón a evitar

**No implementar lógica antes de fijar el header.**

Si se empieza a escribir código en `impl-c/` o `impl-rust/` antes de que el header esté completo y aprobado, es casi seguro que la API cambiará y habrá que rehacer trabajo en ambos sitios. El header es el contrato; el contrato se firma primero.

Señales de que se está cayendo en este antipatrón:
- "Voy a hacer un prototipo rápido en C y después defino el header."
- "El header lo ajusto cuando vea cómo queda la implementación."
- Escribir `impl-c/` sin que exista `include/<nombre>.h`.
