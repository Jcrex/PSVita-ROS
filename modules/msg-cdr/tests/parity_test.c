/**
 * parity_test.c — Batería de paridad del módulo `msg-cdr`.
 * El MISMO archivo se enlaza contra impl-c y contra impl-rust. Los datos de
 * entrada son fixtures CDR generadas con las definiciones de ROS2 Jazzy
 * (tests/gen_fixtures.py); los valores esperados están escritos a mano aquí.
 * Se ejecuta con el directorio de trabajo en la raíz del repo.
 */
#include "msg_cdr.h"

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
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

#define NEAR(a, b) (fabs((double)(a) - (double)(b)) < 1e-9)

#define FIX_DIR "modules/msg-cdr/tests/fixtures/"

/* Carga un fixture completo (con encapsulación). Devuelve malloc'd o NULL. */
static uint8_t *load(const char *name, size_t *len)
{
    char path[256];
    snprintf(path, sizeof path, FIX_DIR "%s", name);
    FILE *f = fopen(path, "rb");
    if (!f) {
        printf("  FALLO no se pudo abrir %s (¿cwd = raíz del repo?)\n", path);
        failures++;
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)n);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        failures++;
    }
    fclose(f);
    *len = (size_t)n;
    return buf;
}

/* Carga y quita la encapsulación; `*base` es el malloc a liberar. */
static const uint8_t *load_payload(const char *name, size_t *plen, uint8_t **base)
{
    size_t len = 0;
    *base = load(name, &len);
    if (!*base) {
        *plen = 0;
        return NULL;
    }
    const uint8_t *p = NULL;
    CHECK(msg_cdr_strip_encapsulation(*base, len, &p, plen) == MSG_CDR_OK);
    return p;
}

static void test_encapsulation(void)
{
    const uint8_t le[] = { 0, 1, 0, 0, 0xAA };
    const uint8_t be[] = { 0, 0, 0, 0 };
    const uint8_t bad[] = { 7, 7, 0, 0 };
    const uint8_t *p;
    size_t pl;
    CHECK(msg_cdr_strip_encapsulation(le, sizeof le, &p, &pl) == MSG_CDR_OK);
    CHECK(p == le + 4 && pl == 1);
    CHECK(msg_cdr_strip_encapsulation(be, sizeof be, &p, &pl) == MSG_CDR_ERR_UNSUPPORTED);
    CHECK(msg_cdr_strip_encapsulation(bad, sizeof bad, &p, &pl) == MSG_CDR_ERR_INVALID_ARG);
    CHECK(msg_cdr_strip_encapsulation(le, 3, &p, &pl) == MSG_CDR_ERR_TRUNCATED);
    CHECK(msg_cdr_strip_encapsulation(NULL, 4, &p, &pl) == MSG_CDR_ERR_INVALID_ARG);
}

static void test_args(void)
{
    msg_cdr_tf_message m;
    uint8_t b[8] = {0};
    CHECK(msg_cdr_decode_tf_message(NULL, 8, &m) == MSG_CDR_ERR_INVALID_ARG);
    CHECK(msg_cdr_decode_tf_message(b, 8, NULL) == MSG_CDR_ERR_INVALID_ARG);
}

static msg_cdr_tf_message tfm; /* ~6 KB: estático para no cargar la pila */

