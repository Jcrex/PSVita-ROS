# Rust 04 — `Result`, `?`, slices, `CStr` y arrays genéricos (msg-cdr y tf-tree)

> Continúa `00`–`03`. Código real: `modules/msg-cdr/impl-rust/src/lib.rs` y
> `modules/tf-tree/impl-rust/src/lib.rs`.

## `Result<T, E>` y el operador `?`

C devuelve códigos y se comprueban a mano (`TRY(...)` en `msg_cdr.c`). Rust
tiene un tipo para "puede fallar": `Result<T, i32>` vale `Ok(valor)` o
`Err(codigo)`. Al final de una expresión, `?` significa: *si es `Err`, sal de
la función devolviendo ese `Err`; si es `Ok`, dame el valor*.

```rust
fn u32(&mut self) -> R<u32> { self.align(4)?; self.need(4)?; ... Ok(valor) }
```

En la frontera C se convierte a entero (`to_code`).

## Slices `&[u8]` y lifetimes

Un slice es "puntero + longitud" **prestado**: no copia. `&self.b[a..b]` es un
sub-slice. El `'a` de `Cur<'a>` expresa que el cursor no puede vivir más que
el buffer del que lee (el compilador lo comprueba; en C es un error silencioso).
`core::slice::from_raw_parts(ptr, len)` fabrica un slice desde un puntero de C
y por eso es `unsafe`.

## `Option<T>`

`Some(x)` o `None`. `find(...)` devuelve `Option<usize>` ("índice o nada");
`norm(...)` devuelve `Option<&[u8]>`. `if let (Some(a), Some(b)) = (x, y)`
entra solo si ambos tienen valor; `.and_then(f)` encadena.

## `CStr`

`core::ffi::CStr::from_ptr(p).to_bytes()` convierte un `char *` de C en
`&[u8]` hasta el NUL (es `strlen` + vista segura) y existe en `no_std`.

## Genéricos constantes: `fn f64s<const N: usize>(out: &mut [f64; N])`

El tamaño del array es parte del tipo; una sola función sirve para `[f64;3]`
y `[f64;4]`. `out.iter_mut()` recorre dando `&mut` a cada elemento.

## Préstamos disjuntos

`tf_transform(c, &mut out.items[i], &mut out.strings_truncated)` presta a la
vez dos CAMPOS distintos de `out`: Rust lo permite porque no se solapan. Sirvió
para acumular contadores igual que C (`docs` de msg-cdr: el fuzz detectó que
hacerlo "al final" cambiaba el estado parcial ante errores).

## Otras novedades

- `r#type`: identificador que coincide con una palabra reservada.
- `core::mem::zeroed()` (unsafe): memoria a ceros; solo para tipos que lo admiten.
- `ptr::write_bytes(p, 0, 1)`: `memset` de un valor.
- `f32::from_bits(u32)`: reinterpretar bits, sin conversión numérica.
- `const _: () = assert!(size_of::<T>() == N)`: comprobación de layout en compilación.
- `.min()`, `.unwrap_or()`, `.position()` de iteradores/Option.
