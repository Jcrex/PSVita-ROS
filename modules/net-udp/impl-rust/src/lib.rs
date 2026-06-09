//! net-udp — implementación Rust del contrato `include/net_udp.h`.
//!
//! Novedades de Rust respecto a mem-pool (todas explicadas in situ):
//!  - Bloques `unsafe extern "C"`: declarar funciones de OTRA biblioteca
//!    (la libc de Linux o los stubs sceNet de VitaSDK) para llamarlas desde
//!    Rust. Es el "extern" de C pero explícito y por símbolo. No usamos el
//!    crate `libc` a propósito: declarar el FFI a mano enseña qué hay debajo
//!    y evita dependencias de red en el build.
//!  - `#[cfg(target_os = ...)]`: compilación condicional por plataforma,
//!    el equivalente del `#ifdef __vita__` del lado C.
//!  - `static` + `UnsafeCell`: estado global mutable sin malloc (la tabla
//!    de sockets), con la promesa explícita de uso mono-hilo.
//!  - `Option<T>`: el "puntero que puede no estar" de Rust, sin NULL.

#![no_std]

use core::cell::UnsafeCell;
use core::ffi::c_void;
use core::ptr;

// ---------------------------------------------------------------------------
// Códigos de estado del header (net_udp_status)
// ---------------------------------------------------------------------------
const NET_UDP_OK: i32 = 0;
const NET_UDP_ERR_INVALID_ARG: i32 = -1;
// -2 (NOT_INIT) no se devuelve desde funciones int: open devuelve NULL.
// `#[allow(dead_code)]`: silencia el aviso "never used" en el build de host;
// esta constante solo se usa dentro del bloque #[cfg(target_os = "vita")].
#[allow(dead_code)]
const NET_UDP_ERR_INIT: i32 = -3;
const NET_UDP_ERR_SEND: i32 = -5;
const NET_UDP_ERR_TIMEOUT: i32 = -6;
const NET_UDP_ERR_RECV: i32 = -7;

const NET_UDP_MAX_SOCKETS: usize = 4;

// ---------------------------------------------------------------------------
// FFI hacia la plataforma: Linux (host de tests)
// ---------------------------------------------------------------------------
// `unsafe extern "C"` (edición 2024): declaramos símbolos que el linker
// resolverá contra la libc. El bloque es "unsafe" porque el compilador no
// puede verificar que estas firmas coincidan con la realidad: lo prometemos
// nosotros (si mintiéramos, el comportamiento sería indefinido, como en C).
#[cfg(not(target_os = "vita"))]
mod sys {
    use core::ffi::c_void;

    pub const AF_INET: i32 = 2;
    pub const SOCK_DGRAM: i32 = 2;
    pub const SOL_SOCKET: i32 = 1;
    pub const SO_RCVTIMEO: i32 = 20;
    pub const MSG_DONTWAIT: i32 = 0x40;
    pub const EAGAIN: i32 = 11;

    // struct sockaddr_in de Linux, replicada campo a campo. #[repr(C)]
    // garantiza el mismo layout que ve la libc.
    #[repr(C)]
    pub struct SockaddrIn {
        pub sin_family: u16,
        pub sin_port: u16,   // big-endian
        pub sin_addr: u32,   // big-endian
        pub sin_zero: [u8; 8],
    }

    // struct timeval: tv_sec/tv_usec son `long` en C; `isize` de Rust mide
    // lo mismo que `long` en los Linux de 64 y 32 bits que nos importan.
    #[repr(C)]
    pub struct Timeval {
        pub tv_sec: isize,
        pub tv_usec: isize,
    }

    unsafe extern "C" {
        pub fn socket(domain: i32, ty: i32, protocol: i32) -> i32;
        pub fn connect(fd: i32, addr: *const SockaddrIn, len: u32) -> i32;
        pub fn send(fd: i32, buf: *const c_void, len: usize, flags: i32) -> isize;
        pub fn recv(fd: i32, buf: *mut c_void, len: usize, flags: i32) -> isize;
        pub fn setsockopt(fd: i32, level: i32, name: i32,
                          val: *const c_void, len: u32) -> i32;
        pub fn close(fd: i32) -> i32;
        // errno en Linux es una variable por-hilo; se accede vía esta función.
        pub fn __errno_location() -> *mut i32;
    }

    pub fn errno() -> i32 {
        unsafe { *__errno_location() }
    }
}

// ---------------------------------------------------------------------------
// FFI hacia la plataforma: PS Vita (sceNet). Compila solo con el target
// armv7-sony-vita-newlibeabihf; los símbolos los aportan los stubs de
// VitaSDK al enlazar. VALIDAR EN HARDWARE (igual que el lado C).
// ---------------------------------------------------------------------------
#[cfg(target_os = "vita")]
mod sys {
    use core::ffi::c_void;

