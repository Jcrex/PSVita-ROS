# 14 — Hardware de la PS Vita: memoria, hilos, CPU/GPU y cómo optimizar

**Fecha:** 2026-10-27 · **Estado:** estudio basado en headers de VitaSDK,
fuentes de newlib/vitaGL y búsquedas web. Lo que no se pudo confirmar queda
como **[?]** y tiene un experimento asignado (§9, `tools/hwprobe/`).
Marcas: **[V]** leído en un archivo fuente citado · **[A]** conocimiento
general de la arquitectura ARM Cortex-A9 (no específico de la Vita) ·
**[I]** inferencia propia · **[?]** sin confirmar.

Objetivo: tener claro el hardware para (a) escribir Rust nativo propio
(`docs/15`), (b) saber qué optimizar en CPU/GPU limitadas y (c) construir
los componentes personalizados del proyecto sin suposiciones.

---

## 1. Resumen ejecutivo

1. CPU: **ARM Cortex-A9 cuatro núcleos**, ARMv7-A, con **NEON** y **VFPv3**
   **[V]**: la spec del target Rust fija `cpu = cortex-a9`,
   `features = +v7,+neon,+vfp3,+thumb2`, ABI hard-float, atómicos hasta
   64 bits **[V]**.
2. Reloj: el CPU arranca a **333 MHz** y puede subir a **444 MHz** (y 500
   con plugins); GPU hasta **222 MHz**, con bus y crossbar propios
   **[V buscador + header de power]**. Esto decide mucho del rendimiento.
3. RAM: **512 MB** principales + **128 MB de VRAM** ("CDRAM") **[V
   buscador]**; la memoria se pide por *memblocks* de tipos distintos
   (cacheada, no cacheada, CDRAM, físicamente contigua) **[V]**.
4. El **heap de newlib** es **un único memblock de 128 MB por defecto**,
   ajustable con el símbolo `_newlib_heap_size_user` **[V]**.
5. Hilos: el planificador ve **4 CPUs** (`cpuInfo[4]`); la afinidad se
   codifica en los bits 16–19 de la máscara **[V]**. Qué núcleos puede
   usar un homebrew sigue siendo **[?]** (hipótesis común: 3 de 4).
6. GPU: **PowerVR SGX543MP4+**, tile-based, programada por **GXM**; tiles
   de **32×32 px**; los shaders en runtime requieren `libshacccg.suprx`
   **[V]**.

---

## 2. CPU

| Dato | Valor | Fuente |
|---|---|---|
| Núcleo | ARM Cortex-A9 MPCore, 4 núcleos | spec Rust **[V]**; wikipedia vía buscador |
| ISA | ARMv7-A, Thumb-2, interworking | target Rust **[V]** |
| SIMD | **NEON** (128 bit) y VFPv3 | target Rust **[V]** |
| ABI | EABI hard-float (`EabiHf`) | **[V]** |
| Atómicos | hasta 64 bits (`max_atomic_width: 64`) | **[V]** |
| Reloj CPU | 333 MHz por defecto; 444 MHz con WiFi apagado (reportes de la comunidad); 500 con plugin | buscador **[V parcial]** |
| Pasos de PSVshell | CPU 41, 83, 111, 166, 222, 333, 444, 500 MHz; GPU 41, 55, 83, 111, 166, 222 MHz | buscador |
| API de reloj | `scePower{Get,Set}{Arm,Bus,Gpu,GpuXbar}ClockFrequency(MHz)`; sin rango documentado en el header | **[V]** |
| Caché L1 | 32 KB I + 32 KB D por núcleo, línea de 32 B | **[A]** (Cortex-A9 TRM) |
| L2 | controlador PL310 compartido; **tamaño en la Vita [?]** | **[A]** / **[?]** |
| Orden de memoria | débil (ARMv7): necesita barreras `dmb`; `acquire/release` de C11/Rust las generan | **[A]**; relevante para `msg-ring` |

