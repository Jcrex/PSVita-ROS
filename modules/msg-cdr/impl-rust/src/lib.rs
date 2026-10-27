//! msg-cdr — implementación Rust del contrato `include/msg_cdr.h`.
//!
//! Novedades de Rust respecto a los módulos anteriores (explicadas al usarse):
//! `Result` y el operador `?`, slices `&[u8]`, structs `#[repr(C)]` con arrays
//! anidados, y `impl` con un "cursor" de lectura. Ver `docs/rust/04-*.md`.
#![no_std]

use core::ptr;

// Códigos de estado (iguales que `msg_cdr_status` del header).
const OK: i32 = 0;
const ERR_INVALID_ARG: i32 = -1;
const ERR_TRUNCATED: i32 = -2;
const ERR_CAPACITY: i32 = -3;
const ERR_UNSUPPORTED: i32 = -4;

const NAME_MAX: usize = 64;
const MAX_TRANSFORMS: usize = 32;
const MAX_JOINTS: usize = 32;
const MAX_MARKER_POINTS: usize = 64;

// ---------------------------------------------------------------------------
// Structs de salida: réplica exacta (mismo orden, mismos tipos) de los del
// header. `#[repr(C)]` garantiza el mismo layout que C; `char` de C es `u8` aquí.
// Los `const _: () = assert!(...)` fallan al COMPILAR si el tamaño difiere.
// ---------------------------------------------------------------------------
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Time {
    pub sec: i32,
    pub nanosec: u32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Transform {
    pub stamp: Time,
    pub frame_id: [u8; NAME_MAX],
    pub child_frame_id: [u8; NAME_MAX],
    pub translation: [f64; 3],
    pub rotation: [f64; 4],
}

#[repr(C)]
pub struct TfMessage {
    pub count: u32,
    pub dropped: u32,
    pub strings_truncated: u32,
    pub reserved: u32,
    pub items: [Transform; MAX_TRANSFORMS],
}

#[repr(C)]
pub struct JointState {
    pub stamp: Time,
    pub frame_id: [u8; NAME_MAX],
    pub name_count: u32,
    pub position_count: u32,
    pub velocity_count: u32,
    pub effort_count: u32,
    pub dropped: u32,
    pub strings_truncated: u32,
    pub names: [[u8; NAME_MAX]; MAX_JOINTS],
    pub position: [f64; MAX_JOINTS],
    pub velocity: [f64; MAX_JOINTS],
    pub effort: [f64; MAX_JOINTS],
}

#[repr(C)]
pub struct OccupancyGrid {
    pub stamp: Time,
    pub frame_id: [u8; NAME_MAX],
    pub map_load_time: Time,
    pub resolution: f32,
    pub width: u32,
    pub height: u32,
    pub origin_position: [f64; 3],
    pub origin_orientation: [f64; 4],
    pub data: *const i8,
    pub data_len: u32,
    pub strings_truncated: u32,
}

#[repr(C)]
pub struct Marker {
    pub stamp: Time,
    pub frame_id: [u8; NAME_MAX],
    pub ns: [u8; NAME_MAX],
    pub id: i32,
    pub r#type: i32, // `type` es palabra reservada en Rust: `r#type` la "escapa"
    pub action: i32,
    pub frame_locked: u32,
    pub position: [f64; 3],
    pub orientation: [f64; 4],
    pub scale: [f64; 3],
    pub color: [f32; 4],
    pub lifetime: Time,
    pub point_count: u32,
    pub color_count: u32,
    pub points_dropped: u32,
    pub colors_dropped: u32,
    pub strings_truncated: u32,
    pub reserved: u32,
    pub points: [[f64; 3]; MAX_MARKER_POINTS],
    pub colors: [[f32; 4]; MAX_MARKER_POINTS],
}

const _: () = assert!(core::mem::size_of::<Transform>() == 192);
const _: () = assert!(core::mem::size_of::<TfMessage>() == 16 + 32 * 192);
const _: () = assert!(core::mem::size_of::<JointState>() == 2912);
const _: () = assert!(core::mem::size_of::<Marker>() == 2840);

// ---------------------------------------------------------------------------
// Cursor de lectura
// ---------------------------------------------------------------------------
// `Result<T, i32>`: el tipo de Rust para "puede fallar". `Ok(valor)` o
// `Err(codigo)`. El operador `?` al final de una expresión significa: "si es
// Err, sal de la función devolviendo ese Err; si es Ok, dame el valor". Es el
// equivalente del macro TRY(...) de impl-c.
type R<T> = Result<T, i32>;

// `&'a [u8]`: un "slice": puntero + longitud a bytes prestados (no copia).
// `'a` es el "lifetime": cuánto vive el préstamo; aquí el cursor no puede
// sobrevivir al buffer del que lee.
struct Cur<'a> {
    b: &'a [u8],
    pos: usize,
}

