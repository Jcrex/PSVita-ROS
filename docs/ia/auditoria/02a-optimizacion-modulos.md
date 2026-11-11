# Auditoría 02a — Optimización de los módulos de bajo nivel (memoria y CPU)

**Fecha:** 2026-11-01 · **Equipo:** Optimización A · **Ámbito:** `modules/{mem-pool,net-udp,microros-transport,
msg-ring,viz-math,msg-cdr,tf-tree,msg-schema}` + cómo se compilan para la Vita (`tools/build-c-pic.sh`,
`tools/build-rust-pic.sh`, `vita-app/CMakeLists.txt`, `vita-app/rust-modules/Cargo.toml`, `godot/ros2_vita/SCsub`).
**Modo:** solo lectura. Versión corta para el usuario: `docs/informes/02a-optimizacion-modulos.md`.

Marcas: **[M]** medido en esta auditoría (host o desensamblado del objeto real de la Vita) · **[V]** leído en la
fuente citada · **[H]** hipótesis no medida (con método para medirla).

---

## 0. Resumen ejecutivo

1. **Lo que de verdad corre hoy en la Vita es poco** [V]: en Godot 4 (camino principal) solo `msg-schema`
   (cada mensaje), `net-udp` + `microros-transport` (cada datagrama). `msg-ring` se compila dentro de
   `libgodot.so` pero **nadie lo llama** (`godot/ros2_vita/SCsub` lo añade; ningún `msg_ring_*` en
   `godot/ros2_vita/*.cpp`). `viz-math`, `msg-cdr`, `tf-tree` y `mem-pool` **no se ejecutan en ningún
   binario de la Vita** (vita-app enlaza `mem_pool.c` pero no lo llama; usa su propia cámara en
   `vita-app/src/viz/camera.c`). Priorizar en consecuencia.
2. **Los módulos no son hoy el cuello de botella de CPU** [M/H]: decodificar un `nav_msgs/Odometry` (720 B)
   cuesta ~0,2–0,33 µs en el host x86; aun con un factor ×20–×40 para el Cortex-A9 a 333–444 MHz [H] son
   ~5–13 µs por mensaje, frente a 33 ms de frame. El coste real está por encima (visitor de Godot con
   `Variant`/`Dictionary`, fuera de este ámbito) y por debajo (syscalls de red, MTU 512).
3. **Las mejores palancas son de compilación**, no de algoritmo:
   - `vita-app` se compila **sin optimizar (-O0)**: `CMAKE_BUILD_TYPE` vacío en `vita-app/build-c/CMakeCache.txt`
     y `build-rust/CMakeCache.txt` [M], y el toolchain de VitaSDK deja `CMAKE_C_FLAGS=""`
     (`toolchains/vitasdk/share/vita.toolchain.cmake:90`) [V].
   - En Godot, los `.c` de los módulos heredan **`-Os`** (`toolchains/godot4-vita/engine/platform/vita/detect.py:149-152`);
     en host `msg_schema_decode` es **1,45× más rápido con -O2** que con -Os [M].
   - El perfil Rust del paraguas solo fija `panic = "abort"` (`vita-app/rust-modules/Cargo.toml:33-34`):
     sin `lto`, `codegen-units` = 16 por defecto.
4. **Memoria:** 1 MiB de BSS muerto en `libgodot.so` (pool estático de `net_udp.c:40` que nunca se usa porque
   `xrce_transport.cpp:97-115` inicializa la red antes con su propio `memalign` de 1 MiB) [M: `size` del
   `.o` de la Vita da bss = 1 052 672].
5. **Bugs:** (B1) lectura fuera de límites en `msg_schema_init` con un blob malicioso/corrupto — **confirmada
   con ASan** en C y cuelgue en Rust [M]; (B2) el `panic_handler` es `loop {}`: un pánico deja un hilo girando
   al 100 % sin log; (B3) desbordamiento con signo en `timeout_ms * 1000` (UB en C).
6. **NEON no se usa** [M]: el desensamblado de `viz_math_rust` para la Vita tiene 406 operaciones VFP escalares
   y **0** operaciones NEON en registros q/d. La auto-vectorización de `f32` que prometen `docs/14 §2` y
   `docs/15 §3` no ocurre (ni en GCC ni en LLVM) sin `-ffast-math`, porque NEON no es IEEE (pone a cero los
   denormales). Hay que corregir esa afirmación en los docs.

