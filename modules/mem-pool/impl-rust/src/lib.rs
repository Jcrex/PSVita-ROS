//! mem-pool — implementación Rust del contrato `include/mem_pool.h`.
//!
//! Este archivo está comentado en detalle porque el proyecto es también un
//! vehículo de aprendizaje de Rust. Cada construcción nueva del lenguaje se
//! explica la primera vez que aparece. Ver además `docs/rust/`.

// `#![no_std]` (atributo de crate, por eso el `!`): renuncia a la biblioteca
// estándar `std` (que asume un sistema operativo "completo": hilos, ficheros,
// heap...). Solo queda `core`: la parte de Rust que funciona en cualquier
// sitio, incluso en una consola con newlib. Es la opción segura para código
// que debe enlazarse dentro de un binario C de la Vita.
#![no_std]

// `use` importa nombres a este ámbito, como #include pero por símbolo.
use core::ffi::c_void; // c_void = el `void` de C para punteros opacos.
use core::ptr;         // utilidades de punteros crudos (null_mut, etc.)

// ---------------------------------------------------------------------------
// Constantes del contrato (deben coincidir EXACTAMENTE con impl-c/mem_pool.c)
// ---------------------------------------------------------------------------

// `const` en Rust: constante evaluada en compilación, con tipo explícito.
// `usize` es el equivalente de `size_t` en C: entero del tamaño de un puntero.
const POOL_HEADER_BYTES: usize = 64;
const POOL_ALIGN: usize = 8;

// Códigos de estado del header (mem_pool_status). En el lado C es un enum;
// aquí los exponemos como i32 (el `int` de C) para que el ABI sea idéntico.
const MEM_POOL_OK: i32 = 0;
const MEM_POOL_ERR_INVALID_ARG: i32 = -1;
const MEM_POOL_ERR_BAD_PTR: i32 = -2;

// ---------------------------------------------------------------------------
// La estructura de control
// ---------------------------------------------------------------------------

// `#[repr(C)]` ordena los campos en memoria exactamente como lo haría un
// compilador de C. Sin él, Rust puede reordenar campos para optimizar.
// Imprescindible en cualquier struct que cruce la frontera C <-> Rust.
// `pub` porque aparece en firmas de funciones públicas (el compilador avisa
// si un tipo es "más privado" que la función que lo expone). Para C sigue
// siendo un puntero opaco: nunca ve los campos.
#[repr(C)]
pub struct MemPool {
    blocks_start: *mut u8, // `*mut u8` = puntero crudo a bytes (uint8_t* de C).
    eff_block_size: usize, // tamaño de bloque redondeado a POOL_ALIGN
    block_count: usize,
    blocks_free: usize,
    free_head: *mut u8,    // cabeza de la free-list intrusiva (NULL = vacía)
}

// Aserción en compilación: si la cabecera de control no cupiera en los 64
// bytes reservados, esto no compila. `core::mem::size_of` es sizeof().
const _: () = assert!(core::mem::size_of::<MemPool>() <= POOL_HEADER_BYTES);

// ---------------------------------------------------------------------------
// Helpers internos (funciones privadas normales de Rust, sin ABI C)
// ---------------------------------------------------------------------------

fn round_up_align(n: usize) -> usize {
    // En Rust no hay conversión implícita de enteros; las máscaras se
    // escriben igual que en C pero el compilador exige tipos exactos.
    (n + (POOL_ALIGN - 1)) & !(POOL_ALIGN - 1)
}

fn effective_block_size(block_size: usize) -> usize {
    // Si el redondeo a 8 desbordara usize, devolvemos 0 (= inválido), en
    // paridad exacta con impl-c. Ojo: en Rust un overflow aritmético en
    // modo debug PANICA (en C simplemente "da la vuelta"), por eso el guard
    // va antes de la suma.
    if block_size > usize::MAX - (POOL_ALIGN - 1) {
        return 0;
    }
    // `if` es una EXPRESIÓN en Rust: devuelve un valor. No existe `?:` de C.
    let eff = if block_size < POOL_ALIGN { POOL_ALIGN } else { block_size };
    round_up_align(eff)
}

// ---------------------------------------------------------------------------
// API pública con ABI C
// ---------------------------------------------------------------------------
// Anatomía de cada función exportada:
//  - `#[unsafe(no_mangle)]`: conserva el nombre del símbolo tal cual (sin
//    esto, Rust "mangla" los nombres como C++). Desde la edición 2024 se
//    escribe dentro de `unsafe(...)` porque prometemos al compilador que el
//    nombre no colisiona con otro símbolo.
//  - `extern "C"`: usa la convención de llamada de C (cómo se pasan los
//    argumentos en registros/pila), para que el código C pueda llamarla.

