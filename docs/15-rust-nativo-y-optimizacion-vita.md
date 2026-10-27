# 15 — Rust nativo en la Vita: cómo usarlo y cómo optimizarlo

**Fecha:** 2026-10-27 · Complementa `docs/14` (hardware) y `docs/03`/ADR 0003
(estrategia dual). Marcas: **[V]** verificado en fuente o en el repo ·
**[I]** inferencia · **[?]** pendiente de comprobar (PC/Vita).

## 1. Qué es hoy Rust en este repo (hecho)

- Target `armv7-sony-vita-newlibeabihf` (Tier 3) con `-Zbuild-std=std,panic_abort`,
  nightly **[V]** (ADR 0003; `vita-app/CMakeLists.txt`).
- Todos los módulos son **crates `rlib` `#![no_std]`** con ABI C; la app C
  enlaza **un único staticlib** producido por el crate paraguas
  `vita-app/rust-modules/` **[V]**. Desde 2026-10-27 el paraguas incluye
  `msg-ring`, `viz-math`, `msg-cdr` y `tf-tree` (compila y enlaza en host,
  sin símbolos duplicados; **cross-compilar en el PC [?]**).
- Los tests de paridad ejecutan la misma batería C y Rust en host.

## 2. Tres formas de usar Rust, y cuándo cada una

| Modo | Qué es | Cuándo | Estado |
|---|---|---|---|
| **A. Módulos Rust + app C** (actual) | staticlib por ABI C | núcleo de bajo nivel intercambiable con C; Godot | **en uso** |
| **B. App Rust completa** | `cargo vita build vpk` + `vitasdk-sys` (bindings a `psp2`) | herramientas pequeñas, sondas, prototipos | herramienta disponible **[V]**, sin app propia aún |
| **C. Mixta** | app Rust que enlaza XRCE (C) por FFI | si en el futuro se quiere `main` en Rust | idea; exige reescribir `main.c`/`uxr_glue.c` |

Recomendación **[I]**: mantener A mientras exista el requisito dual (C
permanente); usar B para utilidades nuevas (p. ej. una versión Rust de
`hwprobe`) donde no hay equivalente C obligatorio. Tu SDK/entorno Rust
nativo de pruebas anteriores **no está en el repo**: si contiene wrappers
(vitasdk-sys propio, helpers de hilos o memoria), súbelos o descríbelos y
se integran como `modules/` dual o `docs/rust/` (ver §8).

## 3. El target, por dentro (spec oficial) **[V]**

`llvm_target = thumbv7a-sony-vita-eabihf`, `cpu = cortex-a9`,
`features = +v7,+neon,+vfp3,+thumb2,+thumb-mode`, `max_atomic_width = 64`,
linker `arm-vita-eabi-gcc` con `-Wl,-q -Wl,--pic-veneer`,
`relocation_model = static`, `os = vita`, `env = newlib`, `std = true`.
Consecuencias:
- `AtomicU64` existe (útil para contadores de tiempo), pero **ARMv7 no tiene
  ABA-free CAS de 128 bit**: nada de atómicos mayores a 64 bits.
- `+thumb-mode` por defecto: código Thumb-2 (denso). En un bucle caliente
  podría convenir ARM mode (`-C target-feature=-thumb-mode`) **[?]**: medir;
  en Cortex-A9 la diferencia suele ser pequeña **[I]**.
- `+neon,+vfp3`: LLVM puede **auto-vectorizar** `f32`/enteros con NEON.
  Las intrínsecas `core::arch::arm` NEON en ARM de 32 bit son inestables
  **[?]**; preferir auto-vectorización y comprobarla leyendo el ensamblador
  (`cargo rustc --release -- --emit asm` y buscar `vmla.f32 q`, `vadd.f32 q`).

## 4. Perfil de compilación recomendado (a validar en el PC)

```toml
[profile.release]
opt-level = 3          # o "s" si el .vpk/caché de instrucciones importa [?] medir
lto = "fat"            # una sola unidad de optimización entre crates del paraguas
codegen-units = 1      # mejor optimización, compilación más lenta
panic = "abort"        # ya en uso: sin unwinding en embebido
debug = false
```
- `RUSTFLAGS="-C target-cpu=cortex-a9"` ya lo implica el target **[V]**.
- Con `-Zbuild-std=std,panic_abort` el `std` también se compila con estas
  opciones **[I]**.
