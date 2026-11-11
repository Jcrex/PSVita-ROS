/**
 * parity_test.c — Batería de paridad del módulo `viz-math`.
 * El MISMO archivo se enlaza contra impl-c y contra impl-rust. Los valores
 * esperados están calculados a mano (no generados por el código probado).
 */
#include "viz_math.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#ifndef IMPL_NAME
#define IMPL_NAME "?"
#endif

static int failures = 0;
#define TOL 1e-5f

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            failures++;                                                    \
            printf("  FALLO [%s:%d] %s\n", __FILE__, __LINE__, #cond);     \
        }                                                                  \
    } while (0)

static int near(float a, float b) { return fabsf(a - b) <= TOL; }
static int vnear(vizm_vec3 v, float x, float y, float z)
{
    return near(v.x, x) && near(v.y, y) && near(v.z, z);
}

#define HALF_PI 1.57079632679f

static void test_vec3(void)
{
    vizm_vec3 a = {1, 2, 3}, b = {4, 5, 6}, o;
    vizm_vec3_add(&o, &a, &b);      CHECK(vnear(o, 5, 7, 9));
    vizm_vec3_sub(&o, &b, &a);      CHECK(vnear(o, 3, 3, 3));
    vizm_vec3_scale(&o, &a, 2.0f);  CHECK(vnear(o, 2, 4, 6));
    CHECK(near(vizm_vec3_dot(&a, &b), 32.0f));
    vizm_vec3_cross(&o, &a, &b);    CHECK(vnear(o, -3, 6, -3));
    /* i × j = k */
    vizm_vec3 i = {1, 0, 0}, j = {0, 1, 0};
    vizm_vec3_cross(&o, &i, &j);    CHECK(vnear(o, 0, 0, 1));
    vizm_vec3 v345 = {3, 4, 0};
    CHECK(near(vizm_vec3_norm(&v345), 5.0f));
    CHECK(vizm_vec3_normalize(&o, &v345) == 0 && vnear(o, 0.6f, 0.8f, 0));
    vizm_vec3 z = {0, 0, 0};
    CHECK(vizm_vec3_normalize(&o, &z) == -1 && vnear(o, 0, 0, 0));
    /* alias: out == a */
    vizm_vec3 c = {1, 2, 3};
    vizm_vec3_cross(&c, &c, &b);    CHECK(vnear(c, -3, 6, -3));
}

static void test_quat(void)
{
    vizm_vec3 zaxis = {0, 0, 1}, x1 = {1, 0, 0}, o;
    vizm_quat q;
    /* 90° alrededor de Z: (1,0,0) -> (0,1,0) */
    vizm_quat_from_axis_angle(&q, &zaxis, HALF_PI);
    CHECK(near(q.x, 0) && near(q.y, 0) && near(q.z, 0.70710678f) && near(q.w, 0.70710678f));
    vizm_quat_rotate_vec3(&o, &q, &x1);  CHECK(vnear(o, 0, 1, 0));
    /* eje no normalizado se normaliza */
    vizm_vec3 z5 = {0, 0, 5};
    vizm_quat q2;
    vizm_quat_from_axis_angle(&q2, &z5, HALF_PI);
    CHECK(near(q2.z, q.z) && near(q2.w, q.w));
    /* eje nulo -> identidad */
    vizm_vec3 zero = {0, 0, 0};
    vizm_quat_from_axis_angle(&q2, &zero, 1.0f);
    CHECK(near(q2.x, 0) && near(q2.y, 0) && near(q2.z, 0) && near(q2.w, 1));
    /* q*q = 180° en Z: (1,0,0) -> (-1,0,0) */
    vizm_quat qq;
    vizm_quat_mul(&qq, &q, &q);
    vizm_quat_rotate_vec3(&o, &qq, &x1); CHECK(vnear(o, -1, 0, 0));
    /* composición: primero Z90 luego X90 aplicado a (0,1,0)... a*b aplica b primero */
    vizm_vec3 xaxis = {1, 0, 0}, y1 = {0, 1, 0};
    vizm_quat qx, qzx;
    vizm_quat_from_axis_angle(&qx, &xaxis, HALF_PI);
    vizm_quat_mul(&qzx, &qx, &q);        /* aplica q (Z90) y después qx (X90) */
    vizm_quat_rotate_vec3(&o, &qzx, &x1);/* x -> (Z90) y -> (X90) z */
    CHECK(vnear(o, 0, 0, 1));
    (void)y1;
    /* normalize */
    vizm_quat big = {0, 0, 2, 2}, n;
    vizm_quat_normalize(&n, &big);
    CHECK(near(n.z, 0.70710678f) && near(n.w, 0.70710678f));
    vizm_quat zq = {0, 0, 0, 0};
    vizm_quat_normalize(&n, &zq);
    CHECK(near(n.w, 1) && near(n.x, 0));
}