static void test_tf(void)
{
    size_t pl;
    uint8_t *base;
    const uint8_t *p = load_payload("tf_two.bin", &pl, &base);
    if (!p) return;
    CHECK(msg_cdr_decode_tf_message(p, pl, &tfm) == MSG_CDR_OK);
    CHECK(tfm.count == 2 && tfm.dropped == 0 && tfm.strings_truncated == 0);
    CHECK(tfm.items[0].stamp.sec == 1234 && tfm.items[0].stamp.nanosec == 5678);
    CHECK(strcmp(tfm.items[0].frame_id, "odom") == 0);
    CHECK(strcmp(tfm.items[0].child_frame_id, "base_link") == 0);
    CHECK(NEAR(tfm.items[0].translation[0], 1.5));
    CHECK(NEAR(tfm.items[0].translation[1], -2.25));
    CHECK(NEAR(tfm.items[0].translation[2], 0.5));
    CHECK(NEAR(tfm.items[0].rotation[2], 0.70710678));
    CHECK(NEAR(tfm.items[0].rotation[3], 0.70710678));
    CHECK(strcmp(tfm.items[1].frame_id, "base_link") == 0);
    CHECK(strcmp(tfm.items[1].child_frame_id, "laser") == 0);
    CHECK(NEAR(tfm.items[1].translation[0], 0.1));
    CHECK(NEAR(tfm.items[1].translation[2], 0.2));
    CHECK(NEAR(tfm.items[1].rotation[3], 1.0));

    /* truncado: cualquier recorte del payload debe dar TRUNCATED, nunca crash */
    for (size_t cut = 0; cut < pl; cut++) {
        int rc = msg_cdr_decode_tf_message(p, cut, &tfm);
        if (rc != MSG_CDR_ERR_TRUNCATED) {
            failures++;
            printf("  FALLO tf recortado a %zu bytes devolvió %d\n", cut, rc);
            break;
        }
    }
    free(base);

    p = load_payload("tf_empty.bin", &pl, &base);
    if (p) {
        CHECK(msg_cdr_decode_tf_message(p, pl, &tfm) == MSG_CDR_OK && tfm.count == 0);
        free(base);
    }

    p = load_payload("tf_long_names.bin", &pl, &base);
    if (p) {
        CHECK(msg_cdr_decode_tf_message(p, pl, &tfm) == MSG_CDR_OK);
        CHECK(tfm.count == 1 && tfm.strings_truncated == 2);
        CHECK(strlen(tfm.items[0].frame_id) == 63 && tfm.items[0].frame_id[0] == 'p');
        CHECK(strlen(tfm.items[0].child_frame_id) == 63 && tfm.items[0].child_frame_id[62] == 'c');
        CHECK(NEAR(tfm.items[0].translation[2], 3.0));
        free(base);
    }

    p = load_payload("tf_many.bin", &pl, &base);
    if (p) {
        CHECK(msg_cdr_decode_tf_message(p, pl, &tfm) == MSG_CDR_ERR_CAPACITY);
        CHECK(tfm.count == 32 && tfm.dropped == 8);
        CHECK(strcmp(tfm.items[31].child_frame_id, "link_31") == 0);
        CHECK(NEAR(tfm.items[31].translation[0], 31.0));
        free(base);
    }
}

static msg_cdr_joint_state js;

static void test_joints(void)
{
    size_t pl;
    uint8_t *base;
    const uint8_t *p = load_payload("joints.bin", &pl, &base);
    if (!p) return;
    CHECK(msg_cdr_decode_joint_state(p, pl, &js) == MSG_CDR_OK);
    CHECK(js.stamp.sec == 7 && js.stamp.nanosec == 8 && js.frame_id[0] == '\0');
    CHECK(js.name_count == 3 && strcmp(js.names[0], "wheel_left") == 0);
    CHECK(strcmp(js.names[1], "wheel_right") == 0 && strcmp(js.names[2], "arm_joint_1") == 0);
    CHECK(js.position_count == 3 && NEAR(js.position[0], 0.5) &&
          NEAR(js.position[1], -1.25) && NEAR(js.position[2], 3.0));
    CHECK(js.velocity_count == 0);
    CHECK(js.effort_count == 3 && NEAR(js.effort[0], 0.125) &&
          NEAR(js.effort[1], 0.25) && NEAR(js.effort[2], 0.375));
    CHECK(js.dropped == 0);
    for (size_t cut = 0; cut < pl; cut++) {
        if (msg_cdr_decode_joint_state(p, cut, &js) != MSG_CDR_ERR_TRUNCATED) {
            failures++;
            printf("  FALLO joints recortado a %zu\n", cut);
            break;
        }
    }
    free(base);

    p = load_payload("joints_many.bin", &pl, &base);
    if (p) {
        CHECK(msg_cdr_decode_joint_state(p, pl, &js) == MSG_CDR_ERR_CAPACITY);
        CHECK(js.name_count == 32 && js.position_count == 32);
        CHECK(js.dropped == 4); /* 2 nombres + 2 posiciones */
        CHECK(strcmp(js.names[31], "j31") == 0 && NEAR(js.position[31], 31.0));
        CHECK(strcmp(js.frame_id, "base") == 0);
        free(base);
    }
}