Paridad de partida: `tools/run-parity-tests.sh` → **8/8 módulos verdes en C y Rust** [M] (con
`RUSTUP_HOME/CARGO_HOME` de `tools/env-devpc.sh` y `RUSTUP_TOOLCHAIN=nightly`; sin ellas rustup falla con
"could not choose a version of cargo").

---

## 1. Qué se ejecuta en la Vita y con qué flags

| Módulo | vita-app (Fase 1, C) | Godot 4 `ros2_vita` (camino actual) | Frecuencia en la Vita |
|---|---|---|---|
| net-udp | sí (`main.c:161`, `netlog.c:21,41`) | sí (vía microros-transport) | 1 syscall por datagrama + 1 `EAGAIN` por frame |
| microros-transport | sí (`uxr_glue.c:21-41`) | sí (`xrce_transport.cpp:66-81`) | cada `read/write` de XRCE |
| msg-schema | no | sí (`ros_msg.cpp:18,518`; encode en `serialize`) | cada mensaje publicado/recibido |
| msg-ring | no | compilado, **no llamado** | 0 |
| mem-pool | enlazado (`CMakeLists.txt:89`), **no llamado** | no | 0 |
| viz-math / msg-cdr / tf-tree | no (solo en el staticlib Rust, sin llamadas) | no | 0 |

| Binario | Flags C efectivos | Rust |
|---|---|---|
| vita-app (`cmake -B build-c`) | **-O0** (build type vacío) + defaults del gcc de VitaSDK: `-march=armv7-a -mtune=cortex-a9 -mfpu=neon -mfloat-abi=hard -mthumb` (comprobado con `gcc -v` / `-Q --help=target`) [M] | `cargo +nightly rustc --release -Zbuild-std=std,panic_abort` → opt-level 3, sin LTO, 16 CGU |
| libgodot.so (template_release) | `-Os -mcpu=cortex-a9 -mfpu=neon -mfloat-abi=hard -ftree-vectorize -fno-optimize-sibling-calls -fPIC` (`detect.py:149-173`) | `tools/build-rust-pic.sh`: `-C relocation-model=pic -Zbuild-std=core`, mismo perfil |
| `tools/build-c-pic.sh` (solo G2) | idéntico a Godot (`build-c-pic.sh:22-23`) | — |
| host (paridad) | `gcc -std=c11 -g` **sin -O** (`run-parity-tests.sh`) | `--release` |

Consecuencias:
- `-ftree-vectorize` no vectoriza `float` con NEON sin `-funsafe-math-optimizations` (GCC: NEON no cumple IEEE
  con denormales) [V doc. GCC `-mfpu`; M en Rust]. Sirve para enteros (p. ej. copias), no para `viz-math`.
- `-fno-optimize-sibling-calls` desactiva las llamadas de cola: en código con `TRY(...)` encadenado cuesta un
  `push/pop` extra por nivel. Lo exige el port (probablemente por el loader o por trazas) [H]; no tocar sin
  preguntar al port.
- Comparar rendimiento C vs Rust en host con los flags de paridad es engañoso: el C va sin optimizar.

### 1.1 Lo que dice el código máquina real de la Vita [M]

Objetos generados por SCons que ya están (ignorados por git) en `modules/*/impl-c/*.vita.template_release.arm32.o`
y staticlib `toolchains/pic/rust-target/.../libvita_modules_rust.a`:

| Objeto | .text | .bss | Imports relevantes |
|---|---|---|---|
| msg_schema (C, -Os) | 2 492 B | 0 | `__aeabi_uidiv` (encode, `msg_schema.c:445`), `memcmp`, `memcpy`, `memset`, `strcmp` |
| msg_ring (C, -Os) | 354 B | 0 | `__aeabi_uidiv` (solo en `required_size`), `memcpy` |
| net_udp (C, -Os) | 604 B | **1 052 672 B** | sceNet* |
| mem_pool (C, opt) | 372 B | 0 | `__aeabi_uidiv`, **`__aeabi_uidivmod`** (el `%` de `free`) |
| msg_schema_rust | 6 297 B | 0 | `panic_bounds_check`, `slice_index_fail`, `panic_const_div_by_zero`, `memchr_aligned`, `memcmp`, `strlen` |
| msg_cdr_rust | 5 684 B | 0 | `panic_bounds_check`, `slice_index_fail`, `__aeabi_memclr8` |
| tf_tree_rust | 3 140 B | 0 | `panic_bounds_check`, `memcmp`, `strlen` |
| viz_math_rust | 3 704 B | 0 | `sinf`, `cosf`, `tanf` (sqrt se emite como `vsqrt.f32`: bien) |
| net_udp_rust | 1 164 B | **1 048 576 B** | sceNet* |
| mem_pool_rust | 449 B | 0 | `__aeabi_uidivmod`, `panic_const_rem_by_zero` |