static void test_mat4(void)
{
    vizm_mat4 id, t, r, m;
    vizm_vec3 p = {1, 2, 3}, tr = {10, 20, 30}, o;
    vizm_mat4_identity(&id);
    CHECK(id.m[0] == 1 && id.m[5] == 1 && id.m[10] == 1 && id.m[15] == 1 && id.m[1] == 0);
    vizm_mat4_translate(&t, &tr);
    CHECK(t.m[12] == 10 && t.m[13] == 20 && t.m[14] == 30);
    vizm_mat4_transform_point(&o, &t, &p);  CHECK(vnear(o, 11, 22, 33));

    /* rotación Z90 desde cuaternión: columnas (0,1,0),(-1,0,0),(0,0,1) */
    vizm_vec3 zaxis = {0, 0, 1};
    vizm_quat q;
    vizm_quat_from_axis_angle(&q, &zaxis, HALF_PI);
    vizm_quat_to_mat4(&r, &q);
    CHECK(near(r.m[0], 0) && near(r.m[1], 1) && near(r.m[4], -1) && near(r.m[5], 0) && near(r.m[10], 1));

    /* T*R: primero rota (1,0,0)->(0,1,0) y luego traslada (+10,+20,+30) */
    vizm_mat4_mul(&m, &t, &r);
    vizm_vec3 x1 = {1, 0, 0};
    vizm_mat4_transform_point(&o, &m, &x1); CHECK(vnear(o, 10, 21, 30));
    /* from_trs equivale */
    vizm_mat4 trs;
    vizm_mat4_from_trs(&trs, &tr, &q);
    vizm_mat4_transform_point(&o, &trs, &x1); CHECK(vnear(o, 10, 21, 30));
    /* inversa rígida: M^-1 * M = I y recupera el punto */
    vizm_mat4 inv, prod;
    vizm_mat4_inverse_rigid(&inv, &trs);
    vizm_mat4_mul(&prod, &inv, &trs);
    for (int k = 0; k < 16; k++) {
        CHECK(near(prod.m[k], id.m[k]));
    }
    vizm_vec3 back;
    vizm_mat4_transform_point(&o, &trs, &p);
    vizm_mat4_transform_point(&back, &inv, &o);
    CHECK(vnear(back, 1, 2, 3));
    /* alias en mul: a = a*b */
    vizm_mat4 a = t;
    vizm_mat4_mul(&a, &a, &r);
    for (int k = 0; k < 16; k++) {
        CHECK(near(a.m[k], m.m[k]));
    }
}

static void test_projection_view(void)
{
    vizm_mat4 pr, v;
    /* fovy 90°, aspect 1, near 1, far 3: f=1; m[10]=(3+1)/(1-3)=-2; m[14]=2*3*1/(1-3)=-3 */
    CHECK(vizm_mat4_perspective(&pr, HALF_PI, 1.0f, 1.0f, 3.0f) == 0);
    CHECK(near(pr.m[0], 1) && near(pr.m[5], 1) && near(pr.m[10], -2) &&
          near(pr.m[11], -1) && near(pr.m[14], -3) && near(pr.m[15], 0));
    CHECK(vizm_mat4_perspective(&pr, 0.0f, 1.0f, 1.0f, 3.0f) == -1 && pr.m[0] == 1);
    CHECK(vizm_mat4_perspective(&pr, 1.0f, 0.0f, 1.0f, 3.0f) == -1);
    CHECK(vizm_mat4_perspective(&pr, 1.0f, 1.0f, 0.0f, 3.0f) == -1);
    CHECK(vizm_mat4_perspective(&pr, 1.0f, 1.0f, 3.0f, 3.0f) == -1);

    /* mirar desde (0,0,5) al origen, up=Y: traslación z=-5; (0,0,0) -> (0,0,-5) */
    vizm_vec3 eye = {0, 0, 5}, c = {0, 0, 0}, up = {0, 1, 0}, o, org = {0, 0, 0};
    CHECK(vizm_mat4_look_at(&v, &eye, &c, &up) == 0);
    vizm_mat4_transform_point(&o, &v, &org); CHECK(vnear(o, 0, 0, -5));
    /* un punto a la derecha (1,0,0) sigue a la derecha (x=1) */
    vizm_vec3 right = {1, 0, 0};
    vizm_mat4_transform_point(&o, &v, &right); CHECK(vnear(o, 1, 0, -5));
    /* degenerados */
    CHECK(vizm_mat4_look_at(&v, &eye, &eye, &up) == -1 && v.m[0] == 1);
    vizm_vec3 par = {0, 0, 1};
    CHECK(vizm_mat4_look_at(&v, &eye, &c, &par) == -1);
}

int main(void)
{
    printf("== parity_test viz-math [impl=%s] ==\n", IMPL_NAME);
    test_vec3();
    test_quat();
    test_mat4();
    test_projection_view();
    if (failures) {
        printf("FALLARON %d comprobaciones [impl=%s]\n", failures, IMPL_NAME);
        return 1;
    }
    printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
    return 0;
}