static void test_map(void)
{
    size_t pl;
    uint8_t *base;
    const uint8_t *p = load_payload("map_4x4.bin", &pl, &base);
    if (!p) return;
    msg_cdr_occupancy_grid g;
    CHECK(msg_cdr_decode_occupancy_grid(p, pl, &g) == MSG_CDR_OK);
    CHECK(g.stamp.sec == 100 && strcmp(g.frame_id, "map") == 0);
    CHECK(g.map_load_time.sec == 50 && g.map_load_time.nanosec == 60);
    CHECK(NEAR(g.resolution, 0.5) && g.width == 4 && g.height == 4);
    CHECK(NEAR(g.origin_position[0], -1.0) && NEAR(g.origin_position[1], -2.0) &&
          NEAR(g.origin_position[2], 0.0));
    CHECK(NEAR(g.origin_orientation[3], 1.0));
    CHECK(g.data_len == 16 && g.data != NULL);
    static const int8_t expect[16] = { -1, 0, 100, 50, -1, -1, 0, 0, 100, 100, 25, 75, 0, 1, 2, 99 };
    CHECK(g.data && memcmp(g.data, expect, 16) == 0);
    /* cero copias: el puntero cae dentro del buffer original */
    CHECK((const uint8_t *)g.data >= p && (const uint8_t *)g.data + 16 <= p + pl);
    for (size_t cut = 0; cut < pl; cut++) {
        if (msg_cdr_decode_occupancy_grid(p, cut, &g) != MSG_CDR_ERR_TRUNCATED) {
            failures++;
            printf("  FALLO mapa recortado a %zu\n", cut);
            break;
        }
    }
    free(base);
}

static msg_cdr_marker mk;

static void test_marker(void)
{
    size_t pl;
    uint8_t *base;
    const uint8_t *p = load_payload("marker_cube.bin", &pl, &base);
    if (!p) return;
    CHECK(msg_cdr_decode_marker(p, pl, &mk) == MSG_CDR_OK);
    CHECK(mk.stamp.sec == 9 && mk.stamp.nanosec == 10);
    CHECK(strcmp(mk.frame_id, "base_link") == 0 && strcmp(mk.ns, "robot") == 0);
    CHECK(mk.id == 7 && mk.type == 1 && mk.action == 0 && mk.frame_locked == 1);
    CHECK(NEAR(mk.position[0], 1.0) && NEAR(mk.position[1], 2.0) && NEAR(mk.position[2], 3.0));
    CHECK(NEAR(mk.orientation[3], 1.0));
    CHECK(NEAR(mk.scale[0], 0.5) && NEAR(mk.scale[2], 0.5));
    CHECK(NEAR(mk.color[0], 1.0) && NEAR(mk.color[1], 0.5) && NEAR(mk.color[2], 0.25) &&
          NEAR(mk.color[3], 1.0));
    CHECK(mk.lifetime.sec == 3 && mk.lifetime.nanosec == 500);
    CHECK(mk.point_count == 0 && mk.color_count == 0);
    free(base);

    p = load_payload("marker_line.bin", &pl, &base);
    if (!p) return;
    CHECK(msg_cdr_decode_marker(p, pl, &mk) == MSG_CDR_OK);
    CHECK(strcmp(mk.ns, "path") == 0 && mk.id == 8 && mk.type == 4 && mk.frame_locked == 0);
    CHECK(mk.point_count == 3 && mk.color_count == 3);
    CHECK(NEAR(mk.points[1][0], 1.0) && NEAR(mk.points[1][1], 0.5) && NEAR(mk.points[1][2], 0.25));
    CHECK(NEAR(mk.points[2][0], 2.0) && NEAR(mk.points[2][2], 0.5));
    CHECK(NEAR(mk.colors[0][0], 1.0) && NEAR(mk.colors[1][1], 1.0) && NEAR(mk.colors[2][3], 0.5));
    /* recortes dentro de la parte que se lee deben dar TRUNCATED; el resto
     * (textura, text...) se ignora, así que recortar ahí NO es error */
    int saw_trunc = 0;
    for (size_t cut = 0; cut < pl; cut++) {
        int rc = msg_cdr_decode_marker(p, cut, &mk);
        if (rc == MSG_CDR_ERR_TRUNCATED) {
            saw_trunc = 1;
        } else if (rc == MSG_CDR_OK) {
            break; /* ya se leyó todo lo que interesa: de aquí en adelante OK */
        } else {
            failures++;
            printf("  FALLO marker recortado a %zu devolvió %d\n", cut, rc);
            break;
        }
    }
    CHECK(saw_trunc);
    free(base);
}

