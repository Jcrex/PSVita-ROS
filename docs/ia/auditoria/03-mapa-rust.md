# Auditoría 03 — Mapa de Rust en todo el proyecto (para la IA)

Fecha: 2026-11-01 · Equipo: MAPA DE RUST · Modo: solo lectura (salvo este informe y su versión corta
`docs/informes/03-mapa-rust.md`). Rama: `ccr-44e2db2a-mr6xqr`, HEAD `d3e7c12` + cambios sin commit (no tocan Rust).
Excluidos: `godot/rclgd/`, `toolchains/`, `target/`, `.git/`.

Leyenda: **[V]** verificado en esta auditoría (comando o lectura de archivo:línea) · **[D]** según la documentación
del repo, no re-verificado · **[H]** hipótesis.

---

## 0. Resumen ejecutivo

- Rust vive **solo** en 9 crates: los 8 `modules/*/impl-rust/` y el paraguas `vita-app/rust-modules/` **[V]**
  (`git ls-files | grep -E 'Cargo.toml|\.rs$'`). No hay Rust en `godot/`, `tools/`, `mcp/`, `web/` ni `skills/`.
- **Los 8 módulos tienen Rust completo** respecto a su cabecera: 0 funciones de la cabecera faltan en Rust y
  Rust no exporta nada extra salvo `rust_eh_personality` **[V]** (comparación de nombres cabecera ↔ `#[unsafe(no_mangle)]`).
- **Paridad: 16/16 verde** (8 módulos × C y Rust) el 2026-11-01 en el PC **[V]** — `tools/run-parity-tests.sh`,
  con el nightly de `toolchains/` (ver §2.2: el script falla tal cual en el PC).
- **Por defecto ningún binario usa Rust**: `vita-app` (`VITA_IMPL=c`, `vita-app/CMakeLists.txt:26`), `ros2_vita`
  (sin `ros2_vita_rust_lib` compila los `.c`, `godot/ros2_vita/SCsub:50-70`), Godot 3.5 (`microros_impl=c`,
  `godot/godot35/modules/microros/SCsub:38`). Rust es la alternativa seleccionable en build.
- **Rust en hardware**: solo la `vita-app` Fase 1 (`.vpk` Rust, 2026-07-01, `docs/06-bitacora-estado.md:505-512`) **[D]**.
  En Godot 4 la plantilla Rust pasó `verify_runtime.py` (G3) pero **G4–G6 en hardware se hicieron con C**
  (`docs/18-migracion-a-godot4.md:257-261`) **[D]**.
- **Código Rust muerto en la práctica**: `mem-pool`, `viz-math`, `msg-cdr`, `tf-tree` no los llama ningún binario;
  `msg-ring` se enlaza en `ros2_vita` pero nadie lo llama (§4.2) **[V]**.

---

## 1. Inventario de crates

Todos: `edition = "2024"`, `crate-type = ["rlib"]`, `panic = "abort"` en release y dev, feature `standalone`
(por defecto) que aporta `#[panic_handler]` + `rust_eh_personality` bajo `#[cfg(feature = "standalone")]`.
Todos `#![no_std]`, sin `alloc`, sin dependencias externas (solo dependencias de ruta entre crates propios).
`Cargo.lock` versionado en los 9 crates.

