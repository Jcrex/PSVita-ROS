//! msg-schema — implementación Rust del contrato `include/msg_schema.h`.
//!
//! Codec CDR genérico guiado por un esquema (el equivalente en la Vita de
//! `ros_babel_fish`). Novedades de Rust respecto a los módulos anteriores
//! (explicadas al usarse): punteros a función de C como campos de un struct
//! (`Option<unsafe extern "C" fn(...)>`), recursión con `Result` y `?`, y
//! `checked_mul` para evitar desbordes. Ver `docs/rust/05-callbacks-y-recursion.md`.
#![no_std]

use core::ffi::{c_char, c_void};
use core::ptr;

// Códigos de estado (iguales que `msg_schema_status`)
const OK: i32 = 0;
const ERR_INVALID_ARG: i32 = -1;
const ERR_BAD_SCHEMA: i32 = -2;
const ERR_UNKNOWN_TYPE: i32 = -3;
const ERR_TRUNCATED: i32 = -4;
const ERR_NO_SPACE: i32 = -5;
const ERR_ABORTED: i32 = -6;
const ERR_TOO_DEEP: i32 = -7;
const ERR_BAD_VALUE: i32 = -8;

const MAX_DEPTH: i32 = 16;
const HEADER_LEN: u32 = 32;
const TYPE_ROW: usize = 12;
const FIELD_ROW: usize = 16;

const KIND_PRIM: u8 = 0;
const KIND_STRING: u8 = 1;
const KIND_STRUCT: u8 = 2;
const ARRAY_NONE: u8 = 0;
const ARRAY_FIXED: u8 = 1;
const ARRAY_SEQ: u8 = 2;
const PRIM_F64: u8 = 10;

#[repr(C)]
pub struct MsgSchema {
    blob: *const u8,
    len: usize,
    type_count: u32,
    field_count: u32,
    types_off: u32,
    fields_off: u32,
    strings_off: u32,
    strings_len: u32,
}

#[repr(C)]
pub struct MsgFieldInfo {
    name: *const c_char,
    kind: u8,
    prim: u8,
    array: u8,
    pad: u8,
    type_idx: u32,
    array_len: u32,
}

// Tipos de los callbacks del header. `Option<fn>` en un struct #[repr(C)] tiene
// el mismo layout que un puntero a función de C que puede ser NULL (Rust
// garantiza que `None` = puntero nulo para este caso).
type FBeginStruct = Option<unsafe extern "C" fn(*mut c_void, *const c_char) -> i32>;
type FEnd = Option<unsafe extern "C" fn(*mut c_void) -> i32>;

#[repr(C)]
pub struct MsgVisitor {
    begin_struct: FBeginStruct,
    end_struct: FEnd,
    prim: Option<unsafe extern "C" fn(*mut c_void, *const c_char, i32, u64) -> i32>,
    string: Option<unsafe extern "C" fn(*mut c_void, *const c_char, *const u8, u32) -> i32>,
    prim_array: Option<unsafe extern "C" fn(*mut c_void, *const c_char, i32, *const u8, u32) -> i32>,
    begin_array: Option<unsafe extern "C" fn(*mut c_void, *const c_char, u32) -> i32>,
    end_array: FEnd,
}

#[repr(C)]
pub struct MsgSource {
    begin_struct: FBeginStruct,
    end_struct: FEnd,
    prim: Option<unsafe extern "C" fn(*mut c_void, *const c_char, i32, *mut u64) -> i32>,
    string: Option<unsafe extern "C" fn(*mut c_void, *const c_char, *mut *const u8, *mut u32) -> i32>,
    prim_array: Option<
        unsafe extern "C" fn(*mut c_void, *const c_char, i32, u32, *mut *const u8, *mut u32) -> i32,
    >,
    array_len: Option<unsafe extern "C" fn(*mut c_void, *const c_char, u32, *mut u32) -> i32>,
}

// `Result<T, i32>`: Ok(valor) o Err(código). `?` propaga el Err hacia arriba
// (equivale al macro TRY de impl-c).
type R<T> = Result<T, i32>;