**Implicaciones de diseño**
- A 333–444 MHz con un solo hilo de aplicación, **cada ciclo cuenta**:
  evitar `memcpy` extra, `printf` en el bucle caliente y cálculo en `double`
  (VFPv3 es nativo para `f32`/`f64`, pero NEON solo vectoriza `f32`/enteros **[A]**).
- Preferir `f32` en matemática 3D (`viz-math` lo hace) y datos contiguos
  (estructuras de arrays) para que la auto-vectorización use NEON **[I]**.
- El WiFi y el CPU compiten por consumo: la comunidad reporta que 444 MHz
  exige apagar WiFi **[V buscador, anecdótico]** → para ROS2 (necesita
  WiFi) **asumir 333 MHz** hasta medir (§9, E-H1).

---

## 3. Memoria

### 3.1 Tipos de bloque (`sceKernelAllocMemBlock`) **[V]**
Fuente: `psp2common/kernel/sysmem.h` de vita-headers.

| Macro | Valor | Para qué (interpretación [I]) |
|---|---|---|
| `USER_MAIN_RW` (= `USER_RW`) | `0x0C20D060` | RAM normal **cacheada** (heap de newlib) |
| `USER_MAIN_NC_RW` (= `USER_RW_UNCACHE`) | `0x0C208060` | RAM **no cacheada** (búferes que ve la GPU) |
| `USER_CDRAM_RW` | `0x09408060` | **VRAM/CDRAM** (128 MB) |
| `USER_CDRAM_L1WBWA_RW` | `0x09404060` | CDRAM con L1 write-back |
| `USER_MAIN_PHYCONT_RW` / `_NC_RW` | `0x0C80D060` / `0x0D808060` | RAM **físicamente contigua** (DMA/GPU) |
| `USER_MAIN_GAME_RW`, `_CDIALOG_`, `_TOOL_` | `0x0C50D060`… | reservas de sistema (juego, diálogo común, herramientas) |

- `SceKernelAllocMemBlockOpt` (0x40 B): `size`, `attr`, `alignment`, …;
  el flag `HAS_ALIGNMENT = 0x4`, `PHYCONT = 0x200000`, `SKIP_ZERO_FILL =
  0x400000` **[V]**. `sceKernelAllocUnmapMemBlock` exige tamaños múltiplos
  de **1 MiB** **[V]**; GXM exige alineaciones propias (§5).
- `sceKernelGetFreeMemorySize()` devuelve `size_user`, `size_cdram` y
  `size_phycont` libres **[V]** — herramienta base de diagnóstico.
- La memoria disponible para `sceKernelAllocMemBlock` **depende de la
  aplicación anfitriona** (modo normal vs. ampliado) **[V taipool]**.
  Unity para Vita documentaba modos de expansión de +29 MB y +77 MB
  **[V buscador]**; el atributo `ATTRIBUTE2=12` del SFO (usado por
  `cargo-vita` y `godot4-vita`, que citan ~365 MiB de usuario) es el
  equivalente en homebrew **[V docs/12]**. **Nuestra app no lo pasa hoy** (docs/12 §7).

### 3.2 El heap de newlib **[V]** (`newlib/libc/sys/vita/sbrk.c`)
- Un único memblock llamado `"Newlib heap"`, tipo `0x0c20d060`, creado en
  `_init_vita_heap()`; `_sbrk_r` reparte trozos de él.
- Tamaño por defecto **128 MiB**. Se cambia definiendo
  `unsigned int _newlib_heap_size_user = N;` en la aplicación (el código
  comprueba la *dirección* del símbolo débil, no su valor). Valor 0 ⇒ falla.
- Si falla: `sbrk` devuelve -1/`ENOMEM`.
- En C: `unsigned int _newlib_heap_size_user = 192u * 1024 * 1024;`
  En Rust: `#[unsafe(no_mangle)] pub static _newlib_heap_size_user: u32 = …;`
  (explicado en `docs/15`).
- Consecuencia: `malloc` **no** puede superar el heap; **todo lo que pida
  más** (texturas, GXM, hilos con stacks grandes) usa memblocks aparte.
  Con 128 MiB de heap y la RAM de usuario de la app, repartir:
  heap + stacks + memblocks GPU ≤ presupuesto de la app **[I]**.

