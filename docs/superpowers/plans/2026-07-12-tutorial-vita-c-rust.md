# Tutorial práctico C/Rust sobre el código real — Plan de implementación

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Construir en la branch `tutorial-vita` un tutorial práctico (`docs/tutorial/`) que enseñe a Jcrex a leer, modificar y compilar por su cuenta el código C y Rust del proyecto, recorriendo el código real con retos verificables.

**Architecture:** Serie de lecciones markdown bajo `docs/tutorial/`, publicadas en la web mediante una colección `tutorial` (glob), integrada en la sección de documentación existente. Cada lección recorre un archivo real del repo (leer → explicar C+Rust → retos → verificar). Los retos se verifican por dos vías: 🐳 host (docker/gcc + `tools/run-parity-tests.sh`) y 🎮 PC/Vita (comandos que ejecuta el usuario). Las soluciones van inline en bloques `<details>` plegables.

**Tech Stack:** Markdown (docs), Astro 5 content collections (web), pnpm, gcc/C11, Rust (docker `rust:1-slim`), VitaSDK (solo en PC), CMake.

## Global Constraints

- Docs, comentarios y mensajes de commit en **español**; subjects con prefijo convencional (`docs(tutorial):`, `feat(web):`).
- **Nunca dejar los parity tests en rojo** en un commit (`tools/run-parity-tests.sh`).
- El **header C es la verdad** de cada módulo dual; C es respaldo permanente de Rust.
- Todo el aprendizaje vive en la branch **`tutorial-vita`**; no se toca `main` ni `docs/06-bitacora-estado.md` ni `web/src/data/fases.ts`.
- El usuario es **principiante en Rust** y punteros/C le cuestan: cada construcción nueva de C (punteros, memoria, structs) y **toda** construcción de Rust se explica; enlazar a `docs/rust/` para profundizar en vez de duplicar.
- Compilación PC/Vita: **siempre la ejecuta el usuario** (por decisión suya). El tutorial da los comandos exactos y marca "validar en el PC / hardware".
- El código de práctica del usuario va en `practica/` (gitignored), nunca dentro de `modules/` ni `vita-app/`.
- Estilo web: los markdown de `docs/` **no** llevan frontmatter; el título sale del primer `# encabezado` y la descripción del primer párrafo (ver `web/src/lib/docs.ts`).

---

## Estructura de archivos

**Se crean:**
- `docs/tutorial/00-guia-del-tutorial.md` — mapa, workflow de retos, dos vías de compilación, patrón dual, registro de progreso.
- `docs/tutorial/01-c-fundamentos-con-mem-pool.md` — lección plantilla (C + mem-pool).
- `docs/tutorial/02-rust-fundamentos-con-mem-pool.md`
- `docs/tutorial/03-net-udp-sockets-y-sdk.md`
- `docs/tutorial/04-microros-transport-integracion.md`
- `docs/tutorial/05-app-vita-el-sdk-y-main.md`
- `docs/tutorial/06-compilar-y-empaquetar-vpk.md`

**Se modifican (una sola vez, en Task 1):**
- `web/src/content.config.ts` — añadir colección `tutorial` + exportarla.
- `web/src/lib/docs.ts` — añadir `tutorial` al tipo unión y al array `seccionesDocs`.
- `web/src/pages/docs/index.astro` — añadir `tutorial` a `colecciones`.
- `.gitignore` — añadir `practica/`.

**NO se toca:**
- `web/Dockerfile` — ya hace `COPY docs/ /app/docs/`, así que `docs/tutorial/` se publica sin cambios.
- `docs/rust/` — se mantiene; el tutorial enlaza a ella.

## Método de entrega (faseo)

- **Task 1** (Fase 0 — Andamiaje) y **Task 2** (Fase 1 — lección 01 plantilla) se construyen **ahora**, completos.
- **Tasks 3–7** (lecciones 02–06) llevan su **checklist de cobertura + reto estrella + verificación** ya concretados a partir del código real, pero se **escriben de una en una, iterando con el usuario a su ritmo** (así lo pidió). No se redactan las 6 de golpe.

---

