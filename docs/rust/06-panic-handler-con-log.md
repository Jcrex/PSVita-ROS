# Rust 06 — `panic_handler` con log: `PanicInfo`, `core::fmt::Write` y funciones variádicas

> Continúa `00`–`05`. Código real: `modules/paraguas-rust/src/lib.rs` (bug B2 de la
> auditoría `docs/ia/auditoria/README.md`, arreglado el 2026-11-15).

## El problema

En un crate `no_std` (sin biblioteca estándar) no hay nadie que imprima
`thread 'main' panicked at ...`: hay que escribir a mano la función que se llama en
cada panic. Antes el paraguas tenía solo `loop {}`, así que un panic en la Vita (por
ejemplo, un índice fuera de un slice) congelaba la app **sin ningún mensaje**.

## `#[panic_handler]` y `PanicInfo`

```rust
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! { ... }
```
- `#[panic_handler]`: atributo que marca la función a la que salta todo panic. Debe
  haber **exactamente una** en el binario final; por eso los módulos la traen solo con la
  feature `standalone` y el paraguas aporta la única (ver su `Cargo.toml`).
- `&PanicInfo`: datos del panic. `info.location()` da archivo/línea/columna y
  `info.message()` el texto. Implementa `Display`, así que `{}` lo imprime entero:
  `panicked at src/lib.rs:12:5:` + salto de línea + mensaje.
- `-> !`: el tipo «never». La función no puede volver (acaba en `loop {}`).

## `core::fmt::Write`: formatear sin heap

```rust
use core::fmt::Write;

struct BufLog { buf: [u8; 256], len: usize }

impl Write for BufLog {
    fn write_str(&mut self, s: &str) -> core::fmt::Result { ... }
}

let _ = write!(log, "panic de Rust: {}", info);
```
- `Write` es un **trait** (una interfaz). Implementarlo solo exige `write_str`; a cambio,
  la macro `write!` (el mismo formateo que `format!`) funciona sobre nuestro tipo.
- El búfer es un array fijo en la pila: dentro de un panic no conviene pedir memoria.
- `write_str` **trunca** lo que no cabe en vez de fallar: un panic dentro del
  `panic_handler` volvería a entrar en él.
- `let _ = ...` descarta a propósito el `Result` (si no, el compilador avisa).

## Llamar a `sceClibPrintf`: funciones variádicas y `c"..."`

```rust
#[cfg(target_os = "vita")]
unsafe extern "C" {
    fn sceClibPrintf(fmt: *const core::ffi::c_char, ...) -> i32;
}
...
unsafe { sceClibPrintf(c"%s\n".as_ptr(), log.buf.as_ptr()); }
```
- `...` en un `extern "C"`: función **variádica** de C (como `printf`). Rust puede
  llamarlas pero no definirlas.
- `c"%s\n"`: literal de **cadena C** (Rust 1.77+). Es un `&CStr` con el `\0` final ya
  puesto; `.as_ptr()` da el `*const c_char` que espera C.
- Se pasa `"%s\n"` como formato y el texto como argumento: si el mensaje contuviera `%`,
  usarlo como formato haría que printf leyera argumentos inexistentes.
- `sceClibPrintf` ya está en la tabla de imports del loader de godot4-vita (lo usa
  `platform/vita/os_vita.cpp`); `tools/check-vita-imports.py` da 0 imports nuevos.
- `#[cfg(target_os = "vita")]`: solo se compila para la Vita; en el host no hay salida.

## Validar en hardware

El mensaje sale por la consola de `sceClibPrintf` (visible con un plugin de consola tipo
PrincessLog o en el log de Vita3K). **Validar en hardware**: hoy la plantilla por defecto
de Godot usa las implementaciones C; solo entra en ella si se compila con
`RUST_PIC_LIB=...` (`tools/build-godot-template.sh`).