### 3.3 Memoria y GPU: vitaGL **[V]** (`vitaGL.h`, `gxm.c`)
`vglMemType`: `VRAM` (CDRAM), `RAM` (USER_RW), `PHYCONT`, `BUDGET` (CDLG),
`EXTERNAL` (newlib). `vglInitWithCustomSizes(legacy, w, h, ram, cdram,
phycont, cdlg, msaa)` fija los pools; `vglSetCircularPoolSize` (defecto
**32 MB**), `vglUseCachedMem`, `vglUseExtraMem` (fallback a newlib, por
defecto ON), `vglMemFree/Total(tipo)` para medir, `vglAllocFromScratch`
(válida ~3 frames). Defaults de GXM **[V]**: parameter buffer **16 MiB**
(mínimo 256 KiB), anillo VDM 128 KiB, vértices 2 MiB, fragmentos 512 KiB,
USSE 16 KiB; shader patcher 1 MiB ×3; 3 display buffers (superficies
A8B8G8R8 lineales).

### 3.4 Reglas de oro de memoria (para este proyecto)
1. **Presupuesto explícito** al arrancar: loguear (`netlog`) `size_user`,
   `size_cdram`, `size_phycont` y `vglMemFree/Total` tras `vglInit`.
2. **Sin `malloc` en el bucle**: los módulos duales ya reciben buffer del
   llamador (`mem-pool`, `msg-ring`).
3. Buffers que lee la GPU o el DMA: **no cacheados / contiguos**; buffers
   que solo lee la CPU: **cacheados** **[I]** (medir en E-H3).
4. Alinear a **línea de caché (32 B)** las estructuras calientes y a
   **16 B** lo que vaya a NEON/GXM **[A/V]**.

---

## 4. Hilos

**API nativa (SceKernel)**
- `sceKernelCreateThread(nombre, entry, prioridad, stack, attr, cpuAffinityMask, opt)`
  (la firma con `cpuAffinityMask` figura en la documentación de vitasdk
  **[V buscador]**); `sceKernelChangeThreadCpuAffinityMask(thid, mask)`.
- `SceKernelThreadInfo` (0x80 B) expone `initPriority`, `currentPriority`,
  `initCpuAffinityMask`, `currentCpuAffinityMask`, `currentCpuId`,
  `lastExecutedCpuId`, `runClocks`, `threadPreemptCount`, `changeCpuCount`
  **[V]** → **permite medir en hardware dónde corre cada hilo**.
- La máscara de afinidad va "codificada en los bits 16–19"; el valor
  `SCE_KERNEL_THREAD_CPU_AFFINITY_MASK_DEFAULT = 0` hereda la del hilo
  llamador **[V]**. `SceKernelThreadRunStatus.cpuInfo[4]`: el planificador
  maneja 4 CPUs **[V]**.
- Prioridad por defecto de usuario `0x10000100` y stack típico `0x10000`
  (64 KiB) en el hilo recolector de vitaGL **[V]**. Menor número = mayor
  prioridad **[I]**; el rango válido **[?]**.

**Capa newlib/pthread**
- newlib guarda estado por hilo en una tabla de **256 entradas**
  (`MAX_THREADS`) con un slot TLS (índice `0x89`) y un mutex global
  **[V]** (`threading.c`): crear/destruir hilos en masa tiene coste
  y tope → usar **pools de hilos fijos**.
- Los `pthread_*` de VitaSDK se apoyan en primitivas SCE (mutex, semáforos,
  eventflags) **[I]** — implementación exacta **[?]** (pendiente leerla).
- Rust `std::thread` en este target pasa por `libc`/pthreads de newlib
  (fork `vita-rust/libc`) **[I]**; con `#![no_std]` + `sceKernelCreateThread`
  (vía `vitasdk-sys`) se evita el coste de `std` **[I]**.