fn ld16(b: &[u8], o: usize) -> u32 {
    u32::from(b[o]) | u32::from(b[o + 1]) << 8
}
fn ld32(b: &[u8], o: usize) -> u32 {
    u32::from(b[o]) | u32::from(b[o + 1]) << 8 | u32::from(b[o + 2]) << 16 | u32::from(b[o + 3]) << 24
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_prim_size(p: i32) -> u32 {
    match p {
        0 | 1 | 2 => 1,
        3 | 4 => 2,
        5 | 6 | 9 => 4,
        7 | 8 | 10 => 8,
        _ => 0,
    }
}

/// Vista del blob como slice. `unsafe`: confía en que `s` pasó por `msg_schema_init`.
unsafe fn blob<'a>(s: &MsgSchema) -> &'a [u8] {
    unsafe { core::slice::from_raw_parts(s.blob, s.len) }
}

fn str_ok(b: &[u8], strings_off: usize, strings_len: u32, off: u32) -> bool {
    if off >= strings_len {
        return false;
    }
    b[strings_off + off as usize..strings_off + strings_len as usize].contains(&0)
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_init(s: *mut MsgSchema, data: *const u8, len: usize) -> i32 {
    if s.is_null() || data.is_null() {
        return ERR_INVALID_ARG;
    }
    let b = unsafe { core::slice::from_raw_parts(data, len) };
    if len < HEADER_LEN as usize || &b[0..4] != b"RSCH" || ld16(b, 4) != 1 {
        return ERR_BAD_SCHEMA;
    }
    let (tcount, fcount) = (ld32(b, 8), ld32(b, 12));
    let (toff, foff, soff, total) = (ld32(b, 16), ld32(b, 20), ld32(b, 24), ld32(b, 28));
    if total as usize != len || toff < HEADER_LEN || foff < toff || soff < foff {
        return ERR_BAD_SCHEMA;
    }
    // u64 para que las multiplicaciones no desborden aunque el blob mienta
    if u64::from(toff) + u64::from(tcount) * TYPE_ROW as u64 != u64::from(foff)
        || u64::from(foff) + u64::from(fcount) * FIELD_ROW as u64 != u64::from(soff)
    {
        return ERR_BAD_SCHEMA;
    }
    let strings_len = total - soff;
    for t in 0..tcount as usize {
        let r = toff as usize + t * TYPE_ROW;
        let (first, n) = (ld32(b, r + 4), ld32(b, r + 8));
        if !str_ok(b, soff as usize, strings_len, ld32(b, r)) || n == 0
            || u64::from(first) + u64::from(n) > u64::from(fcount)
        {
            return ERR_BAD_SCHEMA;
        }
    }
    for f in 0..fcount as usize {
        let r = foff as usize + f * FIELD_ROW;
        let (kind, prim, array) = (b[r + 4], b[r + 5], b[r + 6]);
        if !str_ok(b, soff as usize, strings_len, ld32(b, r)) || kind > KIND_STRUCT || array > ARRAY_SEQ {
            return ERR_BAD_SCHEMA;
        }
        if kind == KIND_PRIM && prim > PRIM_F64 {
            return ERR_BAD_SCHEMA;
        }
        if kind == KIND_STRUCT && ld32(b, r + 8) >= tcount {
            return ERR_BAD_SCHEMA;
        }
        if array == ARRAY_FIXED && ld32(b, r + 12) == 0 {
            return ERR_BAD_SCHEMA;
        }
    }
    unsafe {
        // `ptr::write`: inicializa sin leer/soltar el valor previo (memoria del llamador).
        ptr::write(
            s,
            MsgSchema {
                blob: data,
                len,
                type_count: tcount,
                field_count: fcount,
                types_off: toff,
                fields_off: foff,
                strings_off: soff,
                strings_len,
            },
        );
    }
    OK
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_type_count(s: *const MsgSchema) -> u32 {
    if s.is_null() { 0 } else { unsafe { (*s).type_count } }
}

fn pool(s: &MsgSchema, off: u32) -> *const c_char {
    unsafe { s.blob.add(s.strings_off as usize + off as usize) as *const c_char }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_type_name(s: *const MsgSchema, idx: u32, name: *mut *const c_char) -> i32 {
    if s.is_null() || name.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let s = &*s;
        if s.blob.is_null() {
            return ERR_INVALID_ARG;
        }
        if idx >= s.type_count {
            return ERR_UNKNOWN_TYPE;
        }
        let b = blob(s);
        *name = pool(s, ld32(b, s.types_off as usize + idx as usize * TYPE_ROW));
    }
    OK
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_find_type(s: *const MsgSchema, name: *const c_char, idx: *mut u32) -> i32 {
    if s.is_null() || name.is_null() || idx.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        if (*s).blob.is_null() {
            return ERR_INVALID_ARG;
        }
        let want = core::ffi::CStr::from_ptr(name).to_bytes();
        for t in 0..(*s).type_count {
            let mut n: *const c_char = ptr::null();
            let rc = msg_schema_type_name(s, t, &mut n);
            if rc != OK {
                return rc;
            }
            if core::ffi::CStr::from_ptr(n).to_bytes() == want {
                *idx = t;
                return OK;
            }
        }
    }
    ERR_UNKNOWN_TYPE
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_field_count(s: *const MsgSchema, idx: u32, count: *mut u32) -> i32 {
    if s.is_null() || count.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let s = &*s;
        if s.blob.is_null() {
            return ERR_INVALID_ARG;
        }
        if idx >= s.type_count {
            return ERR_UNKNOWN_TYPE;
        }
        *count = ld32(blob(s), s.types_off as usize + idx as usize * TYPE_ROW + 8);
    }
    OK
}

/// Campo `fidx` del tipo `tidx` (uso interno y exportado).
fn field_of(s: &MsgSchema, tidx: u32, fidx: u32) -> R<MsgFieldInfo> {
    if s.blob.is_null() {
        return Err(ERR_INVALID_ARG);
    }
    if tidx >= s.type_count {
        return Err(ERR_UNKNOWN_TYPE);
    }
    let b = unsafe { blob(s) };
    let t = s.types_off as usize + tidx as usize * TYPE_ROW;
    if fidx >= ld32(b, t + 8) {
        return Err(ERR_INVALID_ARG);
    }
    let r = s.fields_off as usize + (ld32(b, t + 4) as usize + fidx as usize) * FIELD_ROW;
    Ok(MsgFieldInfo {
        name: pool(s, ld32(b, r)),
        kind: b[r + 4],
        prim: b[r + 5],
        array: b[r + 6],
        pad: 0,
        type_idx: ld32(b, r + 8),
        array_len: ld32(b, r + 12),
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_field(s: *const MsgSchema, tidx: u32, fidx: u32, out: *mut MsgFieldInfo) -> i32 {
    if s.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    match field_of(unsafe { &*s }, tidx, fidx) {
        Ok(f) => {
            unsafe { ptr::write(out, f) };
            OK
        }
        Err(e) => e,
    }
}

fn field_count_of(s: &MsgSchema, tidx: u32) -> R<u32> {
    let mut n = 0u32;
    let rc = msg_schema_field_count(s, tidx, &mut n);
    if rc == OK { Ok(n) } else { Err(rc) }
}

// ---------------------------------------------------------------- decode
struct Dec<'a> {
    s: &'a MsgSchema,
    b: &'a [u8],
    pos: usize,
    v: &'a MsgVisitor,
    ctx: *mut c_void,
}

// `cb!`: ejecuta un callback opcional; si devuelve != 0 sale con ABORTED.
// (macro_rules! = macro por patrones de Rust, como un #define pero tipado.)
macro_rules! cb {
    ($f:expr, $($arg:expr),* $(,)?) => {
        if let Some(f) = $f {
            if unsafe { f($($arg),*) } != 0 {
                return Err(ERR_ABORTED);
            }
        }
    };
}

impl<'a> Dec<'a> {
    fn align(&mut self, a: usize) -> R<()> {
        let p = (self.pos + (a - 1)) & !(a - 1);
        if p > self.b.len() {
            return Err(ERR_TRUNCATED);
        }
        self.pos = p;
        Ok(())
    }
    fn need(&self, n: usize) -> R<()> {
        if self.b.len() - self.pos >= n { Ok(()) } else { Err(ERR_TRUNCATED) }
    }
    fn u32(&mut self) -> R<u32> {
        self.align(4)?;
        self.need(4)?;
        let v = ld32(self.b, self.pos);
        self.pos += 4;
        Ok(v)
    }

    fn string(&mut self, name: *const c_char) -> R<()> {
        let n = self.u32()? as usize;
        self.need(n)?;
        let content = if n > 0 { (n - 1) as u32 } else { 0 };
        cb!(self.v.string, self.ctx, name, self.b[self.pos..].as_ptr(), content);
        self.pos += n;
        Ok(())
    }

    fn field(&mut self, f: &MsgFieldInfo, depth: i32) -> R<()> {
        if f.array == ARRAY_NONE {
            if f.kind == KIND_PRIM {
                let sz = msg_prim_size(i32::from(f.prim)) as usize;
                self.align(sz)?;
                self.need(sz)?;
                let mut raw = 0u64;
                for i in (0..sz).rev() {
                    raw = (raw << 8) | u64::from(self.b[self.pos + i]);
                }
                cb!(self.v.prim, self.ctx, f.name, i32::from(f.prim), raw);
                self.pos += sz;
                return Ok(());
            }
            if f.kind == KIND_STRING {
                return self.string(f.name);
            }
            return self.strukt(f.type_idx, f.name, depth + 1);
        }

        let mut count = f.array_len;
        if f.array == ARRAY_SEQ {
            count = self.u32()?;
            if count as usize > self.b.len() - self.pos {
                return Err(ERR_TRUNCATED); // cada elemento ocupa >= 1 byte
            }
        }
        if f.kind == KIND_PRIM {
            let sz = msg_prim_size(i32::from(f.prim)) as usize;
            // checked_mul: None si desborda (en 32 bits un array fijo enorme lo haría)
            let bytes = (count as usize).checked_mul(sz).ok_or(ERR_TRUNCATED)?;
            if count > 0 {
                self.align(sz)?;
            }
            self.need(bytes)?;
            cb!(self.v.prim_array, self.ctx, f.name, i32::from(f.prim), self.b[self.pos..].as_ptr(), count);
            self.pos += bytes;
            return Ok(());
        }
        cb!(self.v.begin_array, self.ctx, f.name, count);
        for _ in 0..count {
            if f.kind == KIND_STRING {
                self.string(ptr::null())?;
            } else {
                self.strukt(f.type_idx, ptr::null(), depth + 1)?;
            }
        }
        cb!(self.v.end_array, self.ctx,);
        Ok(())
    }

    fn strukt(&mut self, tidx: u32, name: *const c_char, depth: i32) -> R<()> {
        if depth > MAX_DEPTH {
            return Err(ERR_TOO_DEEP);
        }
        let nf = field_count_of(self.s, tidx)?;
        cb!(self.v.begin_struct, self.ctx, name);
        for i in 0..nf {
            let f = field_of(self.s, tidx, i)?;
            self.field(&f, depth)?;
        }
        cb!(self.v.end_struct, self.ctx,);
        Ok(())
    }
}

fn code(r: R<()>) -> i32 {
    match r {
        Ok(()) => OK,
        Err(e) => e,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_decode(
    s: *const MsgSchema,
    type_idx: u32,
    buf: *const u8,
    len: usize,
    vis: *const MsgVisitor,
    ctx: *mut c_void,
    consumed: *mut usize,
) -> i32 {
    if s.is_null() || buf.is_null() || vis.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let s = &*s;
        if s.blob.is_null() {
            return ERR_INVALID_ARG;
        }
        let mut d = Dec { s, b: core::slice::from_raw_parts(buf, len), pos: 0, v: &*vis, ctx };
        let rc = code(d.strukt(type_idx, ptr::null(), 0));
        if rc == OK && !consumed.is_null() {
            *consumed = d.pos;
        }
        rc
    }
}

// ---------------------------------------------------------------- encode
struct Enc<'a> {
    s: &'a MsgSchema,
    out: &'a mut [u8],
    pos: usize,
    src: &'a MsgSource,
    ctx: *mut c_void,
}

impl<'a> Enc<'a> {
    fn pad(&mut self, a: usize) -> R<()> {
        let p = (self.pos + (a - 1)) & !(a - 1);
        if p > self.out.len() {
            return Err(ERR_NO_SPACE);
        }
        for i in self.pos..p {
            self.out[i] = 0;
        }
        self.pos = p;
        Ok(())
    }
    fn room(&self, n: usize) -> R<()> {
        if self.out.len() - self.pos >= n { Ok(()) } else { Err(ERR_NO_SPACE) }
    }
    fn u32(&mut self, v: u32) -> R<()> {
        self.pad(4)?;
        self.room(4)?;
        for i in 0..4 {
            self.out[self.pos + i] = (v >> (8 * i)) as u8;
        }
        self.pos += 4;
        Ok(())
    }

    fn string(&mut self, name: *const c_char) -> R<()> {
        let f = self.src.string.ok_or(ERR_INVALID_ARG)?;
        let mut p: *const u8 = ptr::null();
        let mut n: u32 = 0;
        if unsafe { f(self.ctx, name, &mut p, &mut n) } != 0 {
            return Err(ERR_ABORTED);
        }
        if n == u32::MAX || (p.is_null() && n > 0) {
            return Err(ERR_BAD_VALUE);
        }
        self.u32(n + 1)?;
        self.room(n as usize + 1)?;
        if n > 0 {
            let src = unsafe { core::slice::from_raw_parts(p, n as usize) };
            self.out[self.pos..self.pos + n as usize].copy_from_slice(src);
        }
        self.out[self.pos + n as usize] = 0;
        self.pos += n as usize + 1;
        Ok(())
    }

    fn field(&mut self, f: &MsgFieldInfo, depth: i32) -> R<()> {
        let src = self.src;
        if f.array == ARRAY_NONE {
            if f.kind == KIND_PRIM {
                let sz = msg_prim_size(i32::from(f.prim)) as usize;
                let cbp = src.prim.ok_or(ERR_INVALID_ARG)?;
                let mut raw = 0u64;
                if unsafe { cbp(self.ctx, f.name, i32::from(f.prim), &mut raw) } != 0 {
                    return Err(ERR_ABORTED);
                }
                self.pad(sz)?;
                self.room(sz)?;
                for i in 0..sz {
                    self.out[self.pos + i] = (raw >> (8 * i)) as u8;
                }
                self.pos += sz;
                return Ok(());
            }
            if f.kind == KIND_STRING {
                return self.string(f.name);
            }
            cb!(src.begin_struct, self.ctx, f.name);
            self.strukt(f.type_idx, depth + 1)?;
            cb!(src.end_struct, self.ctx,);
            return Ok(());
        }

        let fixed = if f.array == ARRAY_FIXED { f.array_len } else { 0 };
        let mut count = 0u32;
        let bad_count = |c: u32| (fixed != 0 && c != fixed) || (f.array == ARRAY_SEQ && f.array_len != 0 && c > f.array_len);
        if f.kind == KIND_PRIM {
            let sz = msg_prim_size(i32::from(f.prim)) as usize;
            let cbp = src.prim_array.ok_or(ERR_INVALID_ARG)?;
            let mut data: *const u8 = ptr::null();
            if unsafe { cbp(self.ctx, f.name, i32::from(f.prim), fixed, &mut data, &mut count) } != 0 {
                return Err(ERR_ABORTED);
            }
            if bad_count(count) || (data.is_null() && count > 0) {
                return Err(ERR_BAD_VALUE);
            }
            if f.array == ARRAY_SEQ {
                self.u32(count)?;
            }
            if count > 0 {
                self.pad(sz)?;
                if count as usize > (self.out.len() - self.pos) / sz {
                    return Err(ERR_NO_SPACE);
                }
                let n = count as usize * sz;
                let bytes = unsafe { core::slice::from_raw_parts(data, n) };
                self.out[self.pos..self.pos + n].copy_from_slice(bytes);
                self.pos += n;
            }
            return Ok(());
        }
        let cbl = src.array_len.ok_or(ERR_INVALID_ARG)?;
        if unsafe { cbl(self.ctx, f.name, fixed, &mut count) } != 0 {
            return Err(ERR_ABORTED);
        }
        if bad_count(count) {
            return Err(ERR_BAD_VALUE);
        }
        if f.array == ARRAY_SEQ {
            self.u32(count)?;
        }
        for _ in 0..count {
            if f.kind == KIND_STRING {
                self.string(ptr::null())?;
            } else {
                cb!(src.begin_struct, self.ctx, ptr::null());
                self.strukt(f.type_idx, depth + 1)?;
                cb!(src.end_struct, self.ctx,);
            }
        }
        Ok(())
    }

    fn strukt(&mut self, tidx: u32, depth: i32) -> R<()> {
        if depth > MAX_DEPTH {
            return Err(ERR_TOO_DEEP);
        }
        let nf = field_count_of(self.s, tidx)?;
        for i in 0..nf {
            let f = field_of(self.s, tidx, i)?;
            self.field(&f, depth)?;
        }
        Ok(())
    }
}

// `unused_unsafe`: el macro `cb!` lleva su propio `unsafe` y aquí ya estamos dentro de uno.
#[allow(unused_unsafe)]
#[unsafe(no_mangle)]
pub extern "C" fn msg_schema_encode(
    s: *const MsgSchema,
    type_idx: u32,
    src: *const MsgSource,
    ctx: *mut c_void,
    out: *mut u8,
    cap: usize,
    written: *mut usize,
) -> i32 {
    if s.is_null() || src.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        let (s, src) = (&*s, &*src);
        if s.blob.is_null() {
            return ERR_INVALID_ARG;
        }
        let mut e = Enc { s, out: core::slice::from_raw_parts_mut(out, cap), pos: 0, src, ctx };
        let r = (|| -> R<()> {
            cb!(src.begin_struct, ctx, ptr::null());
            e.strukt(type_idx, 0)?;
            cb!(src.end_struct, ctx,);
            Ok(())
        })();
        let rc = code(r);
        if rc == OK && !written.is_null() {
            *written = e.pos;
        }
        rc
    }
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
