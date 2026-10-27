//! msg-ring — implementación Rust del contrato `include/msg_ring.h`.
//!
//! Cola circular SPSC sin bloqueos. Comentada en detalle (proyecto de
//! aprendizaje de Rust); lo nuevo respecto a mem-pool: ATÓMICOS y ÓRDENES
//! DE MEMORIA (ver `docs/rust/03-atomicos-y-hilos.md`).
#![no_std]

use core::ffi::c_void;
use core::ptr;
// `AtomicU32`: un u32 que se puede leer/escribir desde varios hilos sin
// carreras de datos. `Ordering` dice cuánta sincronización exige cada
// operación (equivale a `memory_order_*` de C11).
use core::sync::atomic::{AtomicU32, Ordering};

const RING_HEADER_BYTES: usize = 64;
const RING_ALIGN: usize = 8;
const RING_MAX_SLOTS: usize = 1 << 30;

const MSG_RING_OK: i32 = 0;
const MSG_RING_ERR_INVALID_ARG: i32 = -1;
const MSG_RING_ERR_FULL: i32 = -2;
const MSG_RING_ERR_EMPTY: i32 = -3;
const MSG_RING_ERR_TOO_BIG: i32 = -4;
const MSG_RING_ERR_BUF_SMALL: i32 = -5;

/// Cabecera (mismo orden de campos que `struct msg_ring` de impl-c).
/// `#[repr(C)]` fija el orden; `AtomicU32` tiene el mismo layout que u32.
#[repr(C)]
pub struct MsgRing {
    slot_size: u32,
    slot_count: u32,
    stride: u32,
    head: AtomicU32,    // lo avanza el consumidor
    tail: AtomicU32,    // lo avanza el productor
    dropped: AtomicU32, // descartes por cola llena
}

const _: () = assert!(core::mem::size_of::<MsgRing>() <= RING_HEADER_BYTES);

/// Bytes por ranura: 4 de longitud + payload, redondeado a 8. 0 si desborda.
fn stride_for(slot_size: usize) -> usize {
    if slot_size > (u32::MAX as usize) - 4 - (RING_ALIGN - 1) {
        return 0;
    }
    (4 + slot_size + (RING_ALIGN - 1)) & !(RING_ALIGN - 1)
}

