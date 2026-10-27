/**
 * viz_math.c — Implementación C11 del contrato include/viz_math.h.
 * Compilar con -lm (sinf, cosf, tanf, sqrtf).
 */
#include "viz_math.h"

#include <math.h>
#include <string.h>

#define EPS 1e-12f

/* ------------------------------------------------------------------ vec3 */
void vizm_vec3_add(vizm_vec3 *o, const vizm_vec3 *a, const vizm_vec3 *b)
{
    o->x = a->x + b->x; o->y = a->y + b->y; o->z = a->z + b->z;
}

void vizm_vec3_sub(vizm_vec3 *o, const vizm_vec3 *a, const vizm_vec3 *b)
{
    o->x = a->x - b->x; o->y = a->y - b->y; o->z = a->z - b->z;
}

void vizm_vec3_scale(vizm_vec3 *o, const vizm_vec3 *a, float s)
{
    o->x = a->x * s; o->y = a->y * s; o->z = a->z * s;
}

void vizm_vec3_cross(vizm_vec3 *o, const vizm_vec3 *a, const vizm_vec3 *b)
{
    /* temporales: permiten alias (out == a o b) */
    float x = a->y * b->z - a->z * b->y;
    float y = a->z * b->x - a->x * b->z;
    float z = a->x * b->y - a->y * b->x;
    o->x = x; o->y = y; o->z = z;
}

float vizm_vec3_dot(const vizm_vec3 *a, const vizm_vec3 *b)
{
    return a->x * b->x + a->y * b->y + a->z * b->z;
}

float vizm_vec3_norm(const vizm_vec3 *a)
{
    return sqrtf(vizm_vec3_dot(a, a));
}

int vizm_vec3_normalize(vizm_vec3 *o, const vizm_vec3 *a)
{
    float n = vizm_vec3_norm(a);
    if (n < EPS) {
        o->x = o->y = o->z = 0.0f;
        return -1;
    }
    float inv = 1.0f / n;
    o->x = a->x * inv; o->y = a->y * inv; o->z = a->z * inv;
    return 0;
}

/* ------------------------------------------------------------------ quat */
void vizm_quat_identity(vizm_quat *o)
{
    o->x = o->y = o->z = 0.0f; o->w = 1.0f;
}

void vizm_quat_from_axis_angle(vizm_quat *o, const vizm_vec3 *axis, float rad)
{
    vizm_vec3 n;
    if (vizm_vec3_normalize(&n, axis) != 0) {
        vizm_quat_identity(o);
        return;
    }
    float h = 0.5f * rad;
    float s = sinf(h);
    o->x = n.x * s; o->y = n.y * s; o->z = n.z * s; o->w = cosf(h);
}

void vizm_quat_mul(vizm_quat *o, const vizm_quat *a, const vizm_quat *b)
{
    float x = a->w * b->x + a->x * b->w + a->y * b->z - a->z * b->y;
    float y = a->w * b->y - a->x * b->z + a->y * b->w + a->z * b->x;
    float z = a->w * b->z + a->x * b->y - a->y * b->x + a->z * b->w;
    float w = a->w * b->w - a->x * b->x - a->y * b->y - a->z * b->z;
    o->x = x; o->y = y; o->z = z; o->w = w;
}

void vizm_quat_normalize(vizm_quat *o, const vizm_quat *q)
{
    float n = sqrtf(q->x * q->x + q->y * q->y + q->z * q->z + q->w * q->w);
    if (n < EPS) {
        vizm_quat_identity(o);
        return;
    }
    float inv = 1.0f / n;
    o->x = q->x * inv; o->y = q->y * inv; o->z = q->z * inv; o->w = q->w * inv;
}

void vizm_quat_rotate_vec3(vizm_vec3 *o, const vizm_quat *q, const vizm_vec3 *v)
{
    /* v' = v + 2w(u×v) + 2 u×(u×v),  u = (x,y,z) */
    vizm_vec3 u = { q->x, q->y, q->z };
    vizm_vec3 uv, uuv;
    vizm_vec3_cross(&uv, &u, v);
    vizm_vec3_cross(&uuv, &u, &uv);
    o->x = v->x + 2.0f * (q->w * uv.x + uuv.x);
    o->y = v->y + 2.0f * (q->w * uv.y + uuv.y);
    o->z = v->z + 2.0f * (q->w * uv.z + uuv.z);
}

void vizm_quat_to_mat4(vizm_mat4 *o, const vizm_quat *qin)
{
    vizm_quat q;
    vizm_quat_normalize(&q, qin);
    float xx = q.x * q.x, yy = q.y * q.y, zz = q.z * q.z;
    float xy = q.x * q.y, xz = q.x * q.z, yz = q.y * q.z;
    float wx = q.w * q.x, wy = q.w * q.y, wz = q.w * q.z;
    /* column-major: m[col*4+fila] */
    o->m[0]  = 1.0f - 2.0f * (yy + zz);
    o->m[1]  = 2.0f * (xy + wz);
    o->m[2]  = 2.0f * (xz - wy);
    o->m[3]  = 0.0f;
    o->m[4]  = 2.0f * (xy - wz);
    o->m[5]  = 1.0f - 2.0f * (xx + zz);
    o->m[6]  = 2.0f * (yz + wx);
    o->m[7]  = 0.0f;
    o->m[8]  = 2.0f * (xz + wy);
    o->m[9]  = 2.0f * (yz - wx);
    o->m[10] = 1.0f - 2.0f * (xx + yy);
    o->m[11] = 0.0f;
    o->m[12] = o->m[13] = o->m[14] = 0.0f;
    o->m[15] = 1.0f;
}