### Task 1: Andamiaje — guía 00, sandbox de práctica e integración web

**Files:**
- Create: `docs/tutorial/00-guia-del-tutorial.md`
- Modify: `.gitignore`
- Modify: `web/src/content.config.ts`
- Modify: `web/src/lib/docs.ts`
- Modify: `web/src/pages/docs/index.astro`

**Interfaces:**
- Produces: la colección de contenido `tutorial` (clave `'tutorial'`), consumible por `getCollection('tutorial')`; la sección web "Tutorial práctico"; el directorio `docs/tutorial/` donde viven todas las lecciones; el convenio de sandbox `practica/`.

- [ ] **Step 1: Crear la guía 00**

Crear `docs/tutorial/00-guia-del-tutorial.md`. Debe cubrir, en español y sin frontmatter (primer línea `# Tutorial práctico C/Rust — Guía`):

1. **Para quién y qué es**: recorrido del código real con retos; perfil (sabe programar, C/punteros y Rust nuevos); enlaza a `docs/rust/` (referencia) y `docs/03-estrategia-dual-rust-cpp.md` (patrón dual).
2. **Mapa de lecciones**: tabla 00→06 con una línea cada una y el orden mem-pool → net-udp → microros-transport → app Vita → compilar/.vpk.
3. **El patrón dual en 6 líneas**: `modules/*/include/*.h` es la verdad; `impl-c/` e `impl-rust/` la cumplen; ambas pasan la misma paridad.
4. **Las dos vías de compilación** con su leyenda de iconos:
   - 🐳 **Host**: `tools/run-parity-tests.sh [módulo]` (usa docker `rust:1-slim` para Rust; gcc para C). Se corre en la laptop.
   - 🎮 **PC/Vita**: solo compila en el PC (`192.168.1.65`) con VitaSDK; **lo ejecuta el usuario** (su `git pull` + compilar, o SSH que él inicia). El tutorial da los comandos exactos.
5. **Workflow de un reto**: (a) hago el cambio en el archivo real; (b) verifico (parity o gcc directo); (c) para volver al código de referencia: `git checkout -- <archivo>`, o commiteo en mi propia sub-rama de práctica. Recordar la regla: no dejar paridad en rojo si commiteo.
6. **El sandbox `practica/`**: los programas propios de los retos (clientes que usan la API) van en `practica/` en la raíz del repo, que está gitignored; comando genérico de compilación de un cliente C contra un módulo:
   ```bash
   gcc -std=c11 -Wall -I modules/mem-pool/include \
       practica/mi_prueba_pool.c modules/mem-pool/impl-c/mem_pool.c \
       -o practica/mi_prueba_pool && ./practica/mi_prueba_pool
   ```
7. **Registro de progreso**: una tabla/lista al final donde el usuario marca lecciones y retos completados (sustituye a la bitácora, que no se toca en esta branch).

- [ ] **Step 2: Añadir `practica/` a .gitignore**

Añadir al final de `.gitignore`:
```
# Sandbox de práctica del tutorial (código propio de los retos)
practica/
```

- [ ] **Step 3: Registrar la colección `tutorial` en content.config.ts**

En `web/src/content.config.ts`, tras la colección `rust`, añadir:
```ts
// docs/tutorial/*.md — el tutorial práctico C/Rust sobre el código real
const tutorial = defineCollection({
  loader: glob({ pattern: '*.md', base: '../docs/tutorial' }),
});
```
Y cambiar el export a:
```ts
export const collections = { guias, fundacion, adrs, rust, tutorial, codigo };
```

- [ ] **Step 4: Añadir la sección en lib/docs.ts**

En `web/src/lib/docs.ts`, ampliar el tipo `key` de `seccionesDocs` a incluir `'tutorial'`:
```ts
export const seccionesDocs: {
  key: 'fundacion' | 'adrs' | 'rust' | 'tutorial' | 'codigo';
  titulo: string;
  descripcion: string;
}[] = [
```
E insertar la entrada **después** de `rust` y **antes** de `codigo`:
```ts
  {
    key: 'tutorial',
    titulo: 'Tutorial práctico C/Rust',
    descripcion:
      'Recorrido guiado del código real del repo con retos: aprende a leer, modificar y compilar el C y el Rust del proyecto por tu cuenta.',
  },
```