#[unsafe(no_mangle)]
pub extern "C" fn mem_pool_required_size(block_size: usize, block_count: usize) -> usize {
    if block_size == 0 || block_count == 0 {
        return 0;
    }
    let eff = effective_block_size(block_size);
    if eff == 0 {
        return 0;
    }
    // `checked_mul` / `checked_add` devuelven `Option<usize>`: `Some(valor)`
    // si la operación cupo, `None` si desbordó. Es la alternativa idiomática
    // de Rust al chequeo manual `count > (SIZE_MAX - 64) / eff` del lado C.
    match eff
        .checked_mul(block_count)
        .and_then(|blocks| blocks.checked_add(POOL_HEADER_BYTES))
    {
        Some(total) => total,
        None => 0, // desbordaría size_t: mismo contrato que impl-c
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn mem_pool_create(
    backing: *mut c_void,
    backing_len: usize,
    block_size: usize,
    block_count: usize,
) -> *mut MemPool {
    if backing.is_null() || block_size == 0 || block_count == 0 {
        // `ptr::null_mut()` es el NULL tipado de Rust para punteros crudos.
        return ptr::null_mut();
    }
    // `as usize` convierte el puntero a entero para comprobar la alineación.
    if (backing as usize) & (POOL_ALIGN - 1) != 0 {
        return ptr::null_mut();
    }
    let required = mem_pool_required_size(block_size, block_count);
    if required == 0 || backing_len < required {
        return ptr::null_mut();
    }

    let pool = backing as *mut MemPool;
    let eff = effective_block_size(block_size);

    // Bloque `unsafe`: aquí hacemos cosas que el compilador no puede
    // verificar (escribir a través de punteros crudos). Es la frontera
    // explícita donde Rust deja de garantizar la seguridad de memoria y
    // pasamos a responder nosotros, igual que en C — pero acotado y visible.
    unsafe {
        // `(*pool).campo = valor` es el equivalente de `pool->campo = valor`.
        let blocks_start = (backing as *mut u8).add(POOL_HEADER_BYTES);
        (*pool).blocks_start = blocks_start;
        (*pool).eff_block_size = eff;
        (*pool).block_count = block_count;
        (*pool).blocks_free = block_count;

        // Encadenar la free-list en orden de dirección (paridad con impl-c).
        // `(0..block_count).rev()` es un rango iterado al revés:
        // block_count-1, ..., 1, 0 — el `for` de Rust trabaja con iteradores.
        (*pool).free_head = ptr::null_mut();
        for i in (0..block_count).rev() {
            let blk = blocks_start.add(i * eff);
            // Guardar el puntero "siguiente" en los primeros bytes del bloque:
            // reinterpretamos el bloque como *mut *mut u8 (puntero a puntero).
            *(blk as *mut *mut u8) = (*pool).free_head;
            (*pool).free_head = blk;
        }
    }
    pool
}

#[unsafe(no_mangle)]
pub extern "C" fn mem_pool_alloc(pool: *mut MemPool) -> *mut c_void {
    if pool.is_null() {
        return ptr::null_mut();
    }
    unsafe {
        let head = (*pool).free_head;
        if head.is_null() {
            return ptr::null_mut(); // pool agotado
        }
        (*pool).free_head = *(head as *mut *mut u8);
        (*pool).blocks_free -= 1;
        head as *mut c_void
    } // sin `return` ni `;`: la última expresión del bloque es el valor devuelto
}

#[unsafe(no_mangle)]
pub extern "C" fn mem_pool_free(pool: *mut MemPool, block: *mut c_void) -> i32 {
    if pool.is_null() || block.is_null() {
        return MEM_POOL_ERR_INVALID_ARG;
    }
    let blk = block as *mut u8;
    unsafe {
        let start = (*pool).blocks_start;
        let end = start.add((*pool).block_count * (*pool).eff_block_size);
        // Comparar punteros: en Rust se comparan como en C si son del mismo tipo.
        if blk < start || blk >= end {
            return MEM_POOL_ERR_BAD_PTR;
        }
        // `offset_from` da la distancia en elementos (bytes para *mut u8).
        let offset = blk.offset_from(start) as usize;
        if offset % (*pool).eff_block_size != 0 {
            return MEM_POOL_ERR_BAD_PTR;
        }
        // Detección de doble free recorriendo la free-list (paridad con impl-c).
        // `while !cur.is_null()` sustituye al `for(cur=...; cur; cur=next)` de C.
        let mut cur = (*pool).free_head;
        while !cur.is_null() {
            if cur == blk {
                return MEM_POOL_ERR_BAD_PTR;
            }
            cur = *(cur as *mut *mut u8);
        }

        *(blk as *mut *mut u8) = (*pool).free_head;
        (*pool).free_head = blk;
        (*pool).blocks_free += 1;
    }
    MEM_POOL_OK
}

#[unsafe(no_mangle)]
pub extern "C" fn mem_pool_blocks_free(pool: *const MemPool) -> usize {
    // `*const` = puntero de solo lectura (el `const T*` de C).
    if pool.is_null() {
        return 0;
    }
    unsafe { (*pool).blocks_free }
}

#[unsafe(no_mangle)]
pub extern "C" fn mem_pool_block_size(pool: *const MemPool) -> usize {
    if pool.is_null() {
        return 0;
    }
    unsafe { (*pool).eff_block_size }
}

// ---------------------------------------------------------------------------
// panic_handler (solo en compilación standalone)
// ---------------------------------------------------------------------------
// Todo programa no_std necesita exactamente UN manejador de pánico: la
// función a la que salta Rust si algo imposible ocurre (índice fuera de
// rango, overflow en debug...). `-> !` significa "no retorna jamás".
// `#[cfg(feature = ...)]` = compilación condicional, el #ifdef de Rust.
#[cfg(feature = "standalone")]
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo) -> ! {
    loop {} // en embebido sin consola: quedarse parado es lo más seguro
}

// Stub del "personality routine" de unwinding. Aunque compilamos con
// panic = "abort", la biblioteca `core` precompilada que distribuye rustup
// fue construida con soporte de unwinding y deja una referencia débil a
// este símbolo; sin el stub, el linker de C falla con
// "undefined reference to rust_eh_personality". Nunca se ejecuta.
#[cfg(feature = "standalone")]
#[unsafe(no_mangle)]
extern "C" fn rust_eh_personality() {}