- El Cortex-A9 **no tiene división entera por hardware** (UDIV/SDIV son opcionales en ARMv7-A y el A9 no los
  trae) [A]: cada `/` o `%` con divisor variable es una llamada a `__aeabi_uidiv[mod]` (decenas de ciclos) [H: medir].
- En `msg_schema.c` con -Os, `ld32` se compila a un único `ldr` no alineado (bien: ARMv7 admite LDR no
  alineado), **pero no se inlinea**: 20 llamadas `bl ld32`, 4 a `msg_prim_size`, y `msg_schema_field` /
  `msg_schema_field_count` se llaman fuera de línea por cada campo [M].
- Cada import `panic_*` de Rust arrastra `core::fmt` (formateadores, tablas Unicode) al binario final [M: el
  `.a` importa `Formatter::pad`, `unicode::printable`...]. Es tamaño, no velocidad, mientras no haya pánico.

---

## 2. Bugs y riesgos

| ID | Dónde | Qué pasa | Gravedad | Arreglo (ambas impl.) |
|---|---|---|---|---|
| **B1** | `msg-schema/impl-c/msg_schema.c:58-73`; `impl-rust/src/lib.rs:135-144` | `msg_schema_init` comprueba `soff >= foff >= toff >= 32` y que las tablas encajen entre sí, pero **no que `soff <= total`**. Con `toff=32, tcount=1, foff=soff=44, total=len=32`, `strings_len = total - soff` da la vuelta (0xFFFFFFF4) y el bucle de tipos lee fuera del blob. **C: `heap-buffer-overflow` (ASan) [M]. Rust: `panic_bounds_check` → `panic_handler` `loop {}` → el proceso se cuelga [M: `timeout 5` → 124].** | Media: el blob viene del `.pck` (confiable), pero `RosMsg::load_schema_bytes` acepta cualquier `Vector<uint8_t>` y el header promete "Valida el blob" | Añadir `soff > total → BAD_SCHEMA` (con eso `toff,foff ≤ soff ≤ len` quedan garantizados). Añadir el caso al `parity_test.c` (reproductor: §8) |
| **B2** | `vita-app/rust-modules/src/lib.rs:23-25` (y los `standalone` de cada crate) | `panic_handler` = `loop {}`: un pánico (índice fuera de rango, B1...) deja el hilo **girando al 100 % de un núcleo, sin log**, y la app congelada | Media (diagnóstico imposible en hardware) | Llamar a un gancho C (`extern "C" fn vita_rust_panic(file, line)`) que haga log y `abort()`/`sceKernelExitProcess`; o compilar `core` con `panic_immediate_abort` (en nightlies recientes `-Cpanic=immediate-abort`, verificar con el nightly instalado [H]) → el pánico es una instrucción `udf` (trap), sin `fmt` |
| **B3** | `net-udp/impl-c/net_udp.c:260`; `impl-rust/src/lib.rs:465` | `int usec = timeout_ms * 1000` desborda para `timeout_ms > 2 147 483` (~35,8 min): **UB en C**; en Rust release da la vuelta y en debug entra en pánico → divergencia de paridad | Baja (uxr no pasa esos valores) | Saturar: `timeout_ms > INT32_MAX/1000 ? INT32_MAX : timeout_ms*1000` en ambas; caso nuevo en la paridad |
| **B4** | `mem-pool/impl-c/mem_pool.c:106` | `blk < pool->blocks_start` compara punteros a objetos potencialmente distintos: UB formal en C11 §6.5.8 (funciona en la práctica) | Muy baja | Comparar como `uintptr_t` |
| **B5** | `net-udp/impl-rust/src/lib.rs:182`, `microros-transport/impl-rust/src/lib.rs` (`unsafe impl Sync`), y las `static` de C | Estado global sin sincronizar. Hoy todo va en un hilo, pero `docs/14 §4` recomienda mover la red a un hilo propio: si netlog (vita-app) o Godot llamasen a `net_udp_*` desde otro hilo habría carrera de datos (UB en Rust) | Riesgo futuro | Documentar en el header "no reentrante, un solo hilo"; si se crea el hilo de red, toda llamada a net-udp debe salir de él |
| **B6** | `vita-app/build-*/CMakeCache.txt` | vita-app sin optimizar (ver §1). No es un fallo funcional, pero todas las medidas de rendimiento de Fase 1 se hicieron con -O0 | Media (rendimiento) | `-DCMAKE_BUILD_TYPE=Release` en el comando y en `vita-build-package`, o `set(CMAKE_BUILD_TYPE Release CACHE ...)` por defecto en `vita-app/CMakeLists.txt` |

