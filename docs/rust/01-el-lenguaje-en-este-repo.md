# Rust 01 — El lenguaje, construcción a construcción

> Cada entrada: qué es, cómo se relaciona con C, y dónde verla usada en el
> repo. El orden sigue aproximadamente la primera aparición en
> `modules/mem-pool/impl-rust/src/lib.rs`.

## Variables y tipos

```rust
let eff = 8;            // inmutable por defecto (¡al revés que C!)
let mut count = 0;      // `mut` para poder reasignar
const POOL_ALIGN: usize = 8;  // constante de compilación, tipo obligatorio
```

- **Inmutabilidad por defecto**: `let x = 5; x = 6;` no compila. Esto
  convierte en explícito todo lo que cambia.
- Tipos enteros con tamaño en el nombre: `i32`/`u32` (= `int32_t`/`uint32_t`),
  `u8` (= `uint8_t`), `usize`/`isize` (= `size_t`/`ssize_t`).
- **No hay conversiones implícitas**: `usize + i32` no compila; se convierte
  explícito con `as` (`x as usize`). Elimina toda una familia de bugs de C.

## `if` y bloques son expresiones

```rust
let eff = if block_size < 8 { 8 } else { block_size };  // no existe ?: — no hace falta
```

La última expresión de un bloque (sin `;`) es su valor. Por eso muchas
funciones del repo terminan en una línea sin `return` ni `;`:
`mem_pool_alloc` devuelve `head as *mut c_void` así.

## Funciones

```rust
fn round_up_align(n: usize) -> usize { ... }   // privada del módulo
pub extern "C" fn mem_pool_alloc(...) -> ...   // pública con ABI de C
```

`fn nombre(args) -> tipo_retorno`. `pub` = visible fuera del módulo (sin
`pub` es `static` de C, privada). `extern "C"` se explica en `docs/rust/02`.

## Structs y `derive`

```rust
#[repr(C)]                      // layout de C (ver docs/rust/02)
#[derive(Clone, Copy)]          // genera código automáticamente
pub struct NetUdpSocket { fd: i32, in_use: u8 }
```

`#[derive(...)]` le pide al compilador que escriba implementaciones
estándar: `Copy` permite copiar el struct bit a bit (necesario para
inicializar arrays con `[VALOR; N]`, como la tabla de sockets de
`net-udp`).

## `Option<T>`: el "puede no haber valor" sin NULL

```rust
fn parse_ipv4(ip: *const u8) -> Option<u32>   // Some(addr) o None
```

En C, una función que puede fallar devuelve un valor centinela (NULL, -1,
0) y nada te obliga a comprobarlo. `Option` es un enum con dos variantes
(`Some(valor)` / `None`) y **el compilador no deja sacar el valor sin
tratar el caso `None`**. Formas de consumirlo usadas en el repo:

```rust
// `match`: el switch exhaustivo de Rust (cubrir todos los casos u error)
match eff.checked_mul(count) {
    Some(total) => total,
    None => 0,
}

// `let ... else`: desempaqueta o sal de la función (patrón muy común)
let Some(addr_be) = parse_ipv4(ip) else {
    return ptr::null_mut();
};

// Encadenado con `and_then` (como un pipeline que corta en el primer None)
eff.checked_mul(n).and_then(|x| x.checked_add(64))
```

Esa última línea usa un **closure** (`|x| expresión`): una función anónima,
como las lambdas de C++.

## Aritmética: overflow explícito

En C, `SIZE_MAX + 1` "da la vuelta" en silencio; en Rust en modo debug
**panica** y en release da la vuelta. Para tratar el desbordamiento como
caso normal del dominio están `checked_add`/`checked_mul`, que devuelven
`Option`. Verlo en `mem_pool_required_size` (las dos implementaciones del
chequeo, C manual y Rust con `checked_*`, hacen lo mismo — el test de
paridad lo demuestra con `SIZE_MAX`).

## Rangos e iteradores en vez de `for (i=0; ...)`

```rust
for i in (0..block_count).rev() { ... }      // block_count-1, ..., 1, 0
sockets.iter_mut().find(|s| s.in_use == 0)   // primer hueco libre, Option<&mut _>
```

`0..n` es un rango (excluye `n`); `.rev()` lo invierte; `.iter_mut()`
presta referencias mutables a cada elemento; `.find(closure)` devuelve
`Option`. Los iteradores compilan a código tan eficiente como el bucle C
equivalente (es la promesa de "abstracción de coste cero").

## `while` clásico cuando toca

Recorrer la free-list intrusiva con punteros crudos no tiene iterador; se
hace con `while !cur.is_null() { ... }` igual que en C
(`mem_pool_free` en `modules/mem-pool/impl-rust/src/lib.rs`).

## Módulos y `use`

```rust
mod sys { ... }              // submódulo (puede tener #[cfg] de plataforma)
use core::ffi::c_void;       // importa un nombre al ámbito
use net_udp_rust::net_udp_send;  // importa de OTRO crate (dependencia)
```

Un archivo `.rs` es un módulo; `mod` anida; `use` acerca nombres. Las rutas
son `crate::`, `self::`, o el nombre de un crate dependiente.

## Compilación condicional: `#[cfg]` y features

```rust
#[cfg(target_os = "vita")]      // como #ifdef __vita__
#[cfg(not(target_os = "vita"))] // como #else
#[cfg(feature = "standalone")]  // flag definido en Cargo.toml [features]
#[allow(dead_code)]             // silencia un warning concreto y localizado
```

En `net-udp` hay un módulo `sys` para Linux y otro para la Vita, ambos con
la misma interfaz interna: el resto del archivo compila idéntico contra
cualquiera de los dos — el `#ifdef` de C, pero a nivel de módulo entero.

## Strings de C en Rust

Rust tiene sus propios strings (`&str`, garantizado UTF-8), pero en la
frontera con C llegan `*const u8` terminados en NUL. En el repo se recorren
a mano byte a byte (`parse_ipv4`) o se crean con el literal `c"net_udp"`
(string C con NUL incluido, tipo `&CStr`).

## Lo que este repo **no** usa todavía (y verás en cualquier tutorial)

`String`/`Vec` (necesitan heap/allocator — nuestros módulos son no_std sin
alloc), `Result<T, E>` con `?` (los errores cruzan la frontera C como
códigos enteros), traits propios, genéricos, lifetimes explícitos, hilos.
Irán apareciendo cuando el proyecto crezca (p. ej. en tooling de PC).
