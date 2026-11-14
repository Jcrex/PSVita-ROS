# Tutorial práctico C/Rust — Guía

Bienvenido al tutorial de aprendizaje del proyecto **PS Vita ↔ ROS2**. No es
un curso general de C ni de Rust: es un **recorrido guiado del código real de
este repositorio**, con retos para que aprendas modificándolo. El objetivo es
que llegues a **leer, cambiar y compilar por tu cuenta** el código, sin
depender del asistente.

## Para quién es (y de qué se parte)

Está calibrado para alguien que **ya sabe programar** (lógica, funciones en
algún lenguaje) pero para quien **los punteros y la memoria en C son terreno
nuevo**, y **todo Rust** es nuevo. Por eso:

- Cada concepto nuevo de C de bajo nivel (punteros, memoria, structs,
  alineación) se explica con calma.
- **Toda** construcción de Rust se explica la primera vez que aparece.
- Cuando quieras profundizar en una construcción concreta más allá de lo que
  necesita la lección, se enlaza a la serie de **referencia** ya existente en
  [`docs/rust/`](../rust/00-herramientas-y-ecosistema.md), en vez de duplicarla.

Antes de empezar conviene ojear el porqué de la arquitectura:
[`docs/03-estrategia-dual-rust-cpp.md`](../03-estrategia-dual-rust-cpp.md).

## Mapa de lecciones

El orden va de lo más autocontenido a lo más integrado, terminando en cómo se
compila y se lleva a la Vita.

| # | Lección | Qué aprendes |
|---|---|---|
| 00 | Esta guía | Cómo usar el tutorial, compilar y verificar retos |
| 01 | C de bajo nivel leyendo **mem-pool** | Punteros, memoria, structs, free-list, compilar C |
| 02 | Rust fundamentos con **mem-pool** | Ownership, `unsafe`, FFI; el mismo módulo en Rust |
| 03 | **net-udp**: sockets y el SDK | Sockets UDP, el split host/Vita, errores |
| 04 | **microros-transport**: integración | Cómo se componen los módulos; callbacks/punteros a función |
| 05 | La app Vita: el SDK y `main.c` | Bucle principal, controles, red, enlazar Rust en la app |
| 06 | Compilar y empaquetar (`.vpk`) | VitaSDK, CMake, cross-compile, instalar en la Vita |

El orden de los módulos es **mem-pool → net-udp → microros-transport → app
Vita → compilar/empaquetar**.

## El patrón dual en 6 líneas

Todo módulo de bajo nivel de este repo existe **dos veces**:

- `modules/<mod>/include/<mod>.h` — el **header C es la verdad** del módulo:
  define exactamente qué funciones hay y qué hacen.
- `modules/<mod>/impl-c/` y `modules/<mod>/impl-rust/` — dos implementaciones
  que **cumplen ese mismo header**.
- Ambas deben pasar la **misma** batería de tests de paridad. C/C++ es el
  respaldo permanente: nunca queda desactualizado respecto a Rust.

Por eso este tutorial lee el **header primero** y luego las dos
implementaciones: entender el contrato antes que los detalles.

## Las dos vías de compilación

Cada reto lleva un icono que te dice **dónde se compila**:

- 🐳 **Host** — código de los módulos (C y Rust). Compila y se verifica en
  **cualquier máquina** (tu laptop incluida) porque cada implementación tiene
  una rama "host" además de la rama Vita. La herramienta es:

  ```bash
  tools/run-parity-tests.sh            # todos los módulos
  tools/run-parity-tests.sh mem-pool   # solo uno
  ```

  Compila la versión C con `gcc` y la versión Rust con `cargo` (si no hay
  `cargo` local, usa **docker** `rust:1-slim` automáticamente, para no
  instalar toolchains en la laptop). Si termina sin error y ambas
  implementaciones reportan OK, tu cambio mantiene la paridad.

- 🎮 **PC/Vita** — código específico de la consola (llamadas al SDK,
  `vita-app/`, el `.vpk`). Esto **solo** compila en el PC CachyOS
  (`192.168.1.65`) con **VitaSDK**, y **lo ejecutas tú** (tu flujo habitual de
  `git pull` en el PC + compilar, o un SSH que inicies tú). El tutorial te da
  siempre los comandos exactos, y el código que solo aplica ahí va marcado
  «validar en el PC / hardware».

## Workflow de un reto

1. **Haz el cambio** en el archivo real que indica el reto.
2. **Verifica**:
   - retos 🐳: corre el parity test del módulo, o compila tu programa de
     prueba con `gcc` (ver más abajo);
   - retos 🎮: ejecuta en el PC los comandos que da la lección.
3. **Vuelve al código de referencia** cuando termines. Como este código está
   versionado en git, deshacer es trivial:

   ```bash
   git checkout -- <archivo_que_tocaste>     # descarta tu cambio
   ```

   Si quieres **conservar** un experimento, haz commit en tu propia sub-rama
   (`git checkout -b practica/mi-experimento`) en vez de en `tutorial-vita`.

> **Regla de oro del proyecto:** nunca dejes los tests de paridad en rojo en
> un commit. Si un reto rompe la paridad a propósito, revierte antes de
> commitear (o quédate solo en tu sub-rama de práctica).

## El sandbox `practica/`

Muchos retos te piden **escribir un programa propio** que use la API de un
módulo (por ejemplo, un cliente que crea un pool y pide bloques). Esos
programas van en una carpeta `practica/` en la raíz del repo, que está
**gitignored** (no se commitea, es tu terreno de juego).

Para compilar un cliente C contra un módulo, enlazas tu `.c` con la
implementación C del módulo y le indicas dónde está el header:

```bash
gcc -std=c11 -Wall -I modules/mem-pool/include \
    practica/mi_prueba_pool.c modules/mem-pool/impl-c/mem_pool.c \
    -o practica/mi_prueba_pool && ./practica/mi_prueba_pool
```

- `-I modules/mem-pool/include` — dónde buscar `#include "mem_pool.h"`.
- El segundo `.c` (`.../impl-c/mem_pool.c`) aporta el **código** de las
  funciones que tu programa llama; sin él, el enlazador se queja de símbolos
  no definidos.
- `-o` — nombre del ejecutable resultante.

## Mi progreso

Marca aquí lo que vayas completando (esta tabla sustituye a la bitácora del
proyecto, que no se toca en esta rama de aprendizaje).

| Lección | Leída | Retos hechos | Notas |
|---|---|---|---|
| 01 — C con mem-pool | ☐ | ☐ | |
| 02 — Rust con mem-pool | ☐ | ☐ | |
| 03 — net-udp | ☐ | ☐ | |
| 04 — microros-transport | ☐ | ☐ | |
| 05 — app Vita | ☐ | ☐ | |
| 06 — compilar y .vpk | ☐ | ☐ | |
