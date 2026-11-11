# Rust 03 — Atómicos y hilos (lo que usa `msg-ring`)

> Continúa la serie: `00` herramientas, `01` lenguaje, `02` FFI y `unsafe`.
> Código real: `modules/msg-ring/impl-rust/src/lib.rs`.

## El problema

Dos hilos (red y dibujo) comparten una cola. Si ambos tocan los mismos
contadores sin coordinación hay una **carrera de datos**: comportamiento
indefinido en C y *imposible* en Rust "safe". La solución habitual es un
mutex; aquí se evita con **atómicos** para no bloquear nunca el hilo de red.

## `AtomicU32`

Un `u32` cuyas lecturas/escrituras son indivisibles y seguras entre hilos.
Equivale a `_Atomic uint32_t` de C11 (`impl-c/msg_ring.c`). Sus métodos
toman `&self` (referencia compartida, no `&mut`): por eso dos hilos pueden
usarlo a la vez sin que Rust lo prohíba.

```rust
r.tail.store(tail.wrapping_add(1), Ordering::Release);
let head = r.head.load(Ordering::Acquire);
```

## `Ordering` (equivale a `memory_order_*`)

| Ordering | Garantía | Uso en msg-ring |
|---|---|---|
| `Relaxed` | Solo atomicidad, sin orden respecto a otros datos | leer MI propio contador; contar `dropped` |
| `Release` (en `store`) | Todo lo escrito ANTES es visible a quien lea este valor con `Acquire` | el productor publica `tail` tras copiar el mensaje |
| `Acquire` (en `load`) | Ve lo publicado por el `Release` correspondiente | el consumidor lee `tail` antes de leer la ranura |

Sin `Release/Acquire`, la Cortex-A9 de la Vita (memoria débilmente
ordenada) podría mostrar `tail` actualizado con el contenido aún sin
escribir. En x86 esto casi nunca se nota: por eso los tests de host no
bastan y queda pendiente la prueba en hardware.

## Otras construcciones nuevas

- `wrapping_add` / `wrapping_sub`: aritmética que *da la vuelta* al
  desbordar (los contadores u32 crecen sin fin a propósito). Un `+`
  normal entraría en pánico en modo debug.
- `ptr::write(ptr, valor)`: inicializa memoria sin leer ni destruir lo que
  hubiera (el buffer del llamador contiene basura).
- `ptr::copy_nonoverlapping(src, dst, n)`: el `memcpy` de Rust.
- `write_unaligned` / `read_unaligned`: acceso a un `u32` en una dirección
  no alineada a 4 (el prefijo de longitud de la ranura).
- `&*ptr`: de puntero crudo a referencia `&T` (dentro de `unsafe`; el
  llamador de C promete que es válido).
- `is_power_of_two()`: método de los enteros sin signo.
- `/// # Safety`: convención que documenta qué debe cumplir el llamador de
  una función `unsafe`.

## Dónde profundizar

[The Rust Book, cap. 16 (concurrencia)](https://doc.rust-lang.org/book/ch16-00-concurrency.html)
y el *Rustonomicon*, capítulo "Atomics".