impl<'a> Cur<'a> {
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
        let p = &self.b[self.pos..self.pos + 4]; // sub-slice: bytes pos..pos+4
        self.pos += 4;
        Ok(u32::from(p[0]) | u32::from(p[1]) << 8 | u32::from(p[2]) << 16 | u32::from(p[3]) << 24)
    }

    fn i32(&mut self) -> R<i32> {
        // `as i32` reinterpreta los bits del u32 (complemento a dos), igual que memcpy en C.
        Ok(self.u32()? as i32)
    }

    fn f32(&mut self) -> R<f32> {
        Ok(f32::from_bits(self.u32()?)) // from_bits: bits -> float, sin conversión numérica
    }

    fn f64(&mut self) -> R<f64> {
        self.align(8)?;
        self.need(8)?;
        let mut u: u64 = 0;
        for i in (0..8).rev() {
            u = (u << 8) | u64::from(self.b[self.pos + i]);
        }
        self.pos += 8;
        Ok(f64::from_bits(u))
    }

    fn boolean(&mut self) -> R<u32> {
        self.need(1)?;
        let v = self.b[self.pos] != 0;
        self.pos += 1;
        Ok(v as u32)
    }

    fn time(&mut self) -> R<Time> {
        Ok(Time { sec: self.i32()?, nanosec: self.u32()? })
    }

    /// String CDR. `dst = Some(buffer)` copia (truncando); `None` solo salta.
    /// `Option<&mut [u8; 64]>`: "quizá me das un buffer donde escribir".
    fn string(&mut self, dst: Option<&mut [u8; NAME_MAX]>, truncated: &mut u32) -> R<()> {
        let len = self.u32()? as usize;
        self.need(len)?;
        if let Some(d) = dst {
            let content = if len > 0 { len - 1 } else { 0 };
            let n = if content < NAME_MAX - 1 { content } else { NAME_MAX - 1 };
            d[..n].copy_from_slice(&self.b[self.pos..self.pos + n]);
            d[n] = 0;
            if content > NAME_MAX - 1 {
                *truncated += 1;
            }
        }
        self.pos += len;
        Ok(())
    }

    fn f64s<const N: usize>(&mut self, out: &mut [f64; N]) -> R<()> {
        // `const N: usize`: el tamaño del array es un parámetro genérico
        // (sirve igual para [f64;3] y [f64;4]). `iter_mut` da `&mut` a cada elemento.
        for v in out.iter_mut() {
            *v = self.f64()?;
        }
        Ok(())
    }

    fn seq_len(&mut self) -> R<u32> {
        let n = self.u32()?;
        if n as usize > self.b.len() - self.pos {
            return Err(ERR_TRUNCATED);
        }
        Ok(n)
    }

    fn header(&mut self, stamp: &mut Time, frame: &mut [u8; NAME_MAX], trunc: &mut u32) -> R<()> {
        *stamp = self.time()?;
        self.string(Some(frame), trunc)
    }
}

fn min_u32(a: u32, b: usize) -> u32 {
    if (a as usize) < b { a } else { b as u32 }
}