- Cada cambio se acepta **solo con medición** (hwprobe + FPS + tamaño). No
  hay números aún.

## 5. Memoria desde Rust (ver `docs/14` §3)

- El asignador global de `std` usa `malloc` de newlib → el **heap de newlib**
  (128 MiB por defecto) **[V]**.
- Para cambiarlo, definir el símbolo que newlib consulta:
  ```rust
  // El nombre debe quedar SIN modificar para que el linker de newlib lo vea.
  #[unsafe(no_mangle)]
  pub static _newlib_heap_size_user: u32 = 192 * 1024 * 1024;
  ```
  **[?]** newlib comprueba la *dirección* del símbolo débil (`sbrk.c`) y luego
  lee su valor; una `static` Rust con `no_mangle` debería cumplirlo — validar
  en el PC con `arm-vita-eabi-nm`.
- En `no_std` puro: sin asignador global; usar buffers estáticos
  (`static mut`/`UnsafeCell`) y los módulos `mem-pool`/`msg-ring` **[V]**.
- Memoria de GPU/DMA: `sceKernelAllocMemBlock` (vía `vitasdk-sys`), no
  `malloc` (tipos en `docs/14` §3.1).

## 6. Hilos desde Rust

- `std::thread` (pthreads de newlib sobre SCE) o `sceKernelCreateThread` con
  máscara de afinidad (bits 16–19) vía `vitasdk-sys` **[I]** (los nombres de
  `vitasdk-sys` replican los de C; confirmar en el PC).
- Para datos entre hilos: `msg-ring` (SPSC) con ordering `Acquire/Release`
  (`docs/rust/03`). Evitar `Mutex` en la ruta de red.
- La tabla de hilos de newlib tiene **256 entradas** **[V]**: reutilizar
  hilos (pool) en vez de crear/destruir.

## 7. Optimización CPU/GPU: método

1. **Medir antes:** `hwprobe` (docs/14 §9), `netlog` con tiempos por fase del
   frame, `HAVE_PROFILING` de vitaGL, `scePower*` para el reloj.
2. **Cuello de botella:** CPU de aplicación (un hilo), GPU (draw calls /
   relleno), red (WiFi, `uxr_run_session_time`) o memoria (ancho de banda).
3. **Palancas ordenadas por coste/beneficio [I]:** (a) quitar trabajo
   (menos mensajes, menos draw calls), (b) mover trabajo a otro hilo/núcleo,
   (c) formatos compactos (RGBA4444, `f32`, mapas L8), (d) NEON/ARM-mode en
   bucles medidos, (e) overclock 444 MHz si WiFi lo permite.
4. **Un cambio por experimento;** registrar números en la bitácora.

## 8. Qué construir en Rust (backlog verificable en la laptop)

| Pieza | Por qué | Dónde se prueba |
|---|---|---|
| `msg-ring`, `viz-math`, `msg-cdr`, `tf-tree` | núcleo de visualización | **hechos** (host) |
| Pool de hilos `thread-pool` | tope de 256 hilos / coste de creación | diseño + host con `std` |
| Arena por frame (`frame-arena`) | cero `malloc` en el bucle de dibujo | host |
| Envoltorio seguro de `vitasdk-sys` (`vita-safe`) | `unsafe` acotado en un sitio | PC |
| `hwprobe` en Rust (modo B) | primera app Rust completa del repo | PC + Vita |
| Wrappers del SDK propio del usuario | integrar lo ya logrado | por definir |

## 9. Fuentes

- [Target spec](https://raw.githubusercontent.com/rust-lang/rust/master/compiler/rustc_target/src/spec/targets/armv7_sony_vita_newlibeabihf.rs) ·
  [Platform support (md)](https://raw.githubusercontent.com/rust-lang/rust/master/src/doc/rustc/src/platform-support/armv7-sony-vita-newlibeabihf.md)
- [vita-rust](https://github.com/vita-rust) · [cargo-vita](https://github.com/vita-rust/cargo-vita)
- [newlib `sbrk.c` de VitaSDK](https://raw.githubusercontent.com/vitasdk/newlib/vita/newlib/libc/sys/vita/sbrk.c)