- [ ] **Step 5: Añadir la colección a la página índice de docs**

En `web/src/pages/docs/index.astro`, dentro del objeto `colecciones`, añadir la línea (tras `rust`):
```ts
  tutorial: sortDocs(await getCollection('tutorial')),
```

- [ ] **Step 6: Verificar que la web compila y genera las rutas del tutorial**

Run:
```bash
cd web && pnpm build 2>&1 | tail -30
```
Expected: build sin errores y en el listado de páginas generadas aparece `/docs/tutorial/00-guia-del-tutorial` (o similar). Si `pnpm build` es lento, alternativa de sanidad de tipos: `cd web && pnpm astro sync && pnpm astro check` (esperado: 0 errores).

- [ ] **Step 7: Commit**

```bash
git add docs/tutorial/00-guia-del-tutorial.md .gitignore \
  web/src/content.config.ts web/src/lib/docs.ts web/src/pages/docs/index.astro
git commit -m "feat(tutorial): andamiaje del tutorial C/Rust + integracion web

Guia 00 (mapa, workflow de retos, dos vias de compilacion, sandbox practica/),
coleccion 'tutorial' publicada en la seccion de documentacion de la web.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

### Task 2: Lección 01 — C fundamentos con mem-pool (plantilla)

Esta lección fija el **estilo y ritmo** de todas las demás. Recorre `modules/mem-pool/include/mem_pool.h` y `modules/mem-pool/impl-c/mem_pool.c` (ya leídos: define `struct mem_pool` con `blocks_start/eff_block_size/block_count/blocks_free/free_head`; API `mem_pool_required_size`, `mem_pool_create`, `mem_pool_alloc`, `mem_pool_free`, `mem_pool_blocks_free`, `mem_pool_block_size`; free-list intrusiva, `round_up_align`, detección de doble free O(n)).

**Files:**
- Create: `docs/tutorial/01-c-fundamentos-con-mem-pool.md`

**Interfaces:**
- Consumes: convenios de Task 1 (iconos 🐳/🎮, sandbox `practica/`, `<details>` para soluciones).
- Produces: la lección plantilla que Tasks 3–7 replican en estructura.

- [ ] **Step 1: Escribir el cuerpo de la lección**

Crear `docs/tutorial/01-c-fundamentos-con-mem-pool.md` (primer línea `# Lección 01 — C de bajo nivel leyendo mem-pool`). Cobertura obligatoria, anclada a líneas reales del código:

- **Qué resuelve el módulo** (asignador de bloques fijos, sin `malloc`, buffer aportado por el llamador) — resumen del header.
- **`#include` y el header como contrato**: qué es `mem_pool.h`, `#ifndef` guard, `extern "C"`, el `typedef struct mem_pool mem_pool;` **opaco** (declarado en el header, definido en el `.c`) y por qué eso oculta el layout.
- **Tipos de C precisos**: `size_t`, `uint8_t`, `uintptr_t`, `void*`; por qué se usan (`stdint.h`, `stddef.h`).
- **`struct mem_pool`**: explicar cada campo (líneas 18–24) y que la cabecera **vive dentro del propio backing** (`pool = (mem_pool *)backing`, línea 71).
- **Punteros, el núcleo de la lección**: `uint8_t *` como aritmética byte a byte (`blocks_start + i * eff_block_size`, línea 80); `void **` y la free-list intrusiva (`*(void **)blk = pool->free_head;`, líneas 81–82, 93, 120) — dibujar el encadenado paso a paso.
- **Alineación y bits**: `round_up_align` con máscara `& ~(ALIGN-1)` (línea 28) y el chequeo `(uintptr_t)backing & (ALIGN-1)` (línea 63); explicar por qué 8 bytes.
- **Aritmética segura contra overflow**: `block_count > (SIZE_MAX - HEADER) / eff` (línea 51) y el guard de `effective_block_size` (línea 35).
- **Códigos de estado** (`mem_pool_status`, header 30–35) y el patrón "0 ok / negativo error" del proyecto.
- **Recorrer una lista enlazada**: el bucle de doble-free (líneas 114–118) como patrón `for (cur; cur; cur = *(void**)cur)`.
- Un **enlace** a que la versión Rust de todo esto es la Lección 02 (aún sin escribir; enlazar por nombre de archivo).