/* ---- Fuzz determinista: mismas mutaciones → mismos códigos y contadores en
 * C y Rust (el hash FNV-1a debe coincidir con la constante). Garantiza que
 * ninguna entrada corrupta provoque crash ni divergencia. ---- */
static uint64_t fnv(uint64_t h, uint64_t v)
{
    for (int i = 0; i < 8; i++) {
        h ^= (v >> (8 * i)) & 0xFF;
        h *= 1099511628211ULL;
    }
    return h;
}

static uint32_t rng_state = 12345;
static uint32_t rng(void)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state >> 8;
}

static uint64_t fuzz_hash(void)
{
    static const char *names[] = { "tf_two.bin", "tf_many.bin", "joints.bin",
        "joints_many.bin", "map_4x4.bin", "marker_cube.bin", "marker_line.bin" };
    uint64_t h = 14695981039346656037ULL;
    for (unsigned f = 0; f < sizeof names / sizeof names[0]; f++) {
        size_t pl;
        uint8_t *base;
        const uint8_t *p = load_payload(names[f], &pl, &base);
        if (!p) continue;
        uint8_t *mut = malloc(pl);
        for (int it = 0; it < 4000; it++) {
            memcpy(mut, p, pl);
            int flips = 1 + (int)(rng() % 3);
            for (int k = 0; k < flips; k++) {
                mut[rng() % pl] = (uint8_t)rng();
            }
            size_t l = (rng() % 4 == 0) ? (size_t)(rng() % (pl + 1)) : pl;
            int rc;
            switch (f) {
            case 0: case 1:
                rc = msg_cdr_decode_tf_message(mut, l, &tfm);
                h = fnv(h, tfm.count); h = fnv(h, tfm.dropped); h = fnv(h, tfm.strings_truncated);
                break;
            case 2: case 3:
                rc = msg_cdr_decode_joint_state(mut, l, &js);
                h = fnv(h, js.name_count); h = fnv(h, js.position_count);
                h = fnv(h, js.dropped); h = fnv(h, js.strings_truncated);
                break;
            case 4: {
                msg_cdr_occupancy_grid g;
                rc = msg_cdr_decode_occupancy_grid(mut, l, &g);
                h = fnv(h, g.width); h = fnv(h, g.height); h = fnv(h, g.data_len);
                break;
            }
            default:
                rc = msg_cdr_decode_marker(mut, l, &mk);
                h = fnv(h, mk.point_count); h = fnv(h, mk.color_count);
                h = fnv(h, mk.points_dropped); h = fnv(h, (uint64_t)(uint32_t)mk.type);
                break;
            }
            h = fnv(h, (uint64_t)(int64_t)rc);
        }
        free(mut);
        free(base);
    }
    return h;
}

#define FUZZ_EXPECTED 2437122111620109976ULL /* hash de referencia; si cambian fixtures o RNG, recalcular */

static void test_fuzz(void)
{
    uint64_t h = fuzz_hash();
    printf("  fuzz hash = %llu\n", (unsigned long long)h);
    CHECK(h == FUZZ_EXPECTED);
}

int main(void)
{
    printf("== parity_test msg-cdr [impl=%s] ==\n", IMPL_NAME);
    test_encapsulation();
    test_args();
    test_tf();
    test_joints();
    test_map();
    test_marker();
    test_fuzz();
    if (failures) {
        printf("FALLARON %d comprobaciones [impl=%s]\n", failures, IMPL_NAME);
        return 1;
    }
    printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
    return 0;
}