No encontrados: desbordes de escritura, carreras en `msg-ring` (los órdenes acquire/release son correctos:
productor `relaxed` sobre su propio `tail`, `acquire` sobre `head`, `release` al publicar), ni UB en `msg-cdr`
(cada lectura pasa por `need()`).

---

## 3. Análisis por función

Columnas: **Mem** = asignaciones/copias/pila; **CPU** = trabajo por llamada en la Vita; **Prop.** = propuesta (ID de §4).

### 3.1 net-udp (caliente: cada datagrama)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `net_udp_init` (`net_udp.c:97-126`) | BSS 1 MiB (`g_net_pool`, `:40`) + tabla 4×8 B | 1 vez | En Godot el pool **nunca se usa** (EBUSY): 1 MiB de RAM perdida. En Rust idem (`NET_POOL`, `lib.rs:152`) | O4 |
| `net_udp_open` | `sockaddr` 16 B en pila | 1 vez | Parser IPv4 propio, correcto | — |
| `net_udp_send` (`:226-243`) | 0 copias | 1 syscall `sceNetSend` | Mínimo posible | — |
| `net_udp_recv` (`:245-275`) | 0 copias | `timeout>0`: **2 syscalls** (`sceNetSetsockopt` + `sceNetRecv`); `timeout==0`: 1 (`DONTWAIT`) | Godot llama con 0 cada frame (`xrce_transport.cpp:337`) → ya óptimo; pero `_flush` (`:248`, 10 ms) y las esperas de creación de entidades usan >0. vita-app usa 50 ms (`main.c:399`) → 2 syscalls por intento | O5 |

`uxr_run_session_time(0)` drena todos los datagramas pendientes hasta `EAGAIN` [V: semántica de micro-XRCE-DDS;
H sobre la versión exacta], así que en reposo hay **1 syscall fallida por frame** (aceptable). Con
`UXR_CONFIG_CUSTOM_TRANSPORT_MTU = 512` (`vita-app/third_party/xrce-vita-pic/include/uxr/client/config.h:60`), un
mensaje de 16 KB (`MAX_RX`, `xrce_transport.cpp:137`) son ≥32 datagramas → ≥32 `sceNetRecv` + 32 ACK. Subir la MTU
a ~1 400 B dividiría por ~3 los syscalls de mensajes grandes (O6, fuera del módulo pero lo ejecuta este módulo).

### 3.2 microros-transport

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `open/close/is_open` | 4 B estado | 1 vez | — | — |
| `write`/`read` (`microros_transport.c:40-74`) | 0 | 1 llamada a net-udp + ramas | En Rust la llamada `microros_transport_read → net_udp_recv` cruza crates sin LTO → no se inlinea (irrelevante frente al syscall) | O3 |

### 3.3 msg-schema (caliente: cada mensaje en Godot)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `msg_schema_init` (`:47-101`) | 0 (vista sobre el blob) | 1 vez, O(tipos+campos+strings) | **B1**. `str_ok` recorre hasta el NUL por cada nombre: O(n·len) al cargar, despreciable | B1 |
| `msg_schema_find_type` (`:125-139`) | 0 | O(tipos) `strcmp` | Se llama al crear `RosMsg` (`ros_msg.cpp:157`); si GDScript crea mensajes por frame, es un `strcmp` lineal por tipo [H: contar llamadas] | O9 |
| `msg_schema_field` (`:153-174`) | 16 B en pila | ~6 `ld32` + 3 comprobaciones | **Se llama por cada campo de cada struct de cada mensaje**, re-decodificando la fila del blob. Con -Os va fuera de línea [M] | O2, O8 |
| `dec_struct`/`dec_field` (`:226-319`) | recursión ≤16 niveles (~64–100 B/nivel [H]) → ≤ ~2 KB de pila | 1 llamada indirecta al visitor por primitiva | `ld_raw` byte a byte (bucle de hasta 8); `msg_prim_size` fuera de línea; `count > SIZE_MAX / sz` → división (el compilador puede convertirla, `sz` ∈ {1,2,4,8}) | O2, O8 |
| `enc_*` (`:335-512`) | escribe en buffer del llamador | `e_pad` hace `memset` por alineación; **`(e->cap - e->pos) / sz` → `__aeabi_uidiv` real por cada array primitivo** (`:445`) [M] | Sustituir por desplazamiento (`sz` es potencia de 2) | O7 |
| Rust `field_of`/`ld32` (`lib.rs:97,261`) | — | `ld32` indexa `b[o]..b[o+3]`: 4 comprobaciones de límites por lectura; `field_count_of` llama a la función `extern "C"` pública | Misma velocidad que C -Os en host (311 vs 330 ns) incluso **con LTO fat + 1 CGU (313 ns)** [M]: el coste es estructural, no de flags | O8 |