| Crate (ruta) | Líneas (total / código*) | C equivalente | Deps de ruta | `unsafe` | `no_mangle` | `cfg(target_os="vita")` | Notas |
|---|---|---|---|---|---|---|---|
| `mem_pool_rust` (`modules/mem-pool/impl-rust`) | 249 / 144 | 134 | — | 15 | 8 (6 API + 2 standalone) | 0 | `Cargo.toml` con comentarios largos de referencia |
| `net_udp_rust` (`modules/net-udp/impl-rust`) | 496 / 380 | 296 | — | 26 | 7 | **13** | único con rama Vita: `mod` con `sceNet*` importados, `NET_POOL` de 1 MiB `#[repr(C, align(4096))]` (`lib.rs:95,145-153`) |
| `microros_transport_rust` (`modules/microros-transport/impl-rust`) | 137 / 102 | 84 | `net_udp_rust` (`default-features=false`) | 12 | 6 | 0 | `UnsafeCell` + `unsafe impl Sync` (`lib.rs:30-34`) |
| `msg_ring_rust` (`modules/msg-ring/impl-rust`) | 229 / 181 | 154 | — | 18 | 9 | 0 | atómicos SPSC (`AtomicU32`, `Ordering`) |
| `viz_math_rust` (`modules/viz-math/impl-rust`) | 391 / 319 | 233 | — | 48 | 22 | 0 | importa libm con `unsafe extern "C" { safe fn sqrtf… }` (`lib.rs:19-24`) |
| `msg_cdr_rust` (`modules/msg-cdr/impl-rust`) | 463 / 375 | 303 | — | 17 | 6 | 0 | `Result` + `?`, slices; exporta tipos `TfMessage`/`Transform` para `tf-tree` |
| `tf_tree_rust` (`modules/tf-tree/impl-rust`) | 302 / 255 | 223 | `viz_math_rust`, `msg_cdr_rust` | 18 | 9 | 0 | usa API Rust de otros crates (`lib.rs:13-14`), `CStr`, `iter().position` (`lib.rs:73`) |
| `msg_schema_rust` (`modules/msg-schema/impl-rust`) | 651 / 585 | 512 | — | 45 | 10 | 0 | `macro_rules! cb` (`lib.rs:316`), callbacks C en struct, recursión |
| `vita_modules_rust` (`vita-app/rust-modules`) | 29 / 15 | — | los 8 con `default-features=false` | 1 | 1 | 0 | `pub use` de los 8 + el ÚNICO `panic_handler` (`src/lib.rs:13-29`) |

\* «código» = total − líneas que empiezan por `//` − líneas en blanco (aprox.). Ningún crate tiene `#[test]`:
la única batería es el `tests/parity_test.c` en C de cada módulo **[V]**.

Tipos producidos: **ningún `staticlib`/`bin`/`cdylib` declarado**. Los `.a` salen siempre de
`cargo rustc --crate-type staticlib` en: `tools/run-parity-tests.sh:28,35` (por módulo, host),
`vita-app/CMakeLists.txt:79-80` (paraguas, Vita estático), `tools/build-rust-pic.sh:22-23` (paraguas, Vita PIC),
`godot/godot35/scripts/build-vita-template.sh:40` (paraguas, histórico) y los `CMakeLists.txt` de
`mem-pool`/`net-udp`/`microros-transport` (por módulo; ver §4.3).

## 2. Paridad por módulo

### 2.1 Cobertura cabecera ↔ Rust ↔ test

| Módulo | Funciones en cabecera | Faltan en Rust | Sin probar en `parity_test.c` |
|---|---|---|---|
| mem-pool | 6 | 0 | 0 |
| net-udp | 6 | 0 | 0 (rama Vita no ejecutable en host) |
| microros-transport | 5 | 0 | 0 |
| msg-ring | 8 | 0 | 0 |
| viz-math | 21 | 0 | **`vizm_quat_identity`** |
| msg-cdr | 5 | 0 | 0 |
| tf-tree | 8 | 0 | 0 |
| msg-schema | 9 (incl. `msg_prim_size`) | 0 | 0 |

Método **[V]**: `grep -oE` de los prefijos de cada módulo en `include/*.h` vs `fn` tras `#[unsafe(no_mangle)]` en
`lib.rs` vs `grep -w` en el test. Es por nombre, no por firma; las firmas las garantiza que el test C compile y
enlace contra ambos `.a` con `-Wall -Wextra -Werror`.

### 2.2 Ejecución del test (2026-11-01, PC CachyOS)

```
RUSTUP_HOME=$PWD/toolchains/rustup CARGO_HOME=$PWD/toolchains/cargo RUSTUP_TOOLCHAIN=nightly tools/run-parity-tests.sh
→ 8 módulos × [impl=c] y [impl=rust]: «OK: todos los casos pasaron» · «OK: paridad verificada» (exit 0)
```

Hallazgo **[V]**: lanzado tal cual en el PC, **falla** tras el C de `mem-pool`: el `cargo` del PATH es el proxy
de rustup de `toolchains/cargo/bin/cargo` sin toolchain por defecto («rustup could not choose a version of cargo»).
`run-parity-tests.sh:27` prefiere `cargo` local si existe y nunca cae a docker en ese caso, y no pasa `+nightly`.
Arreglos posibles (no aplicados): `rustup default nightly` en ese RUSTUP_HOME, que `tools/env-devpc.{sh,fish}`
exporte `RUSTUP_TOOLCHAIN`, o que el script pruebe `cargo --version` antes de elegir local. En la laptop
(sin cargo) usa docker `rust:1-slim` **[D]**.

