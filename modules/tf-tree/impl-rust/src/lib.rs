//! tf-tree — implementación Rust del contrato `include/tf_tree.h`.
//!
//! Novedades de Rust: usar funciones de OTRO crate nuestro (`use viz_math_rust::…`),
//! `CStr` para leer strings de C en `no_std`, y `Option<usize>` como "índice o nada".
#![no_std]

use core::ffi::{CStr, c_char, c_void};
use core::ptr;

// `use crate_externo::{...}`: traemos tipos y funciones del crate de matemática
// y de los mensajes. Sus funciones `extern "C"` también se pueden llamar desde
// Rust como funciones normales (pasándoles punteros crudos).
use msg_cdr_rust::{TfMessage, Transform};
use viz_math_rust::{
    Mat4, Quat, Vec3, vizm_mat4_from_trs, vizm_mat4_identity, vizm_mat4_inverse_rigid,
    vizm_mat4_mul, vizm_quat_normalize,
};

const MAX_FRAMES: usize = 32;
const NAME_MAX: usize = 64;
const ALIGN: usize = 8;

const OK: i32 = 0;
const ERR_INVALID_ARG: i32 = -1;
const ERR_FULL: i32 = -2;
const ERR_CYCLE: i32 = -3;
const ERR_UNKNOWN_FRAME: i32 = -4;
const ERR_NO_PATH: i32 = -5;

/// Una entrada de la tabla (96 bytes, igual que `frame_t` de impl-c).
#[repr(C)]
#[derive(Clone, Copy)]
struct Frame {
    name: [u8; NAME_MAX],
    parent: i8, // -1 = sin padre
    used: u8,
    pad: [u8; 2],
    t: [f32; 3],
    q: [f32; 4],
}

#[repr(C)]
pub struct TfTree {
    count: u32,
    rejected: u32,
    frames: [Frame; MAX_FRAMES],
}

const _: () = assert!(core::mem::size_of::<Frame>() == 96);
const _: () = assert!(core::mem::size_of::<TfTree>() == 8 + 32 * 96);

const NO_PARENT: i8 = -1;

/// Quita una barra inicial; `None` si el nombre queda vacío o mide 64+.
/// `Option<&[u8]>`: "un slice de bytes o nada".
fn norm(s: &[u8]) -> Option<&[u8]> {
    let s = if !s.is_empty() && s[0] == b'/' { &s[1..] } else { s };
    if s.is_empty() || s.len() >= NAME_MAX { None } else { Some(s) }
}

/// Bytes de un `*const c_char` (hasta el NUL). `None` si el puntero es nulo.
/// `CStr::from_ptr` es el `strlen` + vista segura de Rust, disponible en `core`.
unsafe fn cstr<'a>(p: *const c_char) -> Option<&'a [u8]> {
    if p.is_null() {
        None
    } else {
        Some(unsafe { CStr::from_ptr(p) }.to_bytes())
    }
}

/// Bytes de un nombre almacenado en `[u8; 64]` (hasta el primer 0).
fn arr_bytes(a: &[u8; NAME_MAX]) -> &[u8] {
    let n = a.iter().position(|&b| b == 0).unwrap_or(NAME_MAX);
    &a[..n]
}

fn find(tr: &TfTree, name: &[u8]) -> Option<usize> {
    for i in 0..MAX_FRAMES {
        if tr.frames[i].used != 0 && arr_bytes(&tr.frames[i].name) == name {
            return Some(i);
        }
    }
    None
}

