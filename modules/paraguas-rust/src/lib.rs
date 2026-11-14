//! vita_modules_rust — crate paraguas: un solo staticlib con todos los
//! módulos duales en su variante Rust.
//!
//! `pub use crate_x as nombre;` re-exporta el crate entero. El efecto que
//! buscamos es de LINKER, no de API: al referenciar los crates aquí, rustc
//! incluye sus rlibs (con todos los símbolos `#[unsafe(no_mangle)]` del
//! C-ABI) dentro del staticlib final. La app C de la Vita enlaza
//! libvita_modules_rust.a y encuentra mem_pool_*, net_udp_* y
//! microros_transport_* como si fueran objetos C.

#![no_std]

pub use mem_pool_rust;
pub use microros_transport_rust;
pub use msg_cdr_rust;
pub use msg_ring_rust;
pub use msg_schema_rust;
pub use net_udp_rust;
pub use tf_tree_rust;
pub use viz_math_rust;

// ---------------------------------------------------------------------------
// panic_handler con log (bug B2 de la auditoría, 2026-11-15)
// ---------------------------------------------------------------------------
// Antes era solo `loop {}`: si algo hacía panic (p. ej. un índice fuera de un
// slice), la app se quedaba congelada SIN ningún mensaje. Ahora, en la Vita,
// se escribe primero "panic de Rust: <archivo:línea:columna> <mensaje>" con
// `sceClibPrintf` (la misma salida de consola que usa el port de Godot en
// platform/vita/os_vita.cpp y que el loader ya importa) y DESPUÉS se bloquea.
// Construcciones nuevas explicadas en docs/rust/06-panic-handler-con-log.md.

// `core::fmt::Write` es un TRAIT (una interfaz): quien lo implementa sabe
// recibir texto con `write_str`. A cambio, gana gratis `write!(...)`, el
// mismo formateo de `format!`/`println!` pero sin reservar memoria (no_std).
use core::fmt::Write;

/// Búfer fijo en la pila donde se formatea el mensaje del panic.
/// No usa el heap: dentro de un panic no conviene depender del asignador.
struct BufLog {
    buf: [u8; 256],
    len: usize,
}

impl Write for BufLog {
    /// Copia `s` al búfer; lo que no cabe se descarta (nunca falla ni hace
    /// panic: un panic dentro del panic_handler sería un bucle infinito).
    fn write_str(&mut self, s: &str) -> core::fmt::Result {
        // Se reserva el último byte para el NUL final que espera C.
        let libre = self.buf.len() - 1 - self.len;
        let n = s.len().min(libre);
        self.buf[self.len..self.len + n].copy_from_slice(&s.as_bytes()[..n]);
        self.len += n;
        Ok(())
    }
}

#[cfg(target_os = "vita")]
unsafe extern "C" {
    // `...` declara una función C VARIÁDICA (acepta argumentos extra, como
    // printf). Rust solo puede LLAMARLAS, no definirlas. `c_char` es el
    // `char` de C (u8 en ARM).
    fn sceClibPrintf(fmt: *const core::ffi::c_char, ...) -> i32;
}

// El ÚNICO panic_handler del lado Rust de la app (ver Cargo.toml).
// `#[panic_handler]` marca la función que el compilador llama en todo panic
// de un crate no_std. Recibe `&PanicInfo`: la ubicación (`info.location()`)
// y el mensaje; su `Display` ya los junta como
// "panicked at src/lib.rs:12:5:\n<mensaje>". El tipo `-> !` ("never")
// significa que la función NUNCA vuelve.
#[panic_handler]
fn panic(info: &core::panic::PanicInfo) -> ! {
    let mut log = BufLog { buf: [0; 256], len: 0 };
    // `let _ =` ignora a propósito el Result (BufLog nunca falla).
    let _ = write!(log, "panic de Rust: {}", info);
    // El búfer empezó a ceros y write_str deja libre el último byte, así
    // que siempre hay un NUL detrás del texto: es una cadena C válida.
    #[cfg(target_os = "vita")]
    unsafe {
        // "%s\n" en lugar de pasar el texto como formato: si el mensaje
        // contuviera un '%', printf lo interpretaría como un argumento.
        sceClibPrintf(c"%s\n".as_ptr(), log.buf.as_ptr());
    }
    // En el host (el paraguas no se usa allí) no hay salida: solo se evita
    // el aviso de variable sin usar.
    #[cfg(not(target_os = "vita"))]
    let _ = &log;
    loop {}
}

#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}