Cómo funciona el script (`tools/run-parity-tests.sh`): por cada `modules/*/` compila `parity_test.c` + `impl-c/*.c`
(+ `tests/host_c_only`) con gcc y lo ejecuta; luego `cargo rustc --release --crate-type staticlib` en `impl-rust/`
(feature `standalone` activa ⇒ el `.a` trae su `panic_handler`), enlaza el mismo test contra `target/release/lib*.a`
(+ `tests/host_common_flags`, p. ej. `-lm`) y lo ejecuta. Falla si falta `impl-rust/` (`:89-91`). Solo prueba la
**rama host**; la rama `#[cfg(target_os = "vita")]` de `net-udp` solo se valida en hardware.

## 3. Uso real: crate → staticlib → binario

```
modules/<m>/impl-rust  (rlib ×8, no_std)
   │ standalone=on                      │ default-features=false (dependencias de ruta)
   ▼                                    ▼
 cargo rustc --crate-type staticlib   vita-app/rust-modules  (rlib paraguas, único panic_handler)
 (host x86_64, run-parity-tests.sh)     │
   ▼                                    ├─(A) vita-app/CMakeLists.txt:72-87  [-DVITA_IMPL=rust; defecto c]
 build-host/<m>-parity-rust             │     -Zbuild-std=std,panic_abort, reloc. static
                                        │     → rust-modules/target/armv7-sony-vita-newlibeabihf/release/libvita_modules_rust.a
                                        │     → vita-ros2-hello.velf → .vpk   (Rust probado en hardware 2026-07-01)
                                        │
                                        ├─(B) tools/build-rust-pic.sh  [-Zbuild-std=core, -C relocation-model=pic]
                                        │     → toolchains/pic/rust-target/armv7-…/release/libvita_modules_rust.a
                                        │     → RUST_PIC_LIB=… tools/build-godot-template.sh:72 → scons ros2_vita_rust_lib=…
                                        │     → godot/ros2_vita/SCsub:50-54 (sustituye msg-schema, msg-ring, net-udp,
                                        │       microros-transport .c) → libgodot.so → out-rust/vita_release.zip
                                        │     (G3 verify_runtime PASS 650 imports; NO usado en G4–G6: hardware = C)
                                        │
                                        └─(C) godot/godot35/…/SCsub:38-43 microros_impl=rust (HISTÓRICO; su G4 Rust «no se hará»,
                                              docs/06:376-377)
```

| Binario | Selector | Por defecto | Módulos que realmente llama | Rust validado |
|---|---|---|---|---|
| `vita-app` `.vpk` (Fase 1 teleop/VIZ) | `-DVITA_IMPL=c\|rust` (`CMakeLists.txt:26`) | **C** | `net-udp`, `microros-transport` (grep en `vita-app/src`) | **hardware** (2026-07-01) **[D]** |
| `libgodot.so` / `vita_release.zip` (ros2_vita, G4–G7) | `ros2_vita_rust_lib=` / `RUST_PIC_LIB=` | **C** | `msg-schema`, `net-udp`, `microros-transport` (`msg-ring` compilado pero sin llamadas) | `verify_runtime.py` PASS (G3), **no en hardware** |
| `libgodot` host (G1, pruebas GDScript) | mismo SCsub | C | ídem (sin XRCE si no hay libs host) | **[H]** nunca probado con Rust en host |
| Godot 3.5 template (histórico) | `microros_impl=` | C | `mem-pool`, `net-udp`, `microros-transport` | no |
| Binarios de paridad (host) | — | ambos | cada módulo | sí, 16/16 |

Diferencias de compilación (A) vs (B): `docs/18-migracion-a-godot4.md:125-132`. Riesgo conocido de (B): 31 símbolos
de `compiler_builtins` (`__aeabi_*`, `floor`, `sqrt`…) quedan definidos dentro del `.so` y los usa todo el motor
(`docs/18:257-261`), motivo por el que el hardware usa C.

## 4. Huecos

