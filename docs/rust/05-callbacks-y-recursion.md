# Rust 05 — Punteros a función de C, `macro_rules!` y recursión con `Result` (msg-schema)

> Continúa `00`–`04`. Código real: `modules/msg-schema/impl-rust/src/lib.rs`.

## Callbacks de C dentro de un struct

El header de C define structs con punteros a función (`msg_visitor`,
`msg_source`) que el código del llamador rellena. En Rust se declaran así:

```rust
#[repr(C)]
pub struct MsgVisitor {
    begin_struct: Option<unsafe extern "C" fn(*mut c_void, *const c_char) -> i32>,
    ...
}
```
- `unsafe extern "C" fn(...) -> i32`: tipo de un puntero a función con la
  convención de llamada de C. Llamarlo es `unsafe` (Rust no puede comprobarlo).
- `Option<fn>`: en C un puntero a función puede ser `NULL` ("sin callback").
  `Option<fn>` tiene **exactamente el mismo layout** (`None` = NULL), así que el
  struct sigue siendo compatible con C y Rust nos obliga a tratar el caso nulo.
- `*mut c_void`: el `void *ctx` opaco de C que se devuelve tal cual al callback.

## `macro_rules!`

```rust
macro_rules! cb {
    ($f:expr, $($arg:expr),* $(,)?) => {
        if let Some(f) = $f { if unsafe { f($($arg),*) } != 0 { return Err(ERR_ABORTED); } }
    };
}
```
Un macro por patrones: `$f:expr` captura una expresión; `$($arg:expr),*` captura
cero o más argumentos separados por comas; `$(,)?` admite una coma final.
Se expande **antes** de compilar (como un `#define`, pero comprobado por el
compilador). `if let Some(f) = opcional` ejecuta el bloque solo si hay valor.

## Recursión con `Result` y `?`

`strukt()` → `field()` → `strukt()` ... recorre un mensaje anidado. Cada nivel
devuelve `R<()>` (`Result<(), i32>`), y el operador `?` propaga el primer error
hacia arriba sin código repetido. Un parámetro `depth` y la constante
`MAX_DEPTH` evitan la recursión infinita con un esquema corrupto.

## Otras construcciones nuevas

- `checked_mul` → `Option`: multiplicación que avisa del desbordamiento (en la
  Vita `usize` es de 32 bits).
- `.ok_or(ERR)?`: convierte `Option` en `Result` (`None` → `Err(ERR)`).
- Closure inmediata `(|| -> R<()> { ... })()`: agrupa varios `?` en un bloque.
- `slice.contains(&0)`: búsqueda lineal de un valor en un slice.
- `#[allow(unused_unsafe)]`: silencia el aviso cuando un macro trae su propio `unsafe`.
