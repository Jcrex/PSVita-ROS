//! microros-transport — implementación Rust de `include/microros_transport.h`.
//!
//! Novedad de Rust en este módulo: USAR OTRO CRATE NUESTRO como dependencia.
//! `net_udp_rust` se declara en Cargo.toml con una dependencia de ruta y aquí
//! se llama como código Rust normal (`net_udp_rust::net_udp_send(...)`).
//! Sus funciones son `extern "C"`, pero para Rust siguen siendo funciones
//! corrientes; la convención de llamada C no impide invocarlas desde Rust.
//!
//! El handle `*mut NetUdpSocket` que devuelve net_udp_open es un puntero
//! crudo: lo guardamos tal cual en el estado global. Rust nos obliga a
//! marcar cada uso con `unsafe`, dejando visible dónde está el riesgo.

#![no_std]

use core::cell::UnsafeCell;
use core::ptr;

// `use crate_externo::item`: importa del crate dependiente (Cargo lo
// resuelve por el nombre declarado en [dependencies]).
use net_udp_rust::{
    net_udp_close, net_udp_init, net_udp_open, net_udp_recv, net_udp_send,
    NetUdpSocket,
};

// Códigos de net_udp que este adaptador necesita conocer (del header):
const NET_UDP_OK: i32 = 0;
const NET_UDP_ERR_TIMEOUT: i32 = -6;

// Estado global mono-hilo: el único transporte de la app.
// Mismo patrón UnsafeCell + unsafe impl Sync explicado en net-udp.
struct TransportState {
    sock: UnsafeCell<*mut NetUdpSocket>,
}
unsafe impl Sync for TransportState {}

static STATE: TransportState = TransportState {
    sock: UnsafeCell::new(ptr::null_mut()),
};

fn current_sock() -> *mut NetUdpSocket {
    unsafe { *STATE.sock.get() }
}

fn set_sock(s: *mut NetUdpSocket) {
    unsafe { *STATE.sock.get() = s }
}

// Helper: escribir errcode solo si el puntero no es NULL (contrato uxr).
fn set_errcode(errcode: *mut u8, value: u8) {
    if !errcode.is_null() {
        unsafe { *errcode = value }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn microros_transport_open(agent_ip: *const u8,
                                          agent_port: u16) -> bool {
    if !current_sock().is_null() {
        return false; // ya abierto: cerrar antes de reabrir
    }
    if net_udp_init() != NET_UDP_OK {
        return false;
    }
    let sock = net_udp_open(agent_ip, agent_port);
    if sock.is_null() {
        return false;
    }
    set_sock(sock);
    true
}

#[unsafe(no_mangle)]
pub extern "C" fn microros_transport_close() -> bool {
    let sock = current_sock();
    if sock.is_null() {
        return false;
    }
    net_udp_close(sock);
    set_sock(ptr::null_mut());
    true
}

#[unsafe(no_mangle)]
pub extern "C" fn microros_transport_is_open() -> bool {
    !current_sock().is_null()
}

#[unsafe(no_mangle)]
pub extern "C" fn microros_transport_write(buf: *const u8, len: usize,
                                           errcode: *mut u8) -> usize {
    let sock = current_sock();
    if sock.is_null() {
        set_errcode(errcode, 1);
        return 0;
    }
    let sent = net_udp_send(sock, buf, len);
    if sent < 0 {
        set_errcode(errcode, 1);
        return 0;
    }
    set_errcode(errcode, 0);
    sent as usize
}

#[unsafe(no_mangle)]
pub extern "C" fn microros_transport_read(buf: *mut u8, cap: usize,
                                          timeout_ms: i32,
                                          errcode: *mut u8) -> usize {
    let sock = current_sock();
    if sock.is_null() {
        set_errcode(errcode, 1);
        return 0;
    }
    let got = net_udp_recv(sock, buf, cap, timeout_ms);
    if got == NET_UDP_ERR_TIMEOUT {
        set_errcode(errcode, 0); // timeout NO es error para uxr
        return 0;
    }
    if got < 0 {
        set_errcode(errcode, 1);
        return 0;
    }
    set_errcode(errcode, 0);
    got as usize
}

// panic_handler + stub de unwinding: este crate es el "dueño" del binario
// Rust en el build all-rust (net_udp_rust se compila sin `standalone`).
#[cfg(feature = "standalone")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(feature = "standalone")]
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}