Medida host [M] (`nav_msgs/Odometry`, 720 B, 15 eventos prim, visitor vacío, 200 000 iteraciones):

| Build | ns/decode |
|---|---|
| C `-Os -fno-optimize-sibling-calls` (como Godot) | 330 |
| C `-O2` | 221–230 |
| C `-O3` | 209–212 |
| Rust release (perfil actual) | 311 |
| Rust release + `lto=fat`, `codegen-units=1` | 313–318 |

### 3.4 msg-ring (no usado todavía)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `required_size/create` | cabecera 64 B; `slot_count × roundup8(4+slot_size)` | 1 vez | Un mensaje = una ranura de tamaño máximo: para mensajes de tamaño muy variable desperdicia memoria (aceptado por diseño) | — |
| `push` (`msg_ring.c:76-101`) | **1 `memcpy`** dentro | 2 cargas atómicas + 1 store-release (`dmb`) | `head` y `tail` (offsets 12 y 16, `:21-22`) **comparten línea de caché de 32 B** con `dropped`: con productor y consumidor en núcleos distintos, cada push/pop invalida la línea del otro (false sharing) [H: medir] | O10 |
| `pop` (`:103-125`) | **1 `memcpy`** fuera | idem | Dos copias por mensaje (entrada + salida) | O11 |
| `count/dropped` | — | 2 acquire | `count` usa acquire en ambos: correcto, algo caro si se sondea en bucle | — |

### 3.5 mem-pool (no usado)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `create` (`mem_pool.c:57-85`) | cabecera 64 B; bloques alineados a 8 | O(n) encadenado, 1 vez | Alineación 8: bien para `double`; para NEON/GXM haría falta 16 (`docs/14 §3.4`) | O12 |
| `alloc` | 0 | O(1) | Óptimo | — |
| `free` (`:98-124`) | 0 | **O(n)**: recorre toda la free-list para detectar doble free (toca una línea de caché por bloque libre) + `%` → `__aeabi_uidivmod` [M] | Con pools grandes es el peor caso del módulo | O12 |
| sin cerrojo | — | — | Si micro-ROS lo usara desde dos hilos: carrera | B5 |

### 3.6 msg-cdr (no usado)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `decode_tf_message` (`msg_cdr.c:184-199`) | struct de salida **6 160 B**; `memset` completo; `scratch` 192 B en pila | O(n) lecturas con `align+need` por cada `double` | El `memset` de 6 KB por mensaje ensucia ~19 % de la L1D de 32 KB [H] | O13 |
| `decode_joint_state` | 2 912 B, `memset` | idem | `double` en la salida: VFPv3 maneja f64 nativamente (más lento que f32 en mul [A]); duplica memoria frente a f32 | — |
| `decode_marker` | 2 840 B, `memset` | 3 `align+need` por punto | Se puede validar `need(n*24)` una vez por secuencia | O13 |
| `decode_occupancy_grid` | **0 copias** (`data` apunta al payload) | O(1) | Bien diseñado | — |
| `rd_f64` (`:74-86`) | — | bucle de 8 bytes | GCC/LLVM suelen fundirlo en 2 `ldr` [H: mirar asm] | — |

Ojo de pila: si alguien declara un `msg_cdr_tf_message` local en un hilo de 64 KB (el tamaño típico, `docs/14 §4`), es
casi el 10 % de la pila. Recomendar `static` o buffer del llamador.