**Hipótesis a verificar (E-H2)**: un homebrew puede ejecutar hilos en 3 de
los 4 núcleos (el cuarto lo reserva el sistema). Fuente débil: comentario
de foro vía buscador **[?]**. Experimento: crear 4 hilos con máscaras
`1<<16, 2<<16, 4<<16, 8<<16` y leer `currentCpuId` (`tools/hwprobe/`).

**Patrón recomendado para ROS2 en la Vita [I]**
| Hilo | Misión | Notas |
|---|---|---|
| Principal | UI/dibujo (vitaGL) + entrada | dueño del contexto GL |
| Red/ROS | `uxr_run_session_*` con timeout corto | productor de `msg-ring` |
| Opcional | servicios (logs, GC de vitaGL, audio) | vitaGL ya crea el suyo |

Afinidad: fijar red y dibujo a núcleos distintos evita migraciones
(`changeCpuCount` lo delata) **[I]**.

---

## 5. GPU (SGX543MP4+ vía GXM)

- GPU de 4 núcleos PowerVR SGX543, **renderizado diferido por tiles**
  **[V buscador]**; tile de **32×32 px** (`SCE_GXM_TILE_SIZEX/Y = 32`)
  **[V]**. La pantalla es 960×544 **[V godot4-vita]**.
- Límites GXM **[V]** (`psp2common/gxm.h`): 16 atributos y 16 streams de
  vértices, 16 unidades de textura, 14 uniform buffers.
- Alineaciones **[V]**: textura 16 B, superficie de color 4 B,
  depth/stencil 16 B, paleta 64 B; superficies de color en memblocks
  alineados a **1 MiB** (vitaGL).
- Formatos: ETC1 requiere `SCE_GXM_INITIALIZE_FLAG_EXTENDED_FORMAT`
  **[V]**. godot4-vita usa **RGBA4444 por defecto** para ahorrar ancho de
  banda y 64 MiB de presupuesto de texturas **[V]**.
- Shaders en runtime: se compilan con `libshacccg.suprx` (extraído y
  descifrado en la consola) **[V]**; vitaGL puede cachear shaders
  (`HAVE_SHADER_CACHE=1`, `vglSetShaderCachePath`) **[V]**.
- vitaGL **[V]**: máx. 8 escenas por frame y render target, 47 render
  targets de FBO; doble/triple buffer; MSAA 2x/4x con coste de memoria.
- Reloj de GPU hasta 222 MHz; la memoria CDRAM es la rápida para la GPU
  **[I]**.

**Optimización de GPU/CPU para el mini-rviz (checklist [I], medir cada punto)**
1. Un solo `glDrawArrays/Elements` por objeto; agrupar líneas (grid, ejes)
   en un VBO estático creado una vez (`vglBufferData`/pools en CDRAM).
2. Evitar cambios de estado y de programa dentro del frame.
3. Subir matrices una vez por objeto; calcular FK en CPU con `viz-math`
   (f32) y no en el shader.
4. Texturas del mapa en formato compacto (L8/RGBA4444); no recrear cada
   mensaje: actualizar con `glTexSubImage2D` cuando cambie.
5. Medir con `HAVE_PROFILING=1` (perfilador de draw calls de vitaGL) y el
   depurador en pantalla `HAVE_DEBUGGER=1` **[V]**.
6. Presupuesto de frame: a 30 FPS = 33 ms; el bucle actual (`uxr_run_session_time`
   50 ms ⇒ ~20 FPS, docs/11 §2) debe pasar a hilo de red + `msg-ring`.

---

## 6. Qué implica para Rust nativo

Ver `docs/15`. Puntos duros: `max_atomic_width = 64`; `+neon,+vfp3`
disponibles al compilador (auto-vectorización); `relocation_model =
static`; `panic = abort`; heap de newlib de 128 MiB configurable; `std`
parcial.

---

## 7. Componentes personalizados (qué construir y por qué)

