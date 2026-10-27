//! viz-math — implementación Rust del contrato `include/viz_math.h`.
//!
//! Comentada para aprendizaje (ver docs/rust/). Novedades respecto a los
//! módulos anteriores: tipos `f32`, structs `#[repr(C)]` pasados por puntero,
//! `unsafe extern "C"` para usar la libm de C desde `no_std`, y `impl` con
//! funciones auxiliares sobre structs.
#![no_std]

// ---------------------------------------------------------------------------
// libm: `no_std` solo trae `core`, y `core` NO tiene sin/cos/tan/sqrt para
// f32 (viven en `std`). Como el módulo siempre se enlaza junto a C (gcc en
// host, VitaSDK/newlib en la Vita), pedimos prestadas las funciones de la
// libm de C, exactamente las mismas que usa impl-c → resultados casi idénticos.
//
// `unsafe extern "C" { ... }` (edición 2024) declara funciones de otro
// lenguaje. `safe fn` le dice al compilador que llamarlas es seguro (son
// funciones puras), así evitamos `unsafe` en cada uso.
// ---------------------------------------------------------------------------
unsafe extern "C" {
    safe fn sinf(x: f32) -> f32;
    safe fn cosf(x: f32) -> f32;
    safe fn tanf(x: f32) -> f32;
    safe fn sqrtf(x: f32) -> f32;
}

const EPS: f32 = 1e-12;