### 3.7 tf-tree (no usado)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `find` (`tf_tree.c:46-54`) | árbol 3 080 B (32×96 B) | hasta 32 `strcmp` | En Rust `arr_bytes` (`lib.rs:72`) busca el NUL de cada nombre antes de comparar (64 B extra por frame) | O14 |
| `update` (`:95-140`) | — | 2 `norm` (strlen) + 2 `find` + `strcmp` + normalización de cuaternión (sqrt+div) | Un TFMessage de 32 transforms → hasta 2 048 `strcmp` | O14 |
| `to_root` (`:164-181`) | `mat4` 64 B en pila por nivel | **por cada salto: `quat_to_mat4` (que vuelve a normalizar el cuaternión ya normalizado: sqrt+div) + `mat4_mul` (64 mul + 64 add)** | Se recalcula entero en cada `lookup` | O15 |
| `lookup` (`:183-213`) | 3×64 B | 2× `to_root` + inversa + mul | Sin caché: dibujar N objetos = N recomposiciones | O15 |

### 3.8 viz-math (no usado)

| Función | Mem | CPU | Observaciones | Prop. |
|---|---|---|---|---|
| `mat4_mul` (`viz_math.c:140-153`; `lib.rs:242`) | temporal 64 B | 64 `vmul` + 64 `vadd` escalares VFP [M] | Empieza con `s = 0.0f`: el compilador no puede quitar el `0 + x` (cambiaría `-0.0`) → 16 sumas extra [M: `vldr s2, =0.0` en el asm]. Sin NEON | O16 |
| `quat_to_mat4` (`:108-130`) | — | sqrt + div + ~20 mul | Normaliza siempre (útil si la entrada no es unitaria; redundante desde tf-tree) | O15 |
| `quat_from_axis_angle` (`:64-74`) | — | `sinf` + `cosf` de newlib (software) | `sincosf` ahorraría la reducción de argumento doble [H] | — |
| resto (vec3, quat_mul, look_at...) | — | decenas de flops | Correctos; el `1.0/n` + 3 mul es la forma barata | — |

---

## 4. Optimizaciones priorizadas

Impacto: **A** alto · **M** medio · **B** bajo, siempre relativo a lo que hoy corre. "Paridad": si exige cambiar
las dos implementaciones o el header.

