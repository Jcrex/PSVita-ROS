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
pub use net_udp_rust;

// El ÚNICO panic_handler del lado Rust de la app (ver Cargo.toml).
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}