    pub const SCE_NET_AF_INET: i32 = 2;
    pub const SCE_NET_SOCK_DGRAM: i32 = 2;
    pub const SCE_NET_SOL_SOCKET: i32 = 0xffff;
    pub const SCE_NET_SO_RCVTIMEO: i32 = 0x1006;
    pub const SCE_NET_MSG_DONTWAIT: i32 = 0x80;
    pub const SCE_NET_ERROR_EAGAIN: u32 = 0x8041_0223;
    pub const SCE_NET_ERROR_EBUSY: u32 = 0x8041_0110;
    pub const SCE_NETCTL_ERROR_ALREADY: u32 = 0x8041_2102;
    pub const SCE_SYSMODULE_NET: u16 = 1;

    #[repr(C)]
    pub struct SceNetSockaddrIn {
        pub sin_len: u8,
        pub sin_family: u8,
        pub sin_port: u16, // big-endian
        pub sin_addr: u32, // big-endian
        pub sin_vport: u16,
        pub sin_zero: [u8; 6],
    }

    #[repr(C)]
    pub struct SceNetInitParam {
        pub memory: *mut c_void,
        pub size: i32,
        pub flags: i32,
    }

    unsafe extern "C" {
        pub fn sceSysmoduleLoadModule(id: u16) -> i32;
        pub fn sceNetInit(param: *const SceNetInitParam) -> i32;
        pub fn sceNetTerm() -> i32;
        pub fn sceNetCtlInit() -> i32;
        pub fn sceNetCtlTerm() -> i32;
        pub fn sceNetSocket(name: *const u8, domain: i32, ty: i32,
                            protocol: i32) -> i32;
        pub fn sceNetSocketClose(fd: i32) -> i32;
        pub fn sceNetConnect(fd: i32, addr: *const SceNetSockaddrIn,
                             len: u32) -> i32;
        pub fn sceNetSend(fd: i32, buf: *const c_void, len: usize,
                          flags: i32) -> i32;
        pub fn sceNetRecv(fd: i32, buf: *mut c_void, len: usize,
                          flags: i32) -> i32;
        pub fn sceNetSetsockopt(fd: i32, level: i32, name: i32,
                                val: *const c_void, len: u32) -> i32;
    }

    // Pool de 1 MiB que exige sceNetInit, en BSS estática (sin malloc).
    // Repr alineado a 4096 con un wrapper, porque los arrays no llevan
    // atributos de alineación directamente.
    #[repr(C, align(4096))]
    pub struct NetPool(pub UnsafeCellWrap);
    pub struct UnsafeCellWrap(pub core::cell::UnsafeCell<[u8; 1024 * 1024]>);
    unsafe impl Sync for NetPool {}
    pub static NET_POOL: NetPool =
        NetPool(UnsafeCellWrap(core::cell::UnsafeCell::new([0; 1024 * 1024])));
}

// ---------------------------------------------------------------------------
// Estado interno del módulo
// ---------------------------------------------------------------------------

// El handle que C ve como `net_udp_socket*`. Misma forma que en impl-c.
// `derive(Clone, Copy)`: permite copiar el struct bit a bit (necesario para
// inicializar el array con [VALOR; N]).
#[repr(C)]
#[derive(Clone, Copy)]
pub struct NetUdpSocket {
    fd: i32,
    in_use: u8,
}

const EMPTY_SOCKET: NetUdpSocket = NetUdpSocket { fd: -1, in_use: 0 };

// Rust prohíbe `static mut` accedido a la ligera (carreras de datos = UB).
// El patrón para estado global mutable controlado es envolverlo en
// `UnsafeCell` (la única vía legal de mutabilidad interior) y declarar
// `unsafe impl Sync`: NUESTRA promesa de que solo se usa desde un hilo,
// como hace la app de la Vita. El lado C hace la misma suposición implícita;
// aquí queda escrita y visible.
struct ModuleState {
    initialized: UnsafeCell<bool>,
    sockets: UnsafeCell<[NetUdpSocket; NET_UDP_MAX_SOCKETS]>,
}
unsafe impl Sync for ModuleState {}

static STATE: ModuleState = ModuleState {
    initialized: UnsafeCell::new(false),
    sockets: UnsafeCell::new([EMPTY_SOCKET; NET_UDP_MAX_SOCKETS]),
};

fn is_initialized() -> bool {
    unsafe { *STATE.initialized.get() }
}

fn set_initialized(v: bool) {
    unsafe { *STATE.initialized.get() = v }
}