fn add(tr: &mut TfTree, name: &[u8]) -> Option<usize> {
    for i in 0..MAX_FRAMES {
        if tr.frames[i].used == 0 {
            let mut f: Frame = unsafe { core::mem::zeroed() };
            f.name[..name.len()].copy_from_slice(name);
            f.used = 1;
            f.parent = NO_PARENT;
            f.q[3] = 1.0;
            tr.frames[i] = f;
            tr.count += 1;
            return Some(i);
        }
    }
    None
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_required_size() -> usize {
    core::mem::size_of::<TfTree>()
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_create(backing: *mut c_void, backing_len: usize) -> *mut TfTree {
    if backing.is_null() || (backing as usize) & (ALIGN - 1) != 0
        || backing_len < core::mem::size_of::<TfTree>()
    {
        return ptr::null_mut();
    }
    let tr = backing as *mut TfTree;
    tf_tree_clear(tr);
    tr
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_clear(tree: *mut TfTree) {
    if !tree.is_null() {
        unsafe { ptr::write_bytes(tree, 0, 1) }
    }
}

/// Núcleo de `update` sobre bytes (lo comparten la API C y `apply_message`).
fn update_bytes(tr: &mut TfTree, parent: &[u8], child: &[u8], t: Vec3, q: Quat) -> i32 {
    let (p, c) = match (norm(parent), norm(child)) {
        (Some(p), Some(c)) => (p, c),
        _ => return ERR_INVALID_ARG,
    };
    if p == c {
        return ERR_CYCLE;
    }
    let pi = find(tr, p);
    let ci = find(tr, c);

    // Ciclo: solo si ambos existen y el hijo es ancestro del padre.
    // `if let (Some(a), Some(b)) = (x, y)`: entra solo si AMBOS tienen valor.
    if let (Some(pi), Some(ci)) = (pi, ci) {
        let mut node = pi as i32;
        let mut hops = 0;
        while node != NO_PARENT as i32 && hops <= MAX_FRAMES {
            if node == ci as i32 {
                return ERR_CYCLE;
            }
            node = tr.frames[node as usize].parent as i32;
            hops += 1;
        }
    }
    let missing = pi.is_none() as u32 + ci.is_none() as u32;
    if tr.count + missing > MAX_FRAMES as u32 {
        return ERR_FULL;
    }
    // `match` con valor por defecto: usa el índice existente o añade el frame.
    let pi = match pi {
        Some(i) => i,
        None => add(tr, p).unwrap_or(0),
    };
    let ci = match ci {
        Some(i) => i,
        None => add(tr, c).unwrap_or(0),
    };
    let mut qn = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };
    vizm_quat_normalize(&mut qn, &q);
    let f = &mut tr.frames[ci];
    f.parent = pi as i8;
    f.t = [t.x, t.y, t.z];
    f.q = [qn.x, qn.y, qn.z, qn.w];
    OK
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_update(
    tree: *mut TfTree,
    parent: *const c_char,
    child: *const c_char,
    t: *const Vec3,
    q: *const Quat,
) -> i32 {
    if tree.is_null() || t.is_null() || q.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let (p, c) = match (cstr(parent), cstr(child)) {
            (Some(p), Some(c)) => (p, c),
            _ => return ERR_INVALID_ARG,
        };
        update_bytes(&mut *tree, p, c, *t, *q)
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_apply_message(tree: *mut TfTree, msg: *const TfMessage) -> i32 {
    if tree.is_null() || msg.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let (tr, msg) = (&mut *tree, &*msg);
        let mut applied = 0;
        // `.min(...)` limita el recorrido al tope; `&msg.items[i]` presta cada transform.
        for i in 0..(msg.count as usize).min(msg.items.len()) {
            let m: &Transform = &msg.items[i];
            let t = Vec3 {
                x: m.translation[0] as f32,
                y: m.translation[1] as f32,
                z: m.translation[2] as f32,
            };
            let q = Quat {
                x: m.rotation[0] as f32,
                y: m.rotation[1] as f32,
                z: m.rotation[2] as f32,
                w: m.rotation[3] as f32,
            };
            if update_bytes(tr, arr_bytes(&m.frame_id), arr_bytes(&m.child_frame_id), t, q) == OK {
                applied += 1;
            } else {
                tr.rejected += 1;
            }
        }
        applied
    }
}

/// M_root<-frame y el índice de la raíz alcanzada.
fn to_root(tr: &TfTree, idx: usize) -> (Mat4, usize) {
    let mut m = Mat4 { m: [0.0; 16] };
    vizm_mat4_identity(&mut m);
    let mut node = idx;
    for _ in 0..=MAX_FRAMES {
        let f = &tr.frames[node];
        if f.parent == NO_PARENT {
            break;
        }
        let t = Vec3 { x: f.t[0], y: f.t[1], z: f.t[2] };
        let q = Quat { x: f.q[0], y: f.q[1], z: f.q[2], w: f.q[3] };
        let mut local = Mat4 { m: [0.0; 16] };
        vizm_mat4_from_trs(&mut local, &t, &q);
        let cur: *const Mat4 = &m;
        vizm_mat4_mul(&mut m, &local, cur); // M = L(node) · M  (alias permitido)
        node = f.parent as usize;
    }
    (m, node)
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_lookup(
    tree: *const TfTree,
    target: *const c_char,
    source: *const c_char,
    out: *mut Mat4,
) -> i32 {
    if tree.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let tr = &*tree;
        let (tn, sn) = match (cstr(target).and_then(norm), cstr(source).and_then(norm)) {
            (Some(t), Some(s)) => (t, s),
            _ => return ERR_INVALID_ARG,
        };
        let (ti, si) = match (find(tr, tn), find(tr, sn)) {
            (Some(t), Some(s)) => (t, s),
            _ => return ERR_UNKNOWN_FRAME,
        };
        if ti == si {
            vizm_mat4_identity(out);
            return OK;
        }
        let (mt, rt) = to_root(tr, ti);
        let (ms, rs) = to_root(tr, si);
        if rt != rs {
            return ERR_NO_PATH;
        }
        let mut inv = Mat4 { m: [0.0; 16] };
        vizm_mat4_inverse_rigid(&mut inv, &mt);
        vizm_mat4_mul(out, &inv, &ms);
        OK
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_frame_count(tree: *const TfTree) -> usize {
    if tree.is_null() { 0 } else { unsafe { (*tree).count as usize } }
}

#[unsafe(no_mangle)]
pub extern "C" fn tf_tree_rejected(tree: *const TfTree) -> u32 {
    if tree.is_null() { 0 } else { unsafe { (*tree).rejected } }
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