/// Puntero al inicio de la ranura `index` (envuelto con la máscara).
///
/// # Safety
/// `ring` debe apuntar a una cola creada por `msg_ring_create`.
unsafe fn slot_ptr(ring: *const MsgRing, index: u32) -> *mut u8 {
    unsafe {
        let base = (ring as *mut u8).add(RING_HEADER_BYTES);
        let slot = (index & ((*ring).slot_count - 1)) as usize;
        base.add(slot * (*ring).stride as usize)
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_required_size(slot_size: usize, slot_count: usize) -> usize {
    // `is_power_of_two()` es un método de los enteros sin signo (0 → false).
    if slot_size == 0 || slot_count == 0 || slot_count > RING_MAX_SLOTS
        || !slot_count.is_power_of_two()
    {
        return 0;
    }
    let stride = stride_for(slot_size);
    if stride == 0 {
        return 0;
    }
    match stride
        .checked_mul(slot_count)
        .and_then(|b| b.checked_add(RING_HEADER_BYTES))
    {
        Some(total) => total,
        None => 0,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_create(
    backing: *mut c_void,
    backing_len: usize,
    slot_size: usize,
    slot_count: usize,
) -> *mut MsgRing {
    if backing.is_null() || (backing as usize) & (RING_ALIGN - 1) != 0 {
        return ptr::null_mut();
    }
    let required = msg_ring_required_size(slot_size, slot_count);
    if required == 0 || backing_len < required {
        return ptr::null_mut();
    }
    let ring = backing as *mut MsgRing;
    unsafe {
        // `ptr::write` inicializa memoria SIN leer ni "soltar" el valor
        // anterior (el buffer del llamador contiene basura: asignar con `=`
        // intentaría destruir esa basura). `AtomicU32::new` construye el átomo.
        ptr::write(
            ring,
            MsgRing {
                slot_size: slot_size as u32,
                slot_count: slot_count as u32,
                stride: stride_for(slot_size) as u32,
                head: AtomicU32::new(0),
                tail: AtomicU32::new(0),
                dropped: AtomicU32::new(0),
            },
        );
    }
    ring
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_push(ring: *mut MsgRing, data: *const c_void, len: usize) -> i32 {
    if ring.is_null() || (data.is_null() && len > 0) {
        return MSG_RING_ERR_INVALID_ARG;
    }
    unsafe {
        // `&*ring` convierte el puntero crudo en una referencia compartida
        // `&MsgRing`: los métodos de los átomos toman `&self` (no `&mut`),
        // por eso pueden usarse desde dos hilos a la vez.
        let r = &*ring;
        if len > r.slot_size as usize {
            return MSG_RING_ERR_TOO_BIG;
        }
        // Solo el productor escribe `tail` → Relaxed basta. `head` lo escribe
        // el consumidor → Acquire: vemos que la ranura ya fue liberada.
        let tail = r.tail.load(Ordering::Relaxed);
        let head = r.head.load(Ordering::Acquire);
        // `wrapping_sub`: resta que da la vuelta en vez de entrar en pánico
        // (los contadores u32 crecen sin parar y desbordan a propósito).
        if tail.wrapping_sub(head) >= r.slot_count {
            r.dropped.fetch_add(1, Ordering::Relaxed);
            return MSG_RING_ERR_FULL;
        }
        let slot = slot_ptr(ring, tail);
        // `write_unaligned` escribe sin exigir alineación del puntero.
        (slot as *mut u32).write_unaligned(len as u32);
        if len > 0 {
            // equivalente a memcpy(dst, src, n)
            ptr::copy_nonoverlapping(data as *const u8, slot.add(4), len);
        }
        // Release: el contenido de la ranura queda visible ANTES que `tail`.
        r.tail.store(tail.wrapping_add(1), Ordering::Release);
    }
    MSG_RING_OK
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_pop(
    ring: *mut MsgRing,
    out: *mut c_void,
    out_cap: usize,
    out_len: *mut usize,
) -> i32 {
    if ring.is_null() || out_len.is_null() || (out.is_null() && out_cap > 0) {
        return MSG_RING_ERR_INVALID_ARG;
    }
    unsafe {
        let r = &*ring;
        let head = r.head.load(Ordering::Relaxed);
        let tail = r.tail.load(Ordering::Acquire);
        if head == tail {
            return MSG_RING_ERR_EMPTY;
        }
        let slot = slot_ptr(ring, head);
        let len = (slot as *const u32).read_unaligned() as usize;
        *out_len = len;
        if len > out_cap {
            return MSG_RING_ERR_BUF_SMALL; // no se consume
        }
        if len > 0 {
            ptr::copy_nonoverlapping(slot.add(4) as *const u8, out as *mut u8, len);
        }
        r.head.store(head.wrapping_add(1), Ordering::Release);
    }
    MSG_RING_OK
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_count(ring: *const MsgRing) -> usize {
    if ring.is_null() {
        return 0;
    }
    unsafe {
        let r = &*ring;
        let head = r.head.load(Ordering::Acquire);
        let tail = r.tail.load(Ordering::Acquire);
        tail.wrapping_sub(head) as usize
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_dropped(ring: *const MsgRing) -> u32 {
    if ring.is_null() {
        return 0;
    }
    unsafe { (*ring).dropped.load(Ordering::Relaxed) }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_capacity(ring: *const MsgRing) -> usize {
    if ring.is_null() {
        return 0;
    }
    unsafe { (*ring).slot_count as usize }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_ring_slot_size(ring: *const MsgRing) -> usize {
    if ring.is_null() {
        return 0;
    }
    unsafe { (*ring).slot_size as usize }
}

// panic_handler y stub de unwinding: solo en compilación standalone
// (explicación completa en modules/mem-pool/impl-rust/src/lib.rs).
#[cfg(feature = "standalone")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {}
}

#[cfg(feature = "standalone")]
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}