// `#[repr(C)]`: mismo layout que el struct de C. `#[derive(Clone, Copy)]`: el
// tipo se copia bit a bit (como un struct de C pasado por valor) en vez de
// "moverse"; necesario para poder leer `*puntero` sin consumir el original.
#[repr(C)]
#[derive(Clone, Copy)]
pub struct Vec3 {
    pub x: f32,
    pub y: f32,
    pub z: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Quat {
    pub x: f32,
    pub y: f32,
    pub z: f32,
    pub w: f32,
}

#[repr(C)]
#[derive(Clone, Copy)]
pub struct Mat4 {
    pub m: [f32; 16], // `[f32; 16]`: array de tamaño fijo conocido en compilación
}

// `impl Vec3 { ... }` añade funciones (métodos) al tipo. Aquí las usamos como
// helpers internos con semántica de VALOR: más legibles que punteros.
impl Vec3 {
    fn sub(self, o: Vec3) -> Vec3 {
        Vec3 { x: self.x - o.x, y: self.y - o.y, z: self.z - o.z }
    }
    fn dot(self, o: Vec3) -> f32 {
        self.x * o.x + self.y * o.y + self.z * o.z
    }
    fn cross(self, o: Vec3) -> Vec3 {
        Vec3 {
            x: self.y * o.z - self.z * o.y,
            y: self.z * o.x - self.x * o.z,
            z: self.x * o.y - self.y * o.x,
        }
    }
    /// `Option<Vec3>`: `Some(v)` si se pudo normalizar, `None` si |v| ~ 0.
    fn normalized(self) -> Option<Vec3> {
        let n = sqrtf(self.dot(self));
        if n < EPS {
            return None;
        }
        let inv = 1.0 / n;
        Some(Vec3 { x: self.x * inv, y: self.y * inv, z: self.z * inv })
    }
}

const VEC3_ZERO: Vec3 = Vec3 { x: 0.0, y: 0.0, z: 0.0 };
const QUAT_IDENTITY: Quat = Quat { x: 0.0, y: 0.0, z: 0.0, w: 1.0 };

fn mat4_identity_value() -> Mat4 {
    let mut m = [0.0f32; 16]; // array de 16 ceros
    m[0] = 1.0;
    m[5] = 1.0;
    m[10] = 1.0;
    m[15] = 1.0;
    Mat4 { m }
}

// ------------------------------------------------------------------- vec3
// Todas las funciones públicas reciben punteros crudos que el contrato del
// header promete NO nulos y válidos; por eso cada cuerpo es un bloque `unsafe`
// que los desreferencia (`*p`). Al ser structs `Copy`, `*p` los copia.

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_add(o: *mut Vec3, a: *const Vec3, b: *const Vec3) {
    unsafe {
        let (a, b) = (*a, *b);
        *o = Vec3 { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_sub(o: *mut Vec3, a: *const Vec3, b: *const Vec3) {
    unsafe { *o = (*a).sub(*b) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_scale(o: *mut Vec3, a: *const Vec3, s: f32) {
    unsafe {
        let a = *a;
        *o = Vec3 { x: a.x * s, y: a.y * s, z: a.z * s };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_cross(o: *mut Vec3, a: *const Vec3, b: *const Vec3) {
    unsafe { *o = (*a).cross(*b) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_dot(a: *const Vec3, b: *const Vec3) -> f32 {
    unsafe { (*a).dot(*b) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_norm(a: *const Vec3) -> f32 {
    unsafe { sqrtf((*a).dot(*a)) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_vec3_normalize(o: *mut Vec3, a: *const Vec3) -> i32 {
    unsafe {
        // `match` sobre Option: la forma idiomática de tratar "hay valor / no hay".
        match (*a).normalized() {
            Some(v) => {
                *o = v;
                0
            }
            None => {
                *o = VEC3_ZERO;
                -1
            }
        }
    }
}

// ------------------------------------------------------------------- quat

#[unsafe(no_mangle)]
pub extern "C" fn vizm_quat_identity(o: *mut Quat) {
    unsafe { *o = QUAT_IDENTITY }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_quat_from_axis_angle(o: *mut Quat, axis: *const Vec3, rad: f32) {
    unsafe {
        match (*axis).normalized() {
            None => *o = QUAT_IDENTITY,
            Some(n) => {
                let h = 0.5 * rad;
                let s = sinf(h);
                *o = Quat { x: n.x * s, y: n.y * s, z: n.z * s, w: cosf(h) };
            }
        }
    }
}

fn quat_mul_value(a: Quat, b: Quat) -> Quat {
    Quat {
        x: a.w * b.x + a.x * b.w + a.y * b.z - a.z * b.y,
        y: a.w * b.y - a.x * b.z + a.y * b.w + a.z * b.x,
        z: a.w * b.z + a.x * b.y - a.y * b.x + a.z * b.w,
        w: a.w * b.w - a.x * b.x - a.y * b.y - a.z * b.z,
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_quat_mul(o: *mut Quat, a: *const Quat, b: *const Quat) {
    unsafe { *o = quat_mul_value(*a, *b) }
}

fn quat_normalized(q: Quat) -> Quat {
    let n = sqrtf(q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w);
    if n < EPS {
        return QUAT_IDENTITY;
    }
    let inv = 1.0 / n;
    Quat { x: q.x * inv, y: q.y * inv, z: q.z * inv, w: q.w * inv }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_quat_normalize(o: *mut Quat, q: *const Quat) {
    unsafe { *o = quat_normalized(*q) }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_quat_rotate_vec3(o: *mut Vec3, q: *const Quat, v: *const Vec3) {
    unsafe {
        let (q, v) = (*q, *v);
        let u = Vec3 { x: q.x, y: q.y, z: q.z };
        let uv = u.cross(v);
        let uuv = u.cross(uv);
        *o = Vec3 {
            x: v.x + 2.0 * (q.w * uv.x + uuv.x),
            y: v.y + 2.0 * (q.w * uv.y + uuv.y),
            z: v.z + 2.0 * (q.w * uv.z + uuv.z),
        };
    }
}

fn quat_to_mat4_value(qin: Quat) -> Mat4 {
    let q = quat_normalized(qin);
    let (xx, yy, zz) = (q.x * q.x, q.y * q.y, q.z * q.z);
    let (xy, xz, yz) = (q.x * q.y, q.x * q.z, q.y * q.z);
    let (wx, wy, wz) = (q.w * q.x, q.w * q.y, q.w * q.z);
    Mat4 {
        m: [
            1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0,
            2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx), 0.0,
            2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy), 0.0,
            0.0, 0.0, 0.0, 1.0,
        ],
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_quat_to_mat4(o: *mut Mat4, q: *const Quat) {
    unsafe { *o = quat_to_mat4_value(*q) }
}

// ------------------------------------------------------------------- mat4

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_identity(o: *mut Mat4) {
    unsafe { *o = mat4_identity_value() }
}

fn mat4_mul_value(a: &Mat4, b: &Mat4) -> Mat4 {
    let mut r = [0.0f32; 16];
    // `for c in 0..4`: rango [0,4). Equivale al for de C con índices.
    for c in 0..4 {
        for row in 0..4 {
            let mut s = 0.0f32;
            for k in 0..4 {
                s += a.m[k * 4 + row] * b.m[c * 4 + k];
            }
            r[c * 4 + row] = s;
        }
    }
    Mat4 { m: r }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_mul(o: *mut Mat4, a: *const Mat4, b: *const Mat4) {
    unsafe {
        // Se calcula en un valor local antes de escribir `*o`: alias seguro.
        let r = mat4_mul_value(&*a, &*b);
        *o = r;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_translate(o: *mut Mat4, t: *const Vec3) {
    unsafe {
        let mut m = mat4_identity_value();
        let t = *t;
        m.m[12] = t.x;
        m.m[13] = t.y;
        m.m[14] = t.z;
        *o = m;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_from_trs(o: *mut Mat4, t: *const Vec3, q: *const Quat) {
    unsafe {
        let mut m = quat_to_mat4_value(*q);
        let t = *t;
        m.m[12] = t.x;
        m.m[13] = t.y;
        m.m[14] = t.z;
        *o = m;
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_inverse_rigid(o: *mut Mat4, m: *const Mat4) {
    unsafe {
        let m = (*m).m;
        let mut r = [0.0f32; 16];
        for c in 0..3 {
            for row in 0..3 {
                r[c * 4 + row] = m[row * 4 + c]; // R^T
            }
        }
        let (tx, ty, tz) = (m[12], m[13], m[14]);
        r[12] = -(r[0] * tx + r[4] * ty + r[8] * tz);
        r[13] = -(r[1] * tx + r[5] * ty + r[9] * tz);
        r[14] = -(r[2] * tx + r[6] * ty + r[10] * tz);
        r[15] = 1.0;
        *o = Mat4 { m: r };
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_perspective(
    o: *mut Mat4,
    fovy: f32,
    aspect: f32,
    zn: f32,
    zf: f32,
) -> i32 {
    unsafe {
        // `!(x > 0.0)` (y no `x <= 0.0`) también rechaza NaN, igual que impl-c.
        if !(fovy > 0.0) || !(aspect > 0.0) || !(zn > 0.0) || !(zf > zn) {
            *o = mat4_identity_value();
            return -1;
        }
        let f = 1.0 / tanf(0.5 * fovy);
        let mut m = [0.0f32; 16];
        m[0] = f / aspect;
        m[5] = f;
        m[10] = (zf + zn) / (zn - zf);
        m[11] = -1.0;
        m[14] = (2.0 * zf * zn) / (zn - zf);
        *o = Mat4 { m };
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_look_at(
    o: *mut Mat4,
    eye: *const Vec3,
    center: *const Vec3,
    up: *const Vec3,
) -> i32 {
    unsafe {
        let (eye, center, up) = (*eye, *center, *up);
        let f = match center.sub(eye).normalized() {
            Some(v) => v,
            None => {
                *o = mat4_identity_value();
                return -1;
            }
        };
        let s = match f.cross(up).normalized() {
            Some(v) => v,
            None => {
                *o = mat4_identity_value();
                return -1;
            }
        };
        let u = s.cross(f);
        let mut r = [0.0f32; 16];
        r[0] = s.x;  r[4] = s.y;  r[8] = s.z;   r[12] = -s.dot(eye);
        r[1] = u.x;  r[5] = u.y;  r[9] = u.z;   r[13] = -u.dot(eye);
        r[2] = -f.x; r[6] = -f.y; r[10] = -f.z; r[14] = f.dot(eye);
        r[15] = 1.0;
        *o = Mat4 { m: r };
        0
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn vizm_mat4_transform_point(o: *mut Vec3, m: *const Mat4, p: *const Vec3) {
    unsafe {
        let (m, p) = ((*m).m, *p);
        *o = Vec3 {
            x: m[0] * p.x + m[4] * p.y + m[8] * p.z + m[12],
            y: m[1] * p.x + m[5] * p.y + m[9] * p.z + m[13],
            z: m[2] * p.x + m[6] * p.y + m[10] * p.z + m[14],
        };
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