### 4.1 Rust que podría usarse y no se usa
1. **Plantilla Godot 4 Rust en hardware**: falta una prueba G5/G6 con `out-rust/` y medir `sqrt/floor`
   (`docs/18:261` lo pide). Es el uso Rust de mayor valor pendiente.
2. **App Rust completa (`cargo-vita`, modo B de `docs/15` §2)**: T8.3 pendiente (`docs/19:203`); candidato natural
   `hwprobe` en Rust (`docs/15` §8).
3. **Backlog `docs/15` §8** sin empezar: `thread-pool`, `frame-arena`, `vita-safe`.
4. `docs/19:125` T2.3.6 «¿versión dual Rust?» del transporte XRCE de `ros2_vita` (hoy `xrce_transport.cpp`, solo C++).
5. Pruebas unitarias Rust (`#[test]`, `cargo test`) inexistentes: toda la verificación pasa por el harness C. **[H]**
   Útil para lógica interna no exportada (p. ej. `parse_ipv4` de `net-udp`).

### 4.2 Código Rust muerto o sin consumidor
| Crate | Situación | Evidencia |
|---|---|---|
| `mem_pool_rust` | en el paraguas, nadie llama `mem_pool_*` (ni `vita-app/src` ni `ros2_vita`) | `git grep mem_pool_` fuera de `modules/` y docs: solo el paraguas |
| `viz_math_rust`, `msg_cdr_rust`, `tf_tree_rust` | en el paraguas «para validar que compila» (`vita-app/rust-modules/Cargo.toml:25-26`); `vita-app/src/viz/` no los usa | ídem |
| `msg_ring_rust` | en el paraguas y en `ros2_vita` (C), pero `ros2_vita` encola con su propio `inbox` + `MutexLock` (`godot/ros2_vita/ros_runtime.cpp:462-470`) | `API_PARITY.md:29` dice «cola `msg-ring`»: **desfasado** [V] |
| Las mitades C de esos módulos | igual de muertas fuera de los tests | — |

No es «código muerto» en el sentido de ilegible: está probado por paridad y es la base de Objetivos 3/4 / G7, pero
**ningún binario lo ejecuta**. Coste en tamaño probablemente nulo: el linker descarta del `.a` los objetos no
referenciados **[H]** (no medido).

### 4.3 Restos de build
- `modules/{mem-pool,net-udp,microros-transport}/CMakeLists.txt` implementan la selección por módulo de `docs/03`
  §«Selección en build time», pero **nada los incluye** (`git grep add_subdirectory` vacío) **[V]**. La app usa el
  paraguas. Los otros 5 módulos no tienen `CMakeLists.txt`. `docs/03:36-52` describe un diseño que ya no es el real
  (dice «cargo-vita» y «el CMakeLists de cada módulo»).
- `run-parity-tests.sh` y toolchain local: ver §2.2.

### 4.4 Documentación desfasada respecto al código
| Lugar | Dice | Realidad |
|---|---|---|
| `docs/rust/01-el-lenguaje-en-este-repo.md:143-148` | el repo «no usa» `Result`+`?`, genéricos, lifetimes, hilos | `msg-cdr`/`msg-schema` usan `Result`+`?` (docs/rust/04, 05), genéricos const (04), atómicos (03) |
| `docs/rust/02-ffi-embebido-y-unsafe.md:113-116` | el paraguas re-exporta «los tres módulos» | 8 (`vita-app/rust-modules/src/lib.rs:13-20`) |
| `docs/rust/00-herramientas-y-ecosistema.md:93` | «los tres `Cargo.toml` de módulos» | 8 |
| `vita-app/README.md:33` | paraguas «con los 3 módulos duales» | 8 |
| `docs/15-rust-nativo-y-optimizacion-vita.md:13-15` | cross-compilar el paraguas de 8 «[?]» | G2/G3 lo cross-compilaron (PIC) — al menos la variante PIC está verificada [D] |
| `docs/03-estrategia-dual-rust-cpp.md:36-52` | selección por `CMakeLists` de cada módulo con cargo-vita | selección en el CMake de la app con el paraguas y `cargo rustc` |
| `godot/ros2_vita/API_PARITY.md:29` | callback vía cola `msg-ring` | cola propia en `ros_runtime.cpp` |

### 4.5 Serie `docs/rust/` frente a las construcciones usadas