/* ------------------------------------------------------------------ mat4 */
void vizm_mat4_identity(vizm_mat4 *o)
{
    memset(o->m, 0, sizeof o->m);
    o->m[0] = o->m[5] = o->m[10] = o->m[15] = 1.0f;
}

void vizm_mat4_mul(vizm_mat4 *o, const vizm_mat4 *a, const vizm_mat4 *b)
{
    float r[16];
    for (int c = 0; c < 4; c++) {
        for (int row = 0; row < 4; row++) {
            float s = 0.0f;
            for (int k = 0; k < 4; k++) {
                s += a->m[k * 4 + row] * b->m[c * 4 + k];
            }
            r[c * 4 + row] = s;
        }
    }
    memcpy(o->m, r, sizeof r);
}

void vizm_mat4_translate(vizm_mat4 *o, const vizm_vec3 *t)
{
    vizm_mat4_identity(o);
    o->m[12] = t->x; o->m[13] = t->y; o->m[14] = t->z;
}

void vizm_mat4_from_trs(vizm_mat4 *o, const vizm_vec3 *t, const vizm_quat *q)
{
    vizm_quat_to_mat4(o, q);
    o->m[12] = t->x; o->m[13] = t->y; o->m[14] = t->z;
}

void vizm_mat4_inverse_rigid(vizm_mat4 *o, const vizm_mat4 *m)
{
    float r[16];
    /* R^T en el bloque 3x3 */
    for (int c = 0; c < 3; c++) {
        for (int row = 0; row < 3; row++) {
            r[c * 4 + row] = m->m[row * 4 + c];
        }
        r[c * 4 + 3] = 0.0f;
    }
    /* t' = -R^T t */
    float tx = m->m[12], ty = m->m[13], tz = m->m[14];
    r[12] = -(r[0] * tx + r[4] * ty + r[8]  * tz);
    r[13] = -(r[1] * tx + r[5] * ty + r[9]  * tz);
    r[14] = -(r[2] * tx + r[6] * ty + r[10] * tz);
    r[15] = 1.0f;
    memcpy(o->m, r, sizeof r);
}

int vizm_mat4_perspective(vizm_mat4 *o, float fovy, float aspect, float zn, float zf)
{
    if (!(fovy > 0.0f) || !(aspect > 0.0f) || !(zn > 0.0f) || !(zf > zn)) {
        vizm_mat4_identity(o);
        return -1;
    }
    float f = 1.0f / tanf(0.5f * fovy);
    memset(o->m, 0, sizeof o->m);
    o->m[0]  = f / aspect;
    o->m[5]  = f;
    o->m[10] = (zf + zn) / (zn - zf);
    o->m[11] = -1.0f;
    o->m[14] = (2.0f * zf * zn) / (zn - zf);
    return 0;
}

int vizm_mat4_look_at(vizm_mat4 *o, const vizm_vec3 *eye,
                      const vizm_vec3 *center, const vizm_vec3 *up)
{
    vizm_vec3 f, s, u, d;
    vizm_vec3_sub(&d, center, eye);
    if (vizm_vec3_normalize(&f, &d) != 0) {
        vizm_mat4_identity(o);
        return -1;
    }
    vizm_vec3 sraw;
    vizm_vec3_cross(&sraw, &f, up);
    if (vizm_vec3_normalize(&s, &sraw) != 0) {
        vizm_mat4_identity(o);
        return -1;
    }
    vizm_vec3_cross(&u, &s, &f);
    float r[16];
    r[0] = s.x;  r[4] = s.y;  r[8]  = s.z;  r[12] = -vizm_vec3_dot(&s, eye);
    r[1] = u.x;  r[5] = u.y;  r[9]  = u.z;  r[13] = -vizm_vec3_dot(&u, eye);
    r[2] = -f.x; r[6] = -f.y; r[10] = -f.z; r[14] = vizm_vec3_dot(&f, eye);
    r[3] = 0.0f; r[7] = 0.0f; r[11] = 0.0f; r[15] = 1.0f;
    memcpy(o->m, r, sizeof r);
    return 0;
}

void vizm_mat4_transform_point(vizm_vec3 *o, const vizm_mat4 *m, const vizm_vec3 *p)
{
    float x = m->m[0] * p->x + m->m[4] * p->y + m->m[8]  * p->z + m->m[12];
    float y = m->m[1] * p->x + m->m[5] * p->y + m->m[9]  * p->z + m->m[13];
    float z = m->m[2] * p->x + m->m[6] * p->y + m->m[10] * p->z + m->m[14];
    o->x = x; o->y = y; o->z = z;
}