// Convierte el Result interno en el código entero del ABI de C.
fn to_code(r: R<i32>) -> i32 {
    match r {
        Ok(code) => code,
        Err(code) => code,
    }
}

// `slice::from_raw_parts(ptr, len)` fabrica un `&[u8]` desde puntero crudo +
// longitud. Es `unsafe` porque Rust no puede comprobar que el puntero sea
// válido: aquí lo promete el llamador C (contrato del header).
unsafe fn input<'a>(buf: *const u8, len: usize) -> &'a [u8] {
    unsafe { core::slice::from_raw_parts(buf, len) }
}

// ---------------------------------------------------------------------------
// API con ABI C
// ---------------------------------------------------------------------------
#[unsafe(no_mangle)]
pub extern "C" fn msg_cdr_strip_encapsulation(
    buf: *const u8,
    len: usize,
    payload: *mut *const u8,
    payload_len: *mut usize,
) -> i32 {
    if buf.is_null() || payload.is_null() || payload_len.is_null() {
        return ERR_INVALID_ARG;
    }
    if len < 4 {
        return ERR_TRUNCATED;
    }
    unsafe {
        let b = input(buf, 4);
        if b[0] != 0 {
            return ERR_INVALID_ARG;
        }
        if b[1] == 0x00 {
            return ERR_UNSUPPORTED;
        }
        if b[1] != 0x01 {
            return ERR_INVALID_ARG;
        }
        *payload = buf.add(4);
        *payload_len = len - 4;
    }
    OK
}

fn tf_transform(c: &mut Cur, t: &mut Transform, trunc: &mut u32) -> R<()> {
    c.header(&mut t.stamp, &mut t.frame_id, trunc)?;
    c.string(Some(&mut t.child_frame_id), trunc)?;
    c.f64s(&mut t.translation)?;
    c.f64s(&mut t.rotation)
}

fn tf_decode(c: &mut Cur, out: &mut TfMessage) -> R<i32> {
    let n = c.seq_len()?;
    // `scratch`: destino de los elementos que no caben (hay que leerlos igual
    // para avanzar el cursor). `core::mem::zeroed` = memset a 0 (unsafe: el
    // tipo debe admitir ceros, y Transform lo admite: solo números y bytes).
    let mut scratch: Transform = unsafe { core::mem::zeroed() };
    for i in 0..n as usize {
        // Se acumula directamente en `out.strings_truncated` (como impl-c) para
        // que, incluso ante un error, el estado parcial sea idéntico en ambas.
        // Rust permite prestar a la vez `out.items[i]` y `out.strings_truncated`
        // porque son campos distintos de `out` ("préstamos disjuntos").
        if i < MAX_TRANSFORMS {
            tf_transform(c, &mut out.items[i], &mut out.strings_truncated)?;
        } else {
            tf_transform(c, &mut scratch, &mut out.strings_truncated)?;
        }
    }
    out.count = min_u32(n, MAX_TRANSFORMS);
    out.dropped = n - out.count;
    Ok(if out.dropped > 0 { ERR_CAPACITY } else { OK })
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_cdr_decode_tf_message(buf: *const u8, len: usize, out: *mut TfMessage) -> i32 {
    if buf.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        ptr::write_bytes(out, 0, 1); // memset(out, 0, sizeof *out)
        let mut c = Cur { b: input(buf, len), pos: 0 };
        to_code(tf_decode(&mut c, &mut *out))
    }
}

