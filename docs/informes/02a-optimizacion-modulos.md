---
title: "Informe 02a — Optimización de los módulos de bajo nivel"
description: "Coste en memoria y CPU de los ocho módulos duales en la Vita, bugs encontrados y optimizaciones priorizadas."
fecha: 2026-11-01
---

# Informe 02a — Optimización de los módulos

Detalle completo (por función, con mediciones): `docs/ia/auditoria/02a-optimizacion-modulos.md`.

## Lo esencial

- En la Vita **solo se ejecutan tres módulos**: `msg-schema` (cada mensaje), `net-udp` y
  `microros-transport` (cada datagrama). `msg-ring` está compilado en Godot, pero nadie lo llama.
  `viz-math`, `msg-cdr`, `tf-tree` y `mem-pool` no se usan en ningún binario.
- No son el cuello de botella (un `/odom` se decodifica en microsegundos): rinden más los **flags**.
- La paridad sigue verde: 8/8 módulos en C y en Rust.

## Bugs

| ID | Dónde | Qué pasa |
|---|---|---|
| B1 | `msg_schema.c:58-73` y `lib.rs:135-144` | Un `.rsch` corrupto (`strings_off > total`): **lectura fuera de límites** en C (ASan) y **cuelgue** en Rust |
| B2 | `vita-app/rust-modules/src/lib.rs:23-25` | Pánico = `loop {}`: hilo al 100 % sin log |
| B3 | `net_udp.c:260`, `lib.rs:465` | `timeout_ms * 1000` desborda (UB en C) |

## Top de optimizaciones

| # | Qué | Ganancia | ¿Toca las dos implementaciones? |
|---|---|---|---|
| 1 | Compilar vita-app en `Release`: hoy va a **-O0** porque `CMAKE_BUILD_TYPE` está vacío | Alta | No |
| 2 | Quitar el pool de 1 MiB de `net_udp.c:40`: en Godot no se usa | −1 MiB RAM | Sí (header) |
| 3 | `-O2` para los `.c` de módulos en `godot/ros2_vita/SCsub` (hoy `-Os`) | −30 % decode (host) | No |
| 4 | Manejador de pánico que deje log y aborte | Diagnóstico | No |
| 5 | Subir la MTU de XRCE de 512 a ~1400 B | ÷3 syscalls en mensajes grandes | No |
| 6 | No repetir `sceNetSetsockopt` si el timeout no cambia | −1 syscall | Sí |
| 7 | Perfil Rust del paraguas con `lto = "fat"`, `codegen-units = 1` | Binario más pequeño | No |

Corrige `docs/14` y `docs/15`: **NEON no se auto-vectoriza** con `float` (0 instrucciones NEON en
`viz_math` para la Vita); hay que escribirlo a mano.

## Comandos para comprobarlo (PC, fish)

```fish
set B toolchains/vitasdk/bin
grep CMAKE_BUILD_TYPE vita-app/build-c/CMakeCache.txt
$B/arm-vita-eabi-size modules/net-udp/impl-c/net_udp.vita.template_release.arm32.o
$B/arm-vita-eabi-nm -u modules/msg-schema/impl-c/msg_schema.vita.template_release.arm32.o
```

`grep`: vacío = sin optimizar. `size`: la columna `bss` es el MiB del pool. `nm -u`: imports;
`__aeabi_uidiv` = división por software (el Cortex-A9 no divide enteros por hardware).

## Comprueba que lo has entendido

1. ¿Por qué el bug B1 lee memoria ajena en C pero en Rust se convierte en un cuelgue? Pista: qué hace
   Rust al indexar `b[i]` y qué hace nuestro `panic_handler`.
2. Si `-O2` acelera `msg_schema_decode` un 30 %, ¿por qué apenas cambia los FPS de la HMI? ¿Dónde está el
   coste de verdad?
3. En `msg-ring`, `head` y `tail` viven en la misma línea de caché de 32 B. ¿Por qué hoy da igual y cuándo
   empezaría a importar?