// ---------------------------------------------------------------------------
// Parser IPv4 propio — semántica idéntica a impl-c (misma entrada, mismo
// resultado, sin depender de la libc de cada plataforma).
// ---------------------------------------------------------------------------
// Devuelve `Option<u32>`: `Some(addr_be)` o `None` si la cadena es inválida.
// Es el `if (!parse(...)) return NULL;` de C pero el compilador OBLIGA a
// tratar el caso None: no se puede olvidar el error.
fn parse_ipv4(ip: *const u8) -> Option<u32> {
    let mut addr: u32 = 0;
    let mut p = ip;

    // SAFETY: el contrato del header exige que `ip` sea una cadena C
    // terminada en NUL; la recorremos byte a byte sin pasarnos del NUL.
    unsafe {
        for octet_idx in 0..4 {
            if !(*p).is_ascii_digit() {
                return None;
            }
            let mut value: u32 = 0;
            let mut digits = 0;
            while (*p).is_ascii_digit() {
                value = value * 10 + u32::from(*p - b'0');
                digits += 1;
                if digits > 3 || value > 255 {
                    return None;
                }
                p = p.add(1);
            }
            addr = (addr << 8) | value;
            if octet_idx < 3 {
                if *p != b'.' {
                    return None;
                }
                p = p.add(1);
            }
        }
        if *p != 0 {
            return None; // basura tras el último octeto
        }
    }
    // `swap_bytes` + to_be sería redundante: serializamos explícito como en C.
    Some(
        ((addr & 0x0000_00FF) << 24)
            | ((addr & 0x0000_FF00) << 8)
            | ((addr & 0x00FF_0000) >> 8)
            | ((addr & 0xFF00_0000) >> 24),
    )
}

fn port_to_be(port: u16) -> u16 {
    port.rotate_left(8) // intercambia los dos bytes (swap de 16 bits)
}

// ---------------------------------------------------------------------------
// API pública con ABI C
// ---------------------------------------------------------------------------

#[unsafe(no_mangle)]
pub extern "C" fn net_udp_init() -> i32 {
    if is_initialized() {
        return NET_UDP_OK;
    }

    #[cfg(target_os = "vita")]
    unsafe {
        sys::sceSysmoduleLoadModule(sys::SCE_SYSMODULE_NET);
        let param = sys::SceNetInitParam {
            memory: sys::NET_POOL.0 .0.get() as *mut c_void,
            size: (1024 * 1024) as i32,
            flags: 0,
        };
        let rc = sys::sceNetInit(&param);
        if rc < 0 && rc as u32 != sys::SCE_NET_ERROR_EBUSY {
            return NET_UDP_ERR_INIT;
        }
        let rc = sys::sceNetCtlInit();
        if rc < 0 && rc as u32 != sys::SCE_NETCTL_ERROR_ALREADY {
            return NET_UDP_ERR_INIT;
        }
    }

    unsafe {
        *STATE.sockets.get() = [EMPTY_SOCKET; NET_UDP_MAX_SOCKETS];
    }
    set_initialized(true);
    NET_UDP_OK
}

#[unsafe(no_mangle)]
pub extern "C" fn net_udp_shutdown() {
    if !is_initialized() {
        return;
    }
    unsafe {
        let sockets = &mut *STATE.sockets.get();
        // `iter_mut()` recorre el array prestando referencias mutables a
        // cada elemento; el `for` de Rust consume ese iterador.
        for s in sockets.iter_mut() {
            if s.in_use != 0 {
                net_udp_close(s as *mut NetUdpSocket);
            }
        }
        #[cfg(target_os = "vita")]
        {
            sys::sceNetCtlTerm();
            sys::sceNetTerm();
        }
    }
    set_initialized(false);
}