No hay índice/README en `docs/rust/` (6 archivos 00–05). Conteo de construcciones (código / menciones en la serie):

**Explicadas** (al menos en un capítulo): `#![no_std]`, `extern "C"` + `#[unsafe(no_mangle)]`, `unsafe extern "C" {}`,
`#[repr(C)]`, punteros crudos, `null_mut/is_null`, `UnsafeCell` + `unsafe impl Sync`, `panic_handler`,
`rust_eh_personality`, `Option`, `let … else`, `if let`, `match`, `#[derive(Clone, Copy)]`, `impl`, closures,
rangos/iteradores (`iter_mut().find`, `position`, `unwrap_or`), `wrapping_*`/`checked_*`, `#[cfg]` + features,
`CStr`, `Result` + `?`, slices y lifetimes, genéricos const, préstamos disjuntos, atómicos y `Ordering`,
`macro_rules!`, callbacks C, recursión, `pub use`, rlib vs staticlib, paraguas, `-Zbuild-std`, nightly, cargo-vita.

**No explicadas o casi** (faltan en la serie; están comentadas solo in situ o nada):
1. `safe fn` dentro de `unsafe extern "C"` (Rust 2024) — `viz-math/impl-rust/src/lib.rs:19-24`. 0 menciones.
2. Enlazar **libm** desde `no_std` (por qué `core` no tiene `sinf/sqrtf`, `-lm` en `tests/host_common_flags`). 0.
3. `#[repr(C, align(4096))]` y el truco del wrapper para alinear un array — `net-udp/impl-rust/src/lib.rs:145-153`. 0.
4. **edición 2024** (qué cambia: `unsafe(no_mangle)`, `unsafe extern`, `safe fn`). Se cita «2024» sin explicar «edition».
5. Dependencias de ruta (`path = …`) y `default-features = false` en `Cargo.toml` — explicado solo en comentarios de
   `microros-transport/impl-rust/Cargo.toml:1-10`; 0 en la serie.
6. **PIC** (`-C relocation-model=pic`), `-Zbuild-std=core` vs `std,panic_abort`, `RUSTFLAGS` exportado,
   `compiler_builtins` — 0 en la serie (es la tarea T8.4 pendiente, `docs/19:204`). Está en `docs/18` §3–4.5.
7. `core::ptr::copy_nonoverlapping` / `copy_from_slice`, `slice::from_raw_parts(_mut)` — solo 1 mención de pasada.
8. Conversiones `i32::from(...)` / trait `From` (`msg-schema/impl-rust/src/lib.rs:358`) y casts `as`: `as usize` sí, `From` no.
9. `mod` interno con `pub` y `#[cfg]` aplicado a un módulo entero (`net-udp` rama Vita) — `mod` se explica en 01 sin el caso cfg.
10. `cargo rustc` vs `cargo build`, `Cargo.lock` versionado — **[H]** mencionado en 00 sin el porqué del lock.

Regla del CLAUDE.md («toda construcción Rust nueva explicada en comentarios y/o la serie»): se cumple en comentarios
para casi todo; en la serie faltan los puntos 1–6.

## 5. Recomendaciones (para planificar con el usuario; no aplicadas)

1. Arreglar `run-parity-tests.sh` en el PC (toolchain por defecto o `RUSTUP_TOOLCHAIN` en `env-devpc`).
2. Añadir `vizm_quat_identity` al `parity_test.c` de viz-math (buen **reto** pequeño para el usuario).
3. Capítulo `docs/rust/06-pic-build-std-y-edicion-2024.md` (T8.4) cubriendo los huecos 1–6; actualizar 01:143-148,
   02:113-116, 00 y `vita-app/README.md:33`; crear un índice en `docs/rust/`.
4. Prueba en hardware de la plantilla Godot 4 Rust (G6 con `out-rust`) y medir.
5. Decidir sobre los `CMakeLists.txt` por módulo (borrar o documentar como build suelto) y corregir `docs/03`.
6. Corregir `API_PARITY.md:29` o usar `msg-ring` de verdad en `ros_runtime.cpp`.
7. Nota web: `docs/informes/` es carpeta nueva; según la regla «toda doc en la web», necesita colección en
   `web/src/content.config.ts` (y quizá `COPY` en `web/Dockerfile`) — decisión del coordinador.