- [ ] **Step 2: Añadir los retos con verificación**

En la misma lección, sección "Retos" con estos tres (cada uno con su icono de vía y su solución en `<details>`):

1. 🐳 **Leer y predecir** (sin compilar): dado un pool de `block_size=4, block_count=3`, ¿cuánto devuelve `mem_pool_required_size`? ¿cuál es `eff_block_size`? ¿en qué orden de direcciones salen los 3 `alloc`? Solución en `<details>` con el cálculo (64 + 8*3 = 88; eff=8; salen en orden ascendente de dirección porque `create` encadena de la última a la primera).
2. 🐳 **Escribir un cliente y compilarlo** (reto estrella): crear `practica/mi_prueba_pool.c` que:
   - reserve un `backing` estático alineado (`_Alignas(8) static uint8_t backing[...]` con `mem_pool_required_size`),
   - cree el pool (4 bloques de 16 bytes), imprima `mem_pool_blocks_free` tras crear, tras 3 `alloc`, y tras 1 `free`.
   Dar el comando exacto de compilación (el de la guía 00) y la salida esperada (`4 → 1 → 2`). Solución completa (`.c` íntegro) en `<details>`.
3. 🐳 **Modificar el módulo y re-verificar paridad** (sin romper ABI): instrumentar `mem_pool_alloc` en `impl-c/mem_pool.c` añadiendo `#include <assert.h>` y un `assert(pool->blocks_free <= pool->block_count);` al inicio; correr `tools/run-parity-tests.sh mem-pool` para comprobar que sigue en verde; luego restaurar con `git checkout -- modules/mem-pool/impl-c/mem_pool.c`. Enseña el ciclo modificar→verificar→revertir sin tocar el header ni la firma. Solución/expected en `<details>`: la salida del parity test con ambas implementaciones (C y Rust) OK.

- [ ] **Step 3: Verificar los ejemplos de la lección**

Los ejemplos que la lección afirma deben ser ciertos. Ejecutar:
```bash
tools/run-parity-tests.sh mem-pool 2>&1 | tail -15
```
Expected: termina sin error, con la implementación C y la Rust reportando OK (confirma que el módulo descrito compila y que el reto 3 es reproducible).

Y comprobar el cálculo del reto 1 escribiendo el cliente del reto 2 en el scratchpad y compilándolo:
```bash
gcc -std=c11 -Wall -I modules/mem-pool/include \
    /tmp/mi_prueba_pool.c modules/mem-pool/impl-c/mem_pool.c \
    -o /tmp/mi_prueba_pool && /tmp/mi_prueba_pool
```
Expected: imprime la secuencia `4`, `1`, `2` (valida que la solución del reto 2 es correcta antes de publicarla).

- [ ] **Step 4: Verificar que la lección se publica en la web**

Run:
```bash
cd web && pnpm build 2>&1 | grep -i tutorial | tail -10
```
Expected: aparece la ruta generada de `01-c-fundamentos-con-mem-pool`.

- [ ] **Step 5: Commit**