| # | Optimización | Impacto | Riesgo | Paridad | Cómo medir |
|---|---|---|---|---|---|
| **O1** | Compilar vita-app en Release (`-DCMAKE_BUILD_TYPE=Release` → `-O3`, o `MinSizeRel`) | **A** (todo el C de la app, módulos incluidos, pasa de -O0) | Bajo | No | FPS y `sceKernelGetProcessTimeWide` alrededor de `uxr_run_session_time` en netlog, antes/después |
| **O2** | En `godot/ros2_vita/SCsub`, `env_ros.Append(CCFLAGS=["-O2"])` solo para los `.c` de los módulos (el último `-O` gana en GCC) | M (−30 % en decode en host [M]) | Bajo (+~1–2 KB de .text [H]) | No | `sceKernelGetProcessTimeWide` alrededor de `msg_schema_decode` en `RosMsg::deserialize`; tamaño de `libgodot.so` |
| **O3** | Perfil Rust del paraguas: `opt-level = 3`, `codegen-units = 1`, `lto = "fat"` (solo cuenta el perfil del crate raíz; los `[profile]` de los crates dependientes **se ignoran**) | B en velocidad [M: msg-schema no mejora], M en tamaño (menos `core::fmt`) [H] | Bajo | No | `arm-vita-eabi-size` del staticlib y de `libgodot.so`; `verify_runtime.py` |
| **O4** | Quitar el pool estático de 1 MiB de net-udp: API `net_udp_init_with_pool(void*, size_t)` o macro `NET_UDP_POOL_SIZE` (0 = el llamador ya inició la red) | **A en memoria** (−1 MiB de BSS en `libgodot.so`, −1 MiB en vita-app si se comparte) | Bajo | Sí (header + ambas) | `size` del `.o`; `sceKernelGetFreeMemorySize` al arrancar (E-H4) |
| **O5** | Cachear el último `RCVTIMEO` por socket (campo nuevo en `net_udp_socket`, interno) y no repetir `sceNetSetsockopt` si no cambia | B en Godot (usa 0), M en vita-app y en `_flush`/esperas | Bajo | Sí (ambas; header intacto) | Contador de `sceNetSetsockopt` por segundo en netlog |
| **O6** | Subir `UXR_CONFIG_CUSTOM_TRANSPORT_MTU` de 512 a ~1 400 (cabe en un datagrama Ethernet sin fragmentar IP) y ajustar `RELIABLE_SLOT` | M–A para `/odom`, mapas, markers: ÷3 syscalls y ACK | Medio (recompilar XRCE; el agente lo acepta) | No (es XRCE) | `g_diag.read_packets` por segundo y latencia de `/odom` |
| **O7** | Divisiones por potencia de 2 como desplazamiento: `msg_schema.c:445`, `:269` y `mem_pool.c:109` (guardar `log2(eff)` si `eff` es potencia de 2, o usar `uint32_t` con recíproco) | B | Bajo | Sí (ambas) | Desaparece `__aeabi_uidiv[mod]` en `nm -u` |
| **O8** | msg-schema: "compilar" la tabla de campos al cargar (array de `msg_field_info` desempaquetado en un buffer del llamador, `msg_schema_compile(s, buf, cap)`), `static inline` en `ld32/msg_prim_size`; en Rust `u32::from_le_bytes(b[o..o+4].try_into())` (una sola comprobación de límites) | M (elimina ~6 cargas y 3 ramas por campo) | Medio (API nueva) | Sí (header + ambas) | Bench de §3.3 en host y en la Vita |
| **O9** | Cachear `type_idx` en `RosMsg` (ya lo hace para `ros_msg.cpp:157`; verificar que no se busca por frame) | B | Bajo | No | Contar llamadas a `find_type` |
| **O10** | msg-ring: separar `head` y `tail` en líneas de 32 B distintas **dentro de los 64 B de cabecera** (offsets 0 y 32; `required_size` no cambia) y cachear en el productor la última `head` vista (solo releer si parece llena) | M cuando exista hilo de red | Bajo | Sí (layout interno, ambas) | Bench host con 2 hilos (`perf stat -e cache-misses`); en la Vita, `runClocks` de `SceKernelThreadInfo` |
| **O11** | msg-ring sin copia: `msg_ring_reserve/commit` (productor escribe en la ranura) y `msg_ring_peek/release` (consumidor lee en sitio) | M (−1 `memcpy` por mensaje) | Medio | Sí (header + ambas) | Bench host |
| **O12** | mem-pool: doble-free O(1) con canario en los bytes 4–7 del bloque libre (en la Vita el puntero ocupa 4 de los 8 bytes mínimos), con recorrido O(n) solo si el canario coincide; opción de alineación 16 | B (no se usa) | Bajo | Sí (ambas) | Bench host de 10⁶ alloc/free |
| **O13** | msg-cdr: no hacer `memset` del struct entero, solo de contadores y de los elementos escritos; comprobar `need(n*24)` una vez por secuencia | B (no se usa) | Medio (cambia el contrato "pone `out` a cero") | Sí (header + ambas) | Bench host |
| **O14** | tf-tree: guardar un hash FNV-1a de 32 bits por frame (cabe en `pad`+... o array aparte) y comparar el hash antes que el nombre | B (no se usa) | Bajo | Sí (`required_size` cambia en ambas) | Bench host con 32 frames |
| **O15** | tf-tree: componer `(q, t)` en vez de `mat4` (q·q = 16 mul; rotar t ≈ 15 mul) y caché del transform al raíz con contador de generación; no re-normalizar cuaterniones ya normalizados | B (no se usa) | Medio | Sí (tolerancia 1e-5 de las pruebas lo admite: `tf-tree/tests/parity_test.c:25`) | Bench host |
| **O16** | viz-math NEON explícito (`arm_neon.h` `vmlaq_f32` en C; en Rust `core::arch::arm`, inestable → `#![feature(stdarch_arm_neon_intrinsics)]` en nightly) para `mat4_mul` y `transform_point`; empezar la suma con el primer producto | B (no se usa) | Medio (NEON pone a cero denormales; la tolerancia 1e-5 lo absorbe) | Sí (ambas) | Contar `vmla.f32 q` en el asm; bench en la Vita |
| **O17** | Corregir `docs/14 §2` y `docs/15 §3`: NEON **no** se auto-vectoriza para `f32` sin `-ffast-math`/`unsafe-fp-math` | — | — | — | — |

Orden recomendado: B1 (bug) → O1 → O4 → O2 → B2 → O6 → O5 → O3; el resto cuando el código correspondiente
empiece a ejecutarse en la Vita (hilo de red → O10/O11; mini-rviz → O14–O16).

---

## 5. Cómo medir en la Vita (receta)

1. **Tiempo:** `SceUInt64 t0 = sceKernelGetProcessTimeWide();` antes y después de la función, acumular y mandar
   media/máx por netlog cada segundo (no `printf` en el bucle).
2. **Memoria:** `sceKernelGetFreeMemorySize(&info)` (`size_user`, `size_cdram`, `size_phycont`) al arrancar y tras
   `start()` del transporte (E-H4 de `docs/14 §9`).