| Componente | Motivo basado en hardware | Estado |
|---|---|---|
| `msg-ring` (SPSC) | hilos separados + memoria débil ARM | hecho |
| `viz-math` | matemática f32 contigua, NEON-friendly | esta sesión |
| `msg-cdr` | CDR sin copias ni malloc, buffers acotados | esta sesión |
| `tf-tree` | tabla estática de 32 frames, sin heap | esta sesión |
| Pools de hilos | tope de 256 hilos en newlib; coste de creación | idea |
| Arena de frame | `vglAllocFromScratch` / bump allocator por frame | idea |
| Medidor `hwprobe` | resuelve los [?] de este documento | esqueleto en `tools/hwprobe/` |
| Gestor de reloj | fijar 333/444 MHz según WiFi y batería (E-H1) | idea |

---

## 8. Fuentes

- [vita-headers: `psp2common/kernel/sysmem.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2common/kernel/sysmem.h)
- [vita-headers: `psp2/kernel/sysmem.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2/kernel/sysmem.h)
- [vita-headers: `psp2common/kernel/threadmgr.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2common/kernel/threadmgr.h)
- [vita-headers: `psp2/power.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2/power.h)
- [vita-headers: `psp2/gxm.h`](https://raw.githubusercontent.com/vitasdk/vita-headers/master/include/psp2/gxm.h)
- [vitasdk/newlib: `sbrk.c`](https://raw.githubusercontent.com/vitasdk/newlib/vita/newlib/libc/sys/vita/sbrk.c), [`threading.c`](https://raw.githubusercontent.com/vitasdk/newlib/vita/newlib/libc/sys/vita/threading.c), [`crt0.c`](https://raw.githubusercontent.com/vitasdk/newlib/vita/newlib/libc/sys/vita/crt0.c)
- [vitaGL `vitaGL.h`](https://raw.githubusercontent.com/Rinnegatamante/vitaGL/master/source/vitaGL.h) · [`gxm.c`](https://raw.githubusercontent.com/Rinnegatamante/vitaGL/master/source/gxm.c)
- [taipool](https://github.com/Rinnegatamante/taipool) (memoria en plugins)
- [Rust target spec `armv7_sony_vita_newlibeabihf.rs`](https://raw.githubusercontent.com/rust-lang/rust/master/compiler/rustc_target/src/spec/targets/armv7_sony_vita_newlibeabihf.rs)
- [vita-rust](https://github.com/vita-rust)
- Búsquedas web: relojes 333/444/500 MHz y pasos de PSVshell
  ([TweakTown](https://www.tweaktown.com/news/47804/sony-underclocked-ps-vitas-cpu-frequency-444mhz/index.html),
  [consolemods: PSVshell](https://consolemods.org/wiki/Vita:PSVshell)),
  expansión de memoria de Unity
  ([docs](https://docs.unity3d.com/kr/560/ScriptReference/PlayerSettings.PSVita-memoryExpansionMode.html)),
  especificaciones generales ([Wikipedia](https://en.wikipedia.org/wiki/PlayStation_Vita)).

---

## 9. Experimentos para cerrar los [?] (`tools/hwprobe/`, requieren Vita)

| ID | Pregunta | Método |
|---|---|---|
| E-H1 | ¿Qué relojes acepta `scePowerSet*` y cuánto rinde 333 vs 444 con WiFi activo? | fijar y leer; bucle de f32 cronometrado |
| E-H2 | ¿Qué núcleos admite un homebrew? | 4 hilos con máscaras `n<<16`; leer `currentCpuId` |
| E-H3 | Ancho de banda memcpy en RAM cacheada / no cacheada / CDRAM | `sceKernelAllocMemBlock` de 4 MiB por tipo, `sceKernelGetProcessTimeWide` |
| E-H4 | RAM útil real: heap máximo, `size_user/cdram/phycont` | `sceKernelGetFreeMemorySize` + sondeo con `malloc` |
| E-H5 | ¿Cambia con `ATTRIBUTE2=12`? | repetir E-H4 con el `.vpk` reempaquetado |
| E-H6 | Tamaño de L2 y latencias | recorrido de punteros con saltos crecientes (idea; no implementado) |