```bash
git add docs/tutorial/01-c-fundamentos-con-mem-pool.md
git commit -m "docs(tutorial): leccion 01 — C de bajo nivel leyendo mem-pool

Recorrido del header y impl-c/ de mem-pool: punteros, free-list intrusiva,
alineacion, overflow. Retos con solucion inline y verificacion por parity/gcc.

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

**CHECKPOINT con el usuario:** tras esta lección, revisar juntos el estilo/ritmo antes de continuar con 02. Las Tasks 3–7 se escriben de una en una.

---

### Task 3: Lección 02 — Rust fundamentos con mem-pool

**Files:** Create `docs/tutorial/02-rust-fundamentos-con-mem-pool.md`

**Cobertura** (recorriendo `modules/mem-pool/impl-rust/src/lib.rs`, la versión Rust del mismo módulo de Task 2, para comparar 1:1):
- `#![no_std]`/atributos y el `#[unsafe(no_mangle)] pub extern "C"` que produce la ABI C; enlazar a `docs/rust/02-ffi-embebido-y-unsafe.md`.
- Ownership e inmutabilidad por defecto (`let` vs `let mut`) — enlazar `docs/rust/01`.
- Tipos: `usize`/`u8`, `*mut c_void`, `*mut u8`; conversión explícita con `as`.
- `unsafe`: por qué la aritmética de punteros y el reinterpretado de memoria lo exigen; qué garantiza el llamador.
- Comparar cada función Rust con su gemela C de la Lección 01 (tabla lado a lado).
**Retos:**
1. 🐳 predecir la salida de `mem_pool_required_size` en Rust y confirmar que coincide con C (paridad).
2. 🐳 tocar un `mut`/`as` y ver el error del compilador de Rust (aprender a leer errores) — solución = el mensaje esperado.
3. 🐳 correr `tools/run-parity-tests.sh mem-pool` tras un cambio y revertir.
**Verificación:** `tools/run-parity-tests.sh mem-pool` en verde; `cd web && pnpm build` publica la lección.
**Se escribe iterando con el usuario tras el checkpoint de Task 2.**

---

### Task 4: Lección 03 — net-udp: sockets y llamadas al SDK

**Files:** Create `docs/tutorial/03-net-udp-sockets-y-sdk.md`

**Cobertura** (recorriendo `modules/net-udp/include/net_udp.h`, `impl-c/net_udp.c`, `impl-rust/`):
- El **split de plataforma dentro de cada impl**: `#ifdef __vita__` (SDK `sceNet*`) vs rama host (BSD sockets POSIX) — esto es lo que permite testear en la laptop.
- Sockets UDP: `socket/bind/sendto/recvfrom`, structs `sockaddr_in`, byte order (`htons`), no bloqueo.
- Manejo de errores con `errno`/retornos y su mapeo a los códigos del módulo.
- En Rust: FFI a las llamadas del sistema, `unsafe`, buffers.
**Retos:**
1. 🐳 cliente en `practica/` que envíe/reciba un datagrama loopback usando la rama host; compilar y correr.
2. 🐳 parity test de net-udp en verde tras un ajuste, y revertir.
3. 🎮 (usuario) señalar qué línea cambia bajo `__vita__` y qué llamada `sceNet*` sustituye a la POSIX.
**Verificación:** `tools/run-parity-tests.sh net-udp`; `pnpm build`.
**Se escribe iterando con el usuario.**

---

### Task 5: Lección 04 — microros-transport: integración

**Files:** Create `docs/tutorial/04-microros-transport-integracion.md`

**Cobertura** (recorriendo `modules/microros-transport/`):
- Cómo este módulo **compone** los anteriores (usa net-udp; sus flags de test en `tests/host_common_flags`/`host_c_only`).
- El contrato de transporte de micro-ROS/XRCE-DDS: callbacks `open/close/write/read` y las firmas que exige uxr.
- Punteros a función en C y su equivalente en Rust (`extern "C" fn`).
- Por qué su parity test es `host_c_only` en parte (símbolos ya dentro del staticlib Rust).
**Retos:**
1. 🐳 trazar una llamada `write` de principio a fin por las capas.
2. 🐳 parity test del módulo en verde tras un cambio, y revertir.
**Verificación:** `tools/run-parity-tests.sh microros-transport`; `pnpm build`.
**Se escribe iterando con el usuario.**

---

### Task 6: Lección 05 — la app Vita: el SDK y main.c

**Files:** Create `docs/tutorial/05-app-vita-el-sdk-y-main.md`

