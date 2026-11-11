/**
 * parity_test.c — Batería de paridad del módulo `tf-tree`.
 * Los valores esperados están calculados a mano (ver comentarios).
 */
#include "tf_tree.h"

#include <math.h>
#include <stdio.h>
#include <string.h>

#ifndef IMPL_NAME
#define IMPL_NAME "?"
#endif

static int failures = 0;

#define CHECK(cond)                                                        \
    do {                                                                   \
        if (!(cond)) {                                                     \
            failures++;                                                    \
            printf("  FALLO [%s:%d] %s\n", __FILE__, __LINE__, #cond);     \
        }                                                                  \
    } while (0)

static int near(float a, float b) { return fabsf(a - b) <= 1e-5f; }

static uint8_t backing[8192] __attribute__((aligned(8)));
#define HALF_PI 1.57079632679f

static const vizm_quat QI = {0, 0, 0, 1};

static vizm_quat qz(float rad)
{
    vizm_vec3 z = {0, 0, 1};
    vizm_quat q;
    vizm_quat_from_axis_angle(&q, &z, rad);
    return q;
}

static int xform(tf_tree *tr, const char *target, const char *source,
                 float x, float y, float z, vizm_vec3 *out)
{
    vizm_mat4 m;
    int rc = tf_tree_lookup(tr, target, source, &m);
    if (rc == TF_TREE_OK) {
        vizm_vec3 p = {x, y, z};
        vizm_mat4_transform_point(out, &m, &p);
    }
    return rc;
}

#define PT(v, a, b, c) (near((v).x, (a)) && near((v).y, (b)) && near((v).z, (c)))

static tf_tree *build(void)
{
    tf_tree *tr = tf_tree_create(backing, sizeof backing);
    vizm_vec3 t_odom = {1, 0, 0}, t_base = {0, 2, 0}, t_laser = {0.5f, 0, 0}, t_cam = {0, 0, 1};
    vizm_quat q90 = qz(HALF_PI);
    CHECK(tf_tree_update(tr, "world", "odom", &t_odom, &QI) == TF_TREE_OK);
    CHECK(tf_tree_update(tr, "odom", "base_link", &t_base, &q90) == TF_TREE_OK);
    CHECK(tf_tree_update(tr, "base_link", "laser", &t_laser, &QI) == TF_TREE_OK);
    CHECK(tf_tree_update(tr, "base_link", "camera", &t_cam, &QI) == TF_TREE_OK);
    return tr;
}

static void test_create(void)
{
    CHECK(tf_tree_required_size() == 8 + 32 * 96);
    CHECK(tf_tree_create(NULL, sizeof backing) == NULL);
    CHECK(tf_tree_create(backing + 1, sizeof backing - 1) == NULL);
    CHECK(tf_tree_create(backing, tf_tree_required_size() - 1) == NULL);
    tf_tree *tr = tf_tree_create(backing, tf_tree_required_size());
    CHECK(tr != NULL && tf_tree_frame_count(tr) == 0 && tf_tree_rejected(tr) == 0);
    CHECK(tf_tree_frame_count(NULL) == 0 && tf_tree_rejected(NULL) == 0);
}

static void test_lookup_chain(void)
{
    tf_tree *tr = build();
    vizm_vec3 o;
    CHECK(tf_tree_frame_count(tr) == 5);

    /* laser (0,0,0) -> base (0.5,0,0) -> odom R90: (0,0.5,0)+(0,2,0)=(0,2.5,0) -> world +(1,0,0) */
    CHECK(xform(tr, "world", "laser", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 1, 2.5f, 0));
    /* punto (1,0,0) en laser: base (1.5,0,0) -> odom (0,1.5,0)+(0,2,0)=(0,3.5,0) -> world (1,3.5,0) */
    CHECK(xform(tr, "world", "laser", 1, 0, 0, &o) == TF_TREE_OK && PT(o, 1, 3.5f, 0));
    /* inversa: el origen de world visto desde laser */
    CHECK(xform(tr, "laser", "world", 1, 2.5f, 0, &o) == TF_TREE_OK && PT(o, 0, 0, 0));
    CHECK(xform(tr, "laser", "world", 1, 3.5f, 0, &o) == TF_TREE_OK && PT(o, 1, 0, 0));
    /* hermanos: origen de laser (0.5,0,0 en base) visto desde camera (0,0,1 en base) */
    CHECK(xform(tr, "camera", "laser", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 0.5f, 0, -1));
    /* un solo salto y misma identidad */
    CHECK(xform(tr, "odom", "base_link", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 0, 2, 0));
    CHECK(xform(tr, "odom", "odom", 3, 4, 5, &o) == TF_TREE_OK && PT(o, 3, 4, 5));
    /* barra inicial */
    CHECK(xform(tr, "/world", "/laser", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 1, 2.5f, 0));
}

static void test_errors(void)
{
    tf_tree *tr = build();
    vizm_vec3 t = {0, 0, 0}, o;
    CHECK(xform(tr, "world", "nada", 0, 0, 0, &o) == TF_TREE_ERR_UNKNOWN_FRAME);
    CHECK(xform(tr, "nada", "world", 0, 0, 0, &o) == TF_TREE_ERR_UNKNOWN_FRAME);
    CHECK(xform(tr, "", "world", 0, 0, 0, &o) == TF_TREE_ERR_INVALID_ARG);
    CHECK(xform(tr, NULL, "world", 0, 0, 0, &o) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_lookup(tr, "a", "b", NULL) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_lookup(NULL, "a", "b", (vizm_mat4 *)backing) == TF_TREE_ERR_INVALID_ARG);

    /* árbol desconectado */
    CHECK(tf_tree_update(tr, "map", "mapchild", &t, &QI) == TF_TREE_OK);
    CHECK(xform(tr, "world", "mapchild", 0, 0, 0, &o) == TF_TREE_ERR_NO_PATH);

    /* ciclos: padre = descendiente; auto-referencia */
    CHECK(tf_tree_update(tr, "laser", "world", &t, &QI) == TF_TREE_ERR_CYCLE);
    CHECK(tf_tree_update(tr, "odom", "odom", &t, &QI) == TF_TREE_ERR_CYCLE);
    CHECK(xform(tr, "world", "laser", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 1, 2.5f, 0)); /* intacto */

    /* nombres inválidos */
    char longname[80];
    memset(longname, 'x', 70);
    longname[70] = '\0';
    CHECK(tf_tree_update(tr, longname, "a", &t, &QI) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_update(tr, "a", "", &t, &QI) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_update(tr, "a", "/", &t, &QI) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_update(NULL, "a", "b", &t, &QI) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_update(tr, "a", "b", NULL, &QI) == TF_TREE_ERR_INVALID_ARG);
}

static void test_update_reparent(void)
{
    tf_tree *tr = build();
    vizm_vec3 o, t = {5, 0, 0};
    /* mover el laser: ahora cuelga de odom en (5,0,0) */
    CHECK(tf_tree_update(tr, "odom", "laser", &t, &QI) == TF_TREE_OK);
    CHECK(xform(tr, "world", "laser", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 6, 0, 0));
    CHECK(tf_tree_frame_count(tr) == 5);
    /* cuaternión no unitario (0,0,2,2) se normaliza -> rotación 90° */
    vizm_quat big = {0, 0, 2, 2};
    vizm_vec3 z = {0, 0, 0};
    CHECK(tf_tree_update(tr, "world", "spin", &z, &big) == TF_TREE_OK);
    vizm_vec3 p = {1, 0, 0};
    CHECK(xform(tr, "world", "spin", p.x, p.y, p.z, &o) == TF_TREE_OK && PT(o, 0, 1, 0));
    /* clear */
    tf_tree_clear(tr);
    CHECK(tf_tree_frame_count(tr) == 0);
    CHECK(xform(tr, "world", "spin", 0, 0, 0, &o) == TF_TREE_ERR_UNKNOWN_FRAME);
}

static void test_full(void)
{
    tf_tree *tr = tf_tree_create(backing, sizeof backing);
    vizm_vec3 t = {0, 0, 0};
    char name[16];
    int ok = 0, full = 0;
    for (int i = 0; i < 40; i++) {
        snprintf(name, sizeof name, "f%d", i);
        int rc = tf_tree_update(tr, "root", name, &t, &QI);
        if (rc == TF_TREE_OK) ok++; else if (rc == TF_TREE_ERR_FULL) full++;
    }
    /* "root" ocupa 1 hueco; caben 31 hijos */
    CHECK(ok == 31 && full == 9 && tf_tree_frame_count(tr) == 32);
    /* actualizar uno existente sigue permitido con el árbol lleno */
    CHECK(tf_tree_update(tr, "root", "f0", &t, &QI) == TF_TREE_OK);
    /* padre nuevo + hijo existente necesita 1 hueco -> FULL y no modifica */
    CHECK(tf_tree_update(tr, "nuevo", "f0", &t, &QI) == TF_TREE_ERR_FULL);
    CHECK(tf_tree_frame_count(tr) == 32);
}

static msg_cdr_tf_message msg;

static void test_apply_message(void)
{
    tf_tree *tr = tf_tree_create(backing, sizeof backing);
    memset(&msg, 0, sizeof msg);
    msg.count = 3;
    strcpy(msg.items[0].frame_id, "odom");
    strcpy(msg.items[0].child_frame_id, "base_link");
    msg.items[0].translation[0] = 1.5; msg.items[0].translation[1] = -2.25;
    msg.items[0].rotation[3] = 1.0;
    strcpy(msg.items[1].frame_id, "base_link");
    strcpy(msg.items[1].child_frame_id, "laser");
    msg.items[1].translation[0] = 0.5;
    msg.items[1].rotation[3] = 1.0;
    /* tercero inválido: ciclo (laser -> odom cuando odom->base_link->laser) */
    strcpy(msg.items[2].frame_id, "laser");
    strcpy(msg.items[2].child_frame_id, "odom");
    msg.items[2].rotation[3] = 1.0;

    CHECK(tf_tree_apply_message(tr, &msg) == 2);
    CHECK(tf_tree_rejected(tr) == 1);
    vizm_vec3 o;
    CHECK(xform(tr, "odom", "laser", 0, 0, 0, &o) == TF_TREE_OK && PT(o, 2.0f, -2.25f, 0));
    CHECK(tf_tree_apply_message(NULL, &msg) == TF_TREE_ERR_INVALID_ARG);
    CHECK(tf_tree_apply_message(tr, NULL) == TF_TREE_ERR_INVALID_ARG);
}

int main(void)
{
    printf("== parity_test tf-tree [impl=%s] ==\n", IMPL_NAME);
    test_create();
    test_lookup_chain();
    test_errors();
    test_update_reparent();
    test_full();
    test_apply_message();
    if (failures) {
        printf("FALLARON %d comprobaciones [impl=%s]\n", failures, IMPL_NAME);
        return 1;
    }
    printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
    return 0;
}