#[unsafe(no_mangle)]
pub extern "C" fn net_udp_open(ip: *const u8, port: u16) -> *mut NetUdpSocket {
    if !is_initialized() || ip.is_null() || port == 0 {
        return ptr::null_mut();
    }
    // `let ... else`: si parse_ipv4 devuelve None, salimos por la rama else.
    // Es el patrón de Rust para "desempaquetar o abortar la función".
    let Some(addr_be) = parse_ipv4(ip) else {
        return ptr::null_mut();
    };

    unsafe {
        let sockets = &mut *STATE.sockets.get();
        // Buscar hueco libre: `.iter_mut().find(...)` devuelve Option<&mut _>.
        let Some(slot) = sockets.iter_mut().find(|s| s.in_use == 0) else {
            return ptr::null_mut(); // tabla agotada
        };

        #[cfg(not(target_os = "vita"))]
        let fd = {
            let fd = sys::socket(sys::AF_INET, sys::SOCK_DGRAM, 0);
            if fd < 0 {
                return ptr::null_mut();
            }
            let sin = sys::SockaddrIn {
                sin_family: sys::AF_INET as u16,
                sin_port: port_to_be(port),
                sin_addr: addr_be,
                sin_zero: [0; 8],
            };
            if sys::connect(fd, &sin, core::mem::size_of::<sys::SockaddrIn>() as u32) < 0 {
                sys::close(fd);
                return ptr::null_mut();
            }
            fd
        };

        #[cfg(target_os = "vita")]
        let fd = {
            let fd = sys::sceNetSocket(
                c"net_udp".as_ptr() as *const u8, // c"..." = literal de cadena C (con NUL)
                sys::SCE_NET_AF_INET,
                sys::SCE_NET_SOCK_DGRAM,
                0,
            );
            if fd < 0 {
                return ptr::null_mut();
            }
            let sin = sys::SceNetSockaddrIn {
                sin_len: core::mem::size_of::<sys::SceNetSockaddrIn>() as u8,
                sin_family: sys::SCE_NET_AF_INET as u8,
                sin_port: port_to_be(port),
                sin_addr: addr_be,
                sin_vport: 0,
                sin_zero: [0; 6],
            };
            if sys::sceNetConnect(fd, &sin,
                core::mem::size_of::<sys::SceNetSockaddrIn>() as u32) < 0 {
                sys::sceNetSocketClose(fd);
                return ptr::null_mut();
            }
            fd
        };

        slot.fd = fd;
        slot.in_use = 1;
        slot as *mut NetUdpSocket
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn net_udp_close(sock: *mut NetUdpSocket) {
    if sock.is_null() {
        return;
    }
    unsafe {
        if (*sock).in_use == 0 {
            return;
        }
        #[cfg(not(target_os = "vita"))]
        sys::close((*sock).fd);
        #[cfg(target_os = "vita")]
        sys::sceNetSocketClose((*sock).fd);

        (*sock).fd = -1;
        (*sock).in_use = 0;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn net_udp_send(sock: *mut NetUdpSocket, buf: *const u8,
                               len: usize) -> i32 {
    unsafe {
        if sock.is_null() || (*sock).in_use == 0 || buf.is_null() || len == 0 {
            return NET_UDP_ERR_INVALID_ARG;
        }

        #[cfg(not(target_os = "vita"))]
        {
            let sent = sys::send((*sock).fd, buf as *const c_void, len, 0);
            if sent < 0 {
                return NET_UDP_ERR_SEND;
            }
            sent as i32
        }
        #[cfg(target_os = "vita")]
        {
            let sent = sys::sceNetSend((*sock).fd, buf as *const c_void, len, 0);
            if sent < 0 {
                return NET_UDP_ERR_SEND;
            }
            sent
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn net_udp_recv(sock: *mut NetUdpSocket, buf: *mut u8,
                               cap: usize, timeout_ms: i32) -> i32 {
    unsafe {
        if sock.is_null() || (*sock).in_use == 0 || buf.is_null() || cap == 0
            || timeout_ms < 0
        {
            return NET_UDP_ERR_INVALID_ARG;
        }

        #[cfg(not(target_os = "vita"))]
        {
            let mut flags = 0;
            if timeout_ms == 0 {
                flags = sys::MSG_DONTWAIT;
            } else {
                let tv = sys::Timeval {
                    tv_sec: (timeout_ms / 1000) as isize,
                    tv_usec: ((timeout_ms % 1000) * 1000) as isize,
                };
                if sys::setsockopt((*sock).fd, sys::SOL_SOCKET, sys::SO_RCVTIMEO,
                    &tv as *const _ as *const c_void,
                    core::mem::size_of::<sys::Timeval>() as u32) < 0 {
                    return NET_UDP_ERR_RECV;
                }
            }
            let got = sys::recv((*sock).fd, buf as *mut c_void, cap, flags);
            if got < 0 {
                if sys::errno() == sys::EAGAIN {
                    return NET_UDP_ERR_TIMEOUT;
                }
                return NET_UDP_ERR_RECV;
            }
            got as i32
        }
        #[cfg(target_os = "vita")]
        {
            let mut flags = 0;
            if timeout_ms == 0 {
                flags = sys::SCE_NET_MSG_DONTWAIT;
            } else {
                let usec: i32 = timeout_ms * 1000;
                if sys::sceNetSetsockopt((*sock).fd, sys::SCE_NET_SOL_SOCKET,
                    sys::SCE_NET_SO_RCVTIMEO,
                    &usec as *const _ as *const c_void,
                    core::mem::size_of::<i32>() as u32) < 0 {
                    return NET_UDP_ERR_RECV;
                }
            }
            let got = sys::sceNetRecv((*sock).fd, buf as *mut c_void, cap, flags);
            if got < 0 {
                if got as u32 == sys::SCE_NET_ERROR_EAGAIN {
                    return NET_UDP_ERR_TIMEOUT;
                }
                return NET_UDP_ERR_RECV;
            }
            got
        }
    }
}

// ---------------------------------------------------------------------------
// panic_handler + stub de unwinding (solo build standalone; ver mem-pool)
// ---------------------------------------------------------------------------
#[cfg(feature = "standalone")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(feature = "standalone")]
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}