**Cobertura** (recorriendo `vita-app/src/`: `main.c`, `uxr_glue.c/.h`, `netlog.c/.h`, `teleop.c/.h`, `ui.c`/`viz/`, y `vita-app/rust-modules/`):
- El bucle principal de una app homebrew Vita y las llamadas al **SDK real** (entrada de controles, red, framebuffer/UI, hilos).
- Cómo la app **enlaza el Rust** vía el crate umbrella `vita-app/rust-modules/` (un staticlib Rust por binario) y el FFI Rust→C.
- `netlog` (logging por UDP), `teleop` (mapear controles → cmd_vel), `uxr_glue` (pegamento con micro-ROS).
- Qué de esto es 🎮 solo-PC/Vita y por qué (marcado "validar en el PC / hardware").
**Retos:**
1. 🎮 (usuario) añadir un log `netlog` en un punto de `main.c`, compilar en el PC y verlo en el dashboard `/monitor`.
2. 🎮 (usuario) cambiar un binding de `teleop` y probar en hardware.
**Verificación:** revisión de lectura (no compila en laptop); `pnpm build` publica la lección. Los pasos 🎮 los ejecuta el usuario en el PC.
**Se escribe iterando con el usuario.**

---

### Task 7: Lección 06 — compilar y empaquetar (.vpk)

**Files:** Create `docs/tutorial/06-compilar-y-empaquetar-vpk.md`

**Cobertura** (recorriendo `vita-app/CMakeLists.txt`, `vita-app/scripts/`, `docs/05-setup-entorno-cachyos.md`):
- La toolchain VitaSDK: target `armv7-sony-vita-newlibeabihf`, `newlib` (no Linux).
- CMake de la app paso a paso: cómo se declaran fuentes C, cómo se enlaza el staticlib Rust, cómo se produce el `.vpk`.
- El cross-compile de Rust a la Vita: `cargo +nightly rustc -Zbuild-std=std,panic_abort --target ...` (enlazar `docs/rust/00`).
- El ciclo completo del usuario: `git pull` en el PC → build → `.vpk` → instalar en la Vita → ver en `/monitor`.
**Retos:**
1. 🎮 (usuario) compilar la app entera en el PC desde cero siguiendo la lección y generar el `.vpk`.
2. 🎮 (usuario) instalar y arrancar en la Vita, confirmando el nodo ROS2 vivo.
**Verificación:** `pnpm build` publica la lección; los retos 🎮 los ejecuta y confirma el usuario en PC/hardware.
**Se escribe iterando con el usuario. Cierra el tutorial.**

---

## Self-Review

**Cobertura del spec:**
- Estructura de carpetas y orden → Tasks 1–7. ✅
- Formato invariante (leer→explicar→retos→verificar) → Task 2 lo fija; Tasks 3–7 lo replican. ✅
- Perfil del alumno (C/punteros + Rust nuevos) → Task 2 Step 1 (punteros a fondo), Task 3 (Rust desde cero). ✅
- Dos vías de compilación (🐳/🎮) → Task 1 Step 1.4 + iconos en todos los retos. ✅
- Compilación PC/Vita la hace el usuario → Global Constraints + Tasks 6–7 retos 🎮. ✅
- Cobertura (módulos + app Vita; fuera MCP/web-como-tema) → Tasks 2–7; MCP/web no tienen tarea (correcto, están fuera de alcance). ✅
- Publicación web (colección + sección; Dockerfile) → Task 1 Steps 3–5; aclarado que el Dockerfile NO cambia (ya copia `docs/`). ✅
- Soluciones → inline en `<details>` (opción "y/o" del spec); sin carpeta `soluciones/` separada para mantenerlo DRY. ✅ (refinamiento dentro de la latitud del spec)
- No tocar bitácora/fases de main → Global Constraints + Task 1 Step 1.7 (progreso dentro del tutorial). ✅
- Relación con docs/rust → enlaces en Tasks 2–7. ✅
- Entrega faseada → sección "Método de entrega" + checkpoint en Task 2. ✅

**Placeholder scan:** sin TBD/TODO. Tasks 3–7 no son placeholders: llevan archivos exactos, checklist de cobertura anclado a rutas reales, retos concretos y comando de verificación; se marcan "se escribe iterando" por decisión de método del usuario, no por falta de definición.

**Consistencia de tipos/nombres:** clave de colección `'tutorial'` idéntica en content.config.ts, lib/docs.ts, index.astro. Nombres de archivo de lección consistentes entre estructura y tasks. Funciones de mem-pool citadas coinciden con el header real leído.