fn js_decode(c: &mut Cur, out: &mut JointState) -> R<i32> {
    c.header(&mut out.stamp, &mut out.frame_id, &mut out.strings_truncated)?;

    let n = c.seq_len()?;
    for i in 0..n as usize {
        if i < MAX_JOINTS {
            c.string(Some(&mut out.names[i]), &mut out.strings_truncated)?;
        } else {
            c.string(None, &mut out.strings_truncated)?;
        }
    }
    out.name_count = min_u32(n, MAX_JOINTS);
    out.dropped += n - out.name_count;

    // Los tres arrays de float64 se leen igual: recorrido genérico.
    for a in 0..3 {
        let n = c.seq_len()?;
        for i in 0..n as usize {
            let v = c.f64()?;
            if i < MAX_JOINTS {
                match a {
                    0 => out.position[i] = v,
                    1 => out.velocity[i] = v,
                    _ => out.effort[i] = v,
                }
            }
        }
        let kept = min_u32(n, MAX_JOINTS);
        match a {
            0 => out.position_count = kept,
            1 => out.velocity_count = kept,
            _ => out.effort_count = kept,
        }
        out.dropped += n - kept;
    }
    Ok(if out.dropped > 0 { ERR_CAPACITY } else { OK })
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_cdr_decode_joint_state(buf: *const u8, len: usize, out: *mut JointState) -> i32 {
    if buf.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        ptr::write_bytes(out, 0, 1);
        let mut c = Cur { b: input(buf, len), pos: 0 };
        to_code(js_decode(&mut c, &mut *out))
    }
}

fn og_decode(c: &mut Cur, out: &mut OccupancyGrid) -> R<i32> {
    c.header(&mut out.stamp, &mut out.frame_id, &mut out.strings_truncated)?;
    out.map_load_time = c.time()?;
    out.resolution = c.f32()?;
    out.width = c.u32()?;
    out.height = c.u32()?;
    c.f64s(&mut out.origin_position)?;
    c.f64s(&mut out.origin_orientation)?;
    let n = c.u32()?;
    c.need(n as usize)?;
    // `as_ptr()` da el puntero al primer byte del slice; `.add(pos)` avanza.
    out.data = unsafe { c.b.as_ptr().add(c.pos) } as *const i8;
    out.data_len = n;
    Ok(OK)
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_cdr_decode_occupancy_grid(
    buf: *const u8,
    len: usize,
    out: *mut OccupancyGrid,
) -> i32 {
    if buf.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        ptr::write_bytes(out, 0, 1);
        let mut c = Cur { b: input(buf, len), pos: 0 };
        to_code(og_decode(&mut c, &mut *out))
    }
}

fn mk_decode(c: &mut Cur, out: &mut Marker) -> R<i32> {
    c.header(&mut out.stamp, &mut out.frame_id, &mut out.strings_truncated)?;
    c.string(Some(&mut out.ns), &mut out.strings_truncated)?;
    out.id = c.i32()?;
    out.r#type = c.i32()?;
    out.action = c.i32()?;
    c.f64s(&mut out.position)?;
    c.f64s(&mut out.orientation)?;
    c.f64s(&mut out.scale)?;
    for i in 0..4 {
        out.color[i] = c.f32()?;
    }
    out.lifetime = c.time()?;
    out.frame_locked = c.boolean()?;

    let n = c.seq_len()?;
    for i in 0..n as usize {
        let mut p = [0.0f64; 3];
        c.f64s(&mut p)?;
        if i < MAX_MARKER_POINTS {
            out.points[i] = p;
        }
    }
    out.point_count = min_u32(n, MAX_MARKER_POINTS);
    out.points_dropped = n - out.point_count;

    let n = c.seq_len()?;
    for i in 0..n as usize {
        let mut col = [0.0f32; 4];
        for k in 0..4 {
            col[k] = c.f32()?;
        }
        if i < MAX_MARKER_POINTS {
            out.colors[i] = col;
        }
    }
    out.color_count = min_u32(n, MAX_MARKER_POINTS);
    out.colors_dropped = n - out.color_count;

    Ok(if out.points_dropped > 0 || out.colors_dropped > 0 { ERR_CAPACITY } else { OK })
}

#[unsafe(no_mangle)]
pub extern "C" fn msg_cdr_decode_marker(buf: *const u8, len: usize, out: *mut Marker) -> i32 {
    if buf.is_null() || out.is_null() {
        return ERR_INVALID_ARG;
    }
    unsafe {
        ptr::write_bytes(out, 0, 1);
        let mut c = Cur { b: input(buf, len), pos: 0 };
        to_code(mk_decode(&mut c, &mut *out))
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