3. **Hilos/núcleos:** `sceKernelGetThreadInfo` → `runClocks`, `currentCpuId`, `changeCpuCount` (útil para O10).
4. **Syscalls de red:** contadores en `xrce_transport.cpp` (ya hay `g_diag.read_packets`); añadir los de
   `setsockopt` para O5.
5. **Host:** `perf stat`/`perf record` con el C a **-O2** (no con los flags de paridad, que van sin -O), y el bench
   de §8.
6. **Código máquina:** `arm-vita-eabi-objdump -d` de los `.o` de SCons (`modules/*/impl-c/*.vita.template_release.arm32.o`)
   y `arm-vita-eabi-nm -u` para ver divisiones (`__aeabi_uidiv`) y pánicos.

---

## 6. Construcciones Rust que aparecen en este informe (para el usuario principiante)

- **`[profile.release]` en Cargo.toml:** opciones de compilación del modo `--release`. Cargo solo hace caso al
  perfil del crate que se compila como raíz (aquí `vita-app/rust-modules`); los `[profile]` de `mem-pool`,
  `net-udp`... se ignoran cuando entran como dependencias.
- **`lto = "fat"`:** *link-time optimization*: junta todos los crates (y `core`) en una sola unidad antes de
  optimizar; permite inlinear entre crates y borrar código no usado.
- **`codegen-units = 1`:** el compilador no parte el crate en trozos paralelos; compila más lento y optimiza mejor.
- **`#[panic_handler]` / `-> !`:** función a la que salta Rust en un pánico; `!` significa "no vuelve nunca".
  `loop {}` cumple el tipo, pero gira para siempre.
- **`panic_bounds_check`:** la comprobación que Rust mete al indexar `b[i]`; si `i >= len` entra en pánico en vez
  de leer memoria ajena (por eso B1 es un cuelgue y no una lectura fuera de límites en Rust).
- **`u32::from_le_bytes(arr)` y `slice.try_into()`:** convierten 4 bytes a `u32` little-endian; `try_into()` pasa
  de `&[u8]` a `[u8; 4]` con **una** comprobación de longitud.
- **`AtomicU32` + `Ordering::{Relaxed, Acquire, Release}`:** enteros compartidos entre hilos; `Release` al publicar
  y `Acquire` al leer garantizan que los datos de la ranura se ven antes que el índice (en ARM genera `dmb`).
- **`unsafe impl Sync`:** promesa manual de que un tipo se puede compartir entre hilos; el compilador no lo
  comprueba (B5).
- **`#![feature(...)]`:** activa una función inestable; solo en nightly (el proyecto ya usa nightly).
- **`core::arch::arm`:** intrínsecas NEON (`vmlaq_f32`...) para ARM de 32 bits; inestables.

---

## 7. Qué no se pudo verificar

- Tiempos reales en la Vita (nada se ejecutó en hardware): todo factor host→Vita es **[H]**.
- Si `-fno-optimize-sibling-calls` es obligatorio para el loader de godot4-vita.
- El nombre exacto de la opción `panic_immediate_abort` en el nightly instalado (`toolchains/rustup`).
- El tamaño mínimo real del pool de `sceNetInit` para XRCE con MTU 512 (¿bastaría con 256 KB?) [H: probar
  y vigilar errores `SCE_NET_ERROR_ENOMEM`].

---

## 8. Reproductores (en el scratchpad de la sesión, no en el repo)

**B1** (`schema_oob.c`): blob de 32 B con `"RSCH"`, `version=1`, `type_count=1`, `field_count=0`, `types_off=32`,
`fields_off=44`, `strings_off=44`, `total_len=32`; `msg_schema_init(&s, b, 32)`.
`gcc -fsanitize=address ... impl-c/msg_schema.c` → `heap-buffer-overflow READ of size 1`; enlazado contra el
staticlib Rust → no termina (`timeout 5` = 124).

**Bench msg-schema** (`bench_schema.c`): carga `tests/fixtures/schema.rsch`, decodifica `odometry.bin` como
`nav_msgs/msg/Odometry` 200 000 veces con un visitor que solo cuenta primitivas; compilar el `.c` del módulo con
`-Os -fno-optimize-sibling-calls`, `-O2`, `-O3`, y enlazar el `.a` Rust (normal y con
`CARGO_PROFILE_RELEASE_LTO=fat CARGO_PROFILE_RELEASE_CODEGEN_UNITS=1`, `--target-dir` en el scratchpad).
Conviene convertirlo en `tools/bench-msg-schema.sh` si el usuario lo aprueba.
