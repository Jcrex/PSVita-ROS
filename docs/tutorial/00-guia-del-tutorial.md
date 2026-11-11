# Tutorial — Guía

Aprendes leyendo y modificando **el código real** del repo. Empieza por la
[ruta de aprendizaje (07)](./07-ruta-completa-de-aprendizaje.md).

## Lecciones

| # | Lección | Aprendes |
|---|---|---|
| 01 | C con **mem-pool** | punteros, memoria, compilar C |
| 02 | Rust con mem-pool *(pendiente)* | ownership, `unsafe`, FFI |
| 03 | **net-udp** *(pendiente)* | sockets UDP, host frente a Vita |
| 04 | **microros-transport** *(pendiente)* | callbacks, cómo encajan los módulos |
| 05 | App de la Vita *(pendiente)* | bucle principal, mandos, red |
| 06 | Compilar y `.vpk` *(pendiente)* | VitaSDK, CMake, instalar |
| 07 | **Ruta de aprendizaje** | el mapa y el método |
| 08 | **IMU con Godot (G7a)** | editor, GDScript, ROS 2, QoS |

Las lecciones 02–06 están **pendientes de escribir** (su guion: `docs/ia/plan-tutorial-2026-07-12.md`).

## El patrón dual

Cada módulo de `modules/` tiene:

- `include/<mod>.h`: el **contrato** (la verdad).
- `impl-c/` e `impl-rust/`: dos implementaciones del mismo contrato.
- Los mismos tests para ambas: `tools/run-parity-tests.sh <mod>`.

## Dónde se compila cada cosa

- 🐳 **Módulos (C/Rust):** en cualquier máquina, con `tools/run-parity-tests.sh`.
- 🎮 **Vita y Godot:** solo en el PC, con VitaSDK y el editor 4.8-dev7.

## Cómo hacer un reto

1. Cambia el archivo que indica el reto.
2. Verifica (tests o comandos de la lección).
3. Deshaz con `git checkout -- <archivo>`, o guárdalo en tu rama: `git checkout -b practica/<nombre>`.

Tus programas de prueba van en `practica/` (no se sube a git). Ejemplo:

```bash
gcc -std=c11 -Wall -I modules/mem-pool/include \
    practica/prueba.c modules/mem-pool/impl-c/mem_pool.c -o practica/prueba && ./practica/prueba
```

**Regla:** nunca hagas commit con los tests de paridad en rojo.

## Mi progreso

| Lección | Leída | Retos |
|---|---|---|
| 01 | ☐ | ☐ |
| 02–06 (pendientes) | — | — |
| 08 (G7a) | ☐ | ☐ |
