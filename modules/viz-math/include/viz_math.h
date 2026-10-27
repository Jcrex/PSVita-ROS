/**
 * viz_math.h — Contrato C-ABI del módulo dual `viz-math`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: matemática 3D mínima en `float` para TF, cámara y modelo del
 * robot del mini-rviz (docs/11). Sin malloc, sin estado global, sin
 * dependencias salvo libm (sinf/cosf/tanf/sqrtf).
 *
 * Convenciones (idénticas a OpenGL, que es lo que consume vitaGL):
 *  - mat4 es COLUMN-MAJOR: m[col*4 + fila]. La traslación vive en m[12..14].
 *  - Un punto/vector columna se transforma como  p' = M * p.
 *  - Mano derecha, ángulos en RADIANES, cuaterniones (x,y,z,w) con w escalar
 *    (mismo orden que geometry_msgs/Quaternion).
 *  - `mat4_mul(out, a, b)` calcula out = a * b (aplica primero b). `out`
 *    puede coincidir con a o b (se usa un temporal interno).
 *  - Se usa `float` a propósito: el Cortex-A9 de la Vita tiene VFPv3/NEON
 *    para f32; f64 es más lento y no auto-vectoriza (docs/14 §2).
 */
#ifndef VITA_VIZ_MATH_H
#define VITA_VIZ_MATH_H

#ifdef __cplusplus
extern "C" {
#endif

typedef struct { float x, y, z; } vizm_vec3;
typedef struct { float x, y, z, w; } vizm_quat;
typedef struct { float m[16]; } vizm_mat4;

/* ---- vec3 ---- */
void  vizm_vec3_add(vizm_vec3 *out, const vizm_vec3 *a, const vizm_vec3 *b);
void  vizm_vec3_sub(vizm_vec3 *out, const vizm_vec3 *a, const vizm_vec3 *b);
void  vizm_vec3_scale(vizm_vec3 *out, const vizm_vec3 *a, float s);
void  vizm_vec3_cross(vizm_vec3 *out, const vizm_vec3 *a, const vizm_vec3 *b);
float vizm_vec3_dot(const vizm_vec3 *a, const vizm_vec3 *b);
/** Longitud euclídea. */
float vizm_vec3_norm(const vizm_vec3 *a);
/** out = a/|a|. Devuelve 0 si OK, -1 si |a| < 1e-12 (out = 0,0,0). */
int   vizm_vec3_normalize(vizm_vec3 *out, const vizm_vec3 *a);

/* ---- quat ---- */
void  vizm_quat_identity(vizm_quat *out);
/** Rotación de `radians` alrededor de `axis` (se normaliza). Eje nulo → identidad. */
void  vizm_quat_from_axis_angle(vizm_quat *out, const vizm_vec3 *axis, float radians);
/** out = a * b (aplica primero b). Alias permitido. */
void  vizm_quat_mul(vizm_quat *out, const vizm_quat *a, const vizm_quat *b);
/** Normaliza. Norma < 1e-12 → identidad. */
void  vizm_quat_normalize(vizm_quat *out, const vizm_quat *q);
/** Rota v con q (q unitario). */
void  vizm_quat_rotate_vec3(vizm_vec3 *out, const vizm_quat *q, const vizm_vec3 *v);
/** Matriz de rotación 4x4 de q (se normaliza antes). */
void  vizm_quat_to_mat4(vizm_mat4 *out, const vizm_quat *q);

/* ---- mat4 (column-major) ---- */
void  vizm_mat4_identity(vizm_mat4 *out);
void  vizm_mat4_mul(vizm_mat4 *out, const vizm_mat4 *a, const vizm_mat4 *b);
void  vizm_mat4_translate(vizm_mat4 *out, const vizm_vec3 *t);
/** Matriz de un transform rígido: out = T(t) * R(q). */
void  vizm_mat4_from_trs(vizm_mat4 *out, const vizm_vec3 *t, const vizm_quat *q);
/** Inversa de una matriz RÍGIDA (rotación+traslación): R^T y -R^T t. No sirve
 *  para escalas ni proyecciones. */
void  vizm_mat4_inverse_rigid(vizm_mat4 *out, const vizm_mat4 *m);
/** Proyección en perspectiva (estilo gluPerspective): fovy en radianes,
 *  profundidad NDC [-1,1]. Devuelve -1 (y out = identidad) si fovy<=0,
 *  aspect<=0, near<=0 o far<=near; 0 si OK. */
int   vizm_mat4_perspective(vizm_mat4 *out, float fovy, float aspect, float znear, float zfar);
/** Vista (estilo gluLookAt). Devuelve -1 (out = identidad) si eye==center o
 *  `up` es paralelo a la dirección de mirada; 0 si OK. */
int   vizm_mat4_look_at(vizm_mat4 *out, const vizm_vec3 *eye,
                        const vizm_vec3 *center, const vizm_vec3 *up);
/** p' = M * (p,1), sin división por w (válido para transforms rígidos/afines). */
void  vizm_mat4_transform_point(vizm_vec3 *out, const vizm_mat4 *m, const vizm_vec3 *p);

#ifdef __cplusplus
}
#endif

#endif /* VITA_VIZ_MATH_H */
