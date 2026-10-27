/**
 * parity_test.c — Batería de paridad del módulo `msg-schema`.
 *
 * El MISMO archivo se enlaza contra impl-c y contra impl-rust. Los datos son
 * fixtures de tests/gen_fixtures.py: mensajes de ROS2 Jazzy construidos y
 * serializados con `rosbags`, junto a su VOLCADO CANÓNICO calculado sobre el
 * objeto Python (independiente del CDR). Se comprueba:
 *   1. decode: el volcado del visitor == volcado esperado (24 tipos de mensaje)
 *   2. encode: re-codificar los eventos reproduce los bytes ORIGINALES
 *   3. recortes: cualquier payload truncado => TRUNCATED, nunca crash
 *   4. esquema: blobs inválidos rechazados; introspección de tipos/campos
 *   5. fuzz determinista (payloads y esquemas) con hash idéntico en C y Rust
 * Se ejecuta con el directorio de trabajo en la raíz del repo.
 */
#include "msg_schema.h"

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

#define FIX "modules/msg-schema/tests/fixtures/"

static uint8_t *load(const char *name, size_t *len)
{
    char path[256];
    snprintf(path, sizeof path, FIX "%s", name);
    FILE *f = fopen(path, "rb");
    if (!f) {
        printf("  FALLO no se pudo abrir %s (¿cwd = raíz del repo?)\n", path);
        failures++;
        return NULL;
    }
    fseek(f, 0, SEEK_END);
    long n = ftell(f);
    fseek(f, 0, SEEK_SET);
    uint8_t *buf = malloc((size_t)n + 1);
    if (fread(buf, 1, (size_t)n, f) != (size_t)n) {
        failures++;
    }
    buf[n] = 0;
    fclose(f);
    *len = (size_t)n;
    return buf;
}

/* ---------------------------------------------------------------- FNV */
static uint64_t fnv_bytes(uint64_t h, const uint8_t *p, size_t n)
{
    for (size_t i = 0; i < n; i++) {
        h ^= p[i];
        h *= 1099511628211ULL;
    }
    return h;
}

static uint64_t fnv_u64(uint64_t h, uint64_t v)
{
    uint8_t b[8];
    for (int i = 0; i < 8; i++) {
        b[i] = (uint8_t)(v >> (8 * i));
    }
    return fnv_bytes(h, b, 8);
}

/* ------------------------------------------------- visitor de volcado */
#define TEXT_CAP 65536
#define DEPTH 64
typedef struct {
    char *text;
    size_t tlen;
    char path[512];
    size_t plen;
    size_t restore[DEPTH];
    int is_array[DEPTH];
    uint32_t idx[DEPTH];
    int top;
} dump;

static void line(dump *d, const char *fmt, ...) __attribute__((format(printf, 2, 3)));
#include <stdarg.h>
static void line(dump *d, const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);
    d->tlen += (size_t)vsnprintf(d->text + d->tlen, TEXT_CAP - d->tlen, fmt, ap);
    va_end(ap);
    d->text[d->tlen++] = '\n';
    d->text[d->tlen] = 0;
}

static void path_push_name(dump *d, const char *name)
{
    if (d->plen) {
        d->path[d->plen++] = '.';
    }
    size_t n = strlen(name);
    memcpy(d->path + d->plen, name, n);
    d->plen += n;
    d->path[d->plen] = 0;
}

static void path_push_index(dump *d, uint32_t i)
{
    d->plen += (size_t)snprintf(d->path + d->plen, sizeof d->path - d->plen, "[%u]", i);
}

static int fmt_prim(char *out, size_t cap, int prim, uint64_t raw)
{
    switch (prim) {
    case MSG_PRIM_BOOL: return snprintf(out, cap, "%d", raw ? 1 : 0);
    case MSG_PRIM_U8: case MSG_PRIM_U16: case MSG_PRIM_U32: case MSG_PRIM_U64:
        return snprintf(out, cap, "%llu", (unsigned long long)raw);
    case MSG_PRIM_I8: return snprintf(out, cap, "%d", (int)(int8_t)raw);
    case MSG_PRIM_I16: return snprintf(out, cap, "%d", (int)(int16_t)raw);
    case MSG_PRIM_I32: return snprintf(out, cap, "%d", (int)(int32_t)raw);
    case MSG_PRIM_I64: return snprintf(out, cap, "%lld", (long long)(int64_t)raw);
    case MSG_PRIM_F32: {
        uint32_t u = (uint32_t)raw;
        float f;
        memcpy(&f, &u, 4);
        return snprintf(out, cap, "%.17g", (double)f);
    }
    default: {
        double v;
        memcpy(&v, &raw, 8);
        return snprintf(out, cap, "%.17g", v);
    }
    }
}

static int d_begin_struct(void *c, const char *name)
{
    dump *d = c;
    d->top++;
    d->restore[d->top] = d->plen;
    d->is_array[d->top] = 0;
    if (d->top == 0) {
        return 0; /* raíz */
    }
    if (name) {
        path_push_name(d, name);
    } else {
        path_push_index(d, d->idx[d->top - 1]++);
    }
    return 0;
}

static int d_end_struct(void *c)
{
    dump *d = c;
    d->plen = d->restore[d->top];
    d->path[d->plen] = 0;
    d->top--;
    return 0;
}

static int d_prim(void *c, const char *name, int prim, uint64_t raw)
{
    dump *d = c;
    size_t keep = d->plen;
    path_push_name(d, name);
    char v[64];
    fmt_prim(v, sizeof v, prim, raw);
    line(d, "%s=%s", d->path, v);
    d->plen = keep;
    d->path[keep] = 0;
    return 0;
}

static int d_string(void *c, const char *name, const uint8_t *s, uint32_t len)
{
    dump *d = c;
    size_t keep = d->plen;
    if (name) {
        path_push_name(d, name);
    } else {
        path_push_index(d, d->idx[d->top]++);
    }
    line(d, "%s=\"%.*s\"", d->path, (int)len, (const char *)s);
    d->plen = keep;
    d->path[keep] = 0;
    return 0;
}

static int d_prim_array(void *c, const char *name, int prim, const uint8_t *data, uint32_t count)
{
    dump *d = c;
    size_t keep = d->plen;
    path_push_name(d, name);
    line(d, "%s=[%u]#%016llx", d->path, count,
         (unsigned long long)fnv_bytes(14695981039346656037ULL, data, (size_t)count * msg_prim_size((msg_prim)prim)));
    d->plen = keep;
    d->path[keep] = 0;
    return 0;
}

static int d_begin_array(void *c, const char *name, uint32_t count)
{
    dump *d = c;
    d->top++;
    d->restore[d->top] = d->plen;
    d->is_array[d->top] = 1;
    d->idx[d->top] = 0;
    path_push_name(d, name);
    line(d, "%s=[%u]", d->path, count);
    return 0;
}

static int d_end_array(void *c)
{
    dump *d = c;
    d->plen = d->restore[d->top];
    d->path[d->plen] = 0;
    d->top--;
    return 0;
}

/* Los structs-elemento usan idx del array padre: begin_struct(NULL) con
 * top-1 siendo array. Para strings-elemento, `string(NULL)` usa idx[top]. */

static const msg_visitor DUMP_VIS = { d_begin_struct, d_end_struct, d_prim, d_string,
                                      d_prim_array, d_begin_array, d_end_array };

/* ----------------------------------------------- grabación + reproducción */
typedef enum { EV_BEGIN_STRUCT, EV_END_STRUCT, EV_PRIM, EV_STRING, EV_PRIM_ARRAY, EV_BEGIN_ARRAY, EV_END_ARRAY } ev_type;
typedef struct {
    ev_type type;
    int prim;
    uint64_t raw;
    const uint8_t *data;
    uint32_t count;
} event;

#define MAX_EVENTS 8192
static event events[MAX_EVENTS];
static int n_events;

static int rec(ev_type t, int prim, uint64_t raw, const uint8_t *data, uint32_t count)
{
    if (n_events >= MAX_EVENTS) {
        return 1;
    }
    events[n_events++] = (event){ t, prim, raw, data, count };
    return 0;
}
static int r_bs(void *c, const char *n) { (void)c; (void)n; return rec(EV_BEGIN_STRUCT, 0, 0, NULL, 0); }
static int r_es(void *c) { (void)c; return rec(EV_END_STRUCT, 0, 0, NULL, 0); }
static int r_p(void *c, const char *n, int p, uint64_t raw) { (void)c; (void)n; return rec(EV_PRIM, p, raw, NULL, 0); }
static int r_s(void *c, const char *n, const uint8_t *s, uint32_t l) { (void)c; (void)n; return rec(EV_STRING, 0, 0, s, l); }
static int r_pa(void *c, const char *n, int p, const uint8_t *d, uint32_t k) { (void)c; (void)n; return rec(EV_PRIM_ARRAY, p, 0, d, k); }
static int r_ba(void *c, const char *n, uint32_t k) { (void)c; (void)n; return rec(EV_BEGIN_ARRAY, 0, 0, NULL, k); }
static int r_ea(void *c) { (void)c; return rec(EV_END_ARRAY, 0, 0, NULL, 0); }
static const msg_visitor REC_VIS = { r_bs, r_es, r_p, r_s, r_pa, r_ba, r_ea };

static int cursor;
static int next_ev(ev_type want, const event **out)
{
    while (cursor < n_events && events[cursor].type == EV_END_ARRAY && want != EV_END_ARRAY) {
        cursor++; /* el encoder no anuncia el fin de un array */
    }
    if (cursor >= n_events || events[cursor].type != want) {
        return 1;
    }
    *out = &events[cursor++];
    return 0;
}
static int s_bs(void *c, const char *n) { (void)c; (void)n; const event *e; return next_ev(EV_BEGIN_STRUCT, &e); }
static int s_es(void *c) { (void)c; const event *e; return next_ev(EV_END_STRUCT, &e); }
static int s_p(void *c, const char *n, int p, uint64_t *raw)
{
    (void)c; (void)n; const event *e;
    if (next_ev(EV_PRIM, &e) || e->prim != p) return 1;
    *raw = e->raw;
    return 0;
}
static int s_s(void *c, const char *n, const uint8_t **s, uint32_t *l)
{
    (void)c; (void)n; const event *e;
    if (next_ev(EV_STRING, &e)) return 1;
    *s = e->data; *l = e->count;
    return 0;
}
static int s_pa(void *c, const char *n, int p, uint32_t fixed, const uint8_t **d, uint32_t *k)
{
    (void)c; (void)n; (void)fixed; const event *e;
    if (next_ev(EV_PRIM_ARRAY, &e) || e->prim != p) return 1;
    *d = e->data; *k = e->count;
    return 0;
}
static int s_al(void *c, const char *n, uint32_t fixed, uint32_t *k)
{
    (void)c; (void)n; (void)fixed; const event *e;
    if (next_ev(EV_BEGIN_ARRAY, &e)) return 1;
    *k = e->count;
    return 0;
}
/* el SOURCE no incluye end_array */
static const msg_source REPLAY_SRC = { s_bs, s_es, s_p, s_s, s_pa, s_al };

/* ---------------------------------------------------------- hash visitor */
static int h_bs(void *c, const char *n) { uint64_t *h = c; *h = fnv_u64(*h, 1 + (n ? strlen(n) : 0)); return 0; }
static int h_es(void *c) { uint64_t *h = c; *h = fnv_u64(*h, 2); return 0; }
static int h_p(void *c, const char *n, int p, uint64_t raw)
{
    uint64_t *h = c; *h = fnv_u64(fnv_u64(fnv_u64(*h, 3), (uint64_t)p + (n ? strlen(n) : 0)), raw); return 0;
}
static int h_s(void *c, const char *n, const uint8_t *s, uint32_t l)
{
    uint64_t *h = c; *h = fnv_bytes(fnv_u64(*h, 4 + (n ? 1 : 0)), s, l); return 0;
}
static int h_pa(void *c, const char *n, int p, const uint8_t *d, uint32_t k)
{
    uint64_t *h = c; (void)n;
    *h = fnv_bytes(fnv_u64(fnv_u64(*h, 5), k), d, (size_t)k * msg_prim_size((msg_prim)p)); return 0;
}
static int h_ba(void *c, const char *n, uint32_t k) { uint64_t *h = c; (void)n; *h = fnv_u64(fnv_u64(*h, 6), k); return 0; }
static int h_ea(void *c) { uint64_t *h = c; *h = fnv_u64(*h, 7); return 0; }
static const msg_visitor HASH_VIS = { h_bs, h_es, h_p, h_s, h_pa, h_ba, h_ea };

/* ------------------------------------------------------------- tests */
static msg_schema schema;
static uint8_t *schema_blob;
static size_t schema_len;

static char textbuf[TEXT_CAP];
static uint8_t outbuf[1 << 16];

typedef struct {
    char name[64];
    char type[96];
    uint8_t *file;
    size_t flen;
} tcase;
static tcase cases[64];
static int n_cases;

static void load_cases(void)
{
    size_t len;
    uint8_t *list = load("cases.txt", &len);
    if (!list) return;
    char *tok = strtok((char *)list, "\n");
    while (tok && n_cases < 64) {
        tcase *c = &cases[n_cases];
        snprintf(c->name, sizeof c->name, "%s", tok);
        char fn[128];
        snprintf(fn, sizeof fn, "%s.type", tok);
        size_t tl;
        uint8_t *t = load(fn, &tl);
        if (t) {
            t[strcspn((char *)t, "\n")] = 0;
            snprintf(c->type, sizeof c->type, "%s", (char *)t);
            free(t);
        }
        snprintf(fn, sizeof fn, "%s.bin", tok);
        c->file = load(fn, &c->flen);
        n_cases++;
        tok = strtok(NULL, "\n");
    }
    free(list);
}

static void test_schema_api(void)
{
    CHECK(msg_schema_type_count(&schema) > 20);
    uint32_t t, nf;
    CHECK(msg_schema_find_type(&schema, "geometry_msgs/msg/Twist", &t) == MSG_SCHEMA_OK);
    CHECK(msg_schema_find_type(&schema, "no/existe", &t) == MSG_SCHEMA_ERR_UNKNOWN_TYPE);
    CHECK(msg_schema_find_type(&schema, "geometry_msgs/msg/Twist", &t) == MSG_SCHEMA_OK);
    const char *name;
    CHECK(msg_schema_type_name(&schema, t, &name) == MSG_SCHEMA_OK && strcmp(name, "geometry_msgs/msg/Twist") == 0);
    CHECK(msg_schema_field_count(&schema, t, &nf) == MSG_SCHEMA_OK && nf == 2);
    msg_field_info f;
    CHECK(msg_schema_field(&schema, t, 1, &f) == MSG_SCHEMA_OK);
    CHECK(strcmp(f.name, "angular") == 0 && f.kind == MSG_KIND_STRUCT && f.array == MSG_ARRAY_NONE);
    uint32_t v3 = f.type_idx;
    CHECK(msg_schema_field(&schema, v3, 2, &f) == MSG_SCHEMA_OK);
    CHECK(strcmp(f.name, "z") == 0 && f.kind == MSG_KIND_PRIM && f.prim == MSG_PRIM_F64);
    CHECK(msg_schema_field(&schema, v3, 3, &f) == MSG_SCHEMA_ERR_INVALID_ARG);
    CHECK(msg_schema_field_count(&schema, 99999, &nf) == MSG_SCHEMA_ERR_UNKNOWN_TYPE);
    /* Imu: array fijo de 9 doubles */
    CHECK(msg_schema_find_type(&schema, "sensor_msgs/msg/Imu", &t) == MSG_SCHEMA_OK);
    CHECK(msg_schema_field(&schema, t, 2, &f) == MSG_SCHEMA_OK);
    CHECK(strcmp(f.name, "orientation_covariance") == 0 && f.array == MSG_ARRAY_FIXED && f.array_len == 9);
    CHECK(msg_prim_size(MSG_PRIM_I16) == 2 && msg_prim_size(MSG_PRIM_F64) == 8 && msg_prim_size((msg_prim)99) == 0);
}

static void test_bad_schemas(void)
{
    msg_schema s;
    CHECK(msg_schema_init(NULL, schema_blob, schema_len) == MSG_SCHEMA_ERR_INVALID_ARG);
    CHECK(msg_schema_init(&s, NULL, 10) == MSG_SCHEMA_ERR_INVALID_ARG);
    CHECK(msg_schema_init(&s, schema_blob, 10) == MSG_SCHEMA_ERR_BAD_SCHEMA);
    CHECK(msg_schema_init(&s, schema_blob, schema_len - 1) == MSG_SCHEMA_ERR_BAD_SCHEMA);
    uint8_t *copy = malloc(schema_len);
    memcpy(copy, schema_blob, schema_len);
    copy[0] = 'X';
    CHECK(msg_schema_init(&s, copy, schema_len) == MSG_SCHEMA_ERR_BAD_SCHEMA);
    memcpy(copy, schema_blob, schema_len);
    copy[4] = 9; /* versión */
    CHECK(msg_schema_init(&s, copy, schema_len) == MSG_SCHEMA_ERR_BAD_SCHEMA);
    memcpy(copy, schema_blob, schema_len);
    copy[32 + 8] = 0; /* field_count del primer tipo = 0 */
    copy[32 + 9] = 0; copy[32 + 10] = 0; copy[32 + 11] = 0;
    CHECK(msg_schema_init(&s, copy, schema_len) == MSG_SCHEMA_ERR_BAD_SCHEMA);
    free(copy);
}

static void test_cases(void)
{
    for (int i = 0; i < n_cases; i++) {
        tcase *c = &cases[i];
        if (!c->file) continue;
        char fn[128];
        snprintf(fn, sizeof fn, "%s.dump", c->name);
        size_t el;
        uint8_t *expected = load(fn, &el);
        const uint8_t *payload = c->file + 4;
        size_t plen = c->flen - 4;
        uint32_t t;
        if (msg_schema_find_type(&schema, c->type, &t) != MSG_SCHEMA_OK) {
            printf("  FALLO tipo %s no está en el esquema\n", c->type);
            failures++;
            free(expected);
            continue;
        }

        /* 1. decode == volcado esperado */
        dump *d = calloc(1, sizeof *d);
        d->text = textbuf;
        textbuf[0] = 0;
        d->top = -1;
        size_t consumed = 0;
        int rc = msg_schema_decode(&schema, t, payload, plen, &DUMP_VIS, d, &consumed);
        if (rc != MSG_SCHEMA_OK || consumed != plen || !expected || strcmp(textbuf, (char *)expected) != 0) {
            failures++;
            printf("  FALLO decode %s rc=%d consumed=%zu/%zu\n", c->name, rc, consumed, plen);
            if (expected && strcmp(textbuf, (char *)expected) != 0) {
                printf("--- obtenido ---\n%.600s\n--- esperado ---\n%.600s\n", textbuf, (char *)expected);
            }
        }
        free(d);

        /* 2. encode(eventos) == bytes originales */
        n_events = 0;
        CHECK(msg_schema_decode(&schema, t, payload, plen, &REC_VIS, NULL, NULL) == MSG_SCHEMA_OK);
        cursor = 0;
        size_t written = 0;
        rc = msg_schema_encode(&schema, t, &REPLAY_SRC, NULL, outbuf, sizeof outbuf, &written);
        if (rc != MSG_SCHEMA_OK || written != plen || memcmp(outbuf, payload, plen) != 0) {
            failures++;
            printf("  FALLO encode %s rc=%d written=%zu esperado=%zu\n", c->name, rc, written, plen);
        }
        /* buffer de salida demasiado pequeño en todas las longitudes */
        for (size_t cap = 0; cap < plen; cap++) {
            cursor = 0;
            if (msg_schema_encode(&schema, t, &REPLAY_SRC, NULL, outbuf, cap, &written) != MSG_SCHEMA_ERR_NO_SPACE) {
                failures++;
                printf("  FALLO encode %s cap=%zu no dio NO_SPACE\n", c->name, cap);
                break;
            }
        }

        /* 3. recortes del payload => TRUNCATED */
        for (size_t cut = 0; cut < plen; cut++) {
            if (msg_schema_decode(&schema, t, payload, cut, &HASH_VIS,
                                  &(uint64_t){ 1 }, NULL) != MSG_SCHEMA_ERR_TRUNCATED) {
                failures++;
                printf("  FALLO decode %s recortado a %zu no dio TRUNCATED\n", c->name, cut);
                break;
            }
        }
        free(expected);
    }
}

static void test_errors(void)
{
    uint32_t t;
    CHECK(msg_schema_find_type(&schema, "std_msgs/msg/Int16", &t) == MSG_SCHEMA_OK);
    uint8_t buf[2] = { 1, 0 };
    CHECK(msg_schema_decode(&schema, t, buf, 2, NULL, NULL, NULL) == MSG_SCHEMA_ERR_INVALID_ARG);
    CHECK(msg_schema_decode(&schema, t, NULL, 2, &HASH_VIS, NULL, NULL) == MSG_SCHEMA_ERR_INVALID_ARG);
    CHECK(msg_schema_decode(&schema, 99999, buf, 2, &HASH_VIS, NULL, NULL) == MSG_SCHEMA_ERR_UNKNOWN_TYPE);
    /* un callback que devuelve != 0 aborta */
    static const msg_visitor abort_vis = { NULL, NULL, NULL, NULL, NULL, NULL, NULL };
    CHECK(msg_schema_decode(&schema, t, buf, 2, &abort_vis, NULL, NULL) == MSG_SCHEMA_OK); /* callbacks NULL: se ignoran */
    msg_visitor v = { r_bs, NULL, NULL, NULL, NULL, NULL, NULL };
    n_events = MAX_EVENTS; /* rec() devolverá 1 */
    CHECK(msg_schema_decode(&schema, t, buf, 2, &v, NULL, NULL) == MSG_SCHEMA_ERR_ABORTED);
    n_events = 0;

    /* encode: valores inválidos */
    uint32_t jt;
    CHECK(msg_schema_find_type(&schema, "sensor_msgs/msg/NavSatFix", &jt) == MSG_SCHEMA_OK);
    n_events = 0;
    CHECK(msg_schema_encode(&schema, jt, &REPLAY_SRC, NULL, outbuf, sizeof outbuf, NULL) == MSG_SCHEMA_ERR_ABORTED); /* sin eventos */
    msg_source nosrc = { NULL, NULL, NULL, NULL, NULL, NULL };
    CHECK(msg_schema_encode(&schema, t, &nosrc, NULL, outbuf, sizeof outbuf, NULL) == MSG_SCHEMA_ERR_INVALID_ARG);
}

/* ------------------------------------------------------------- fuzz */
static uint32_t rng_state = 987654321;
static uint32_t rng(void)
{
    rng_state = rng_state * 1664525u + 1013904223u;
    return rng_state >> 8;
}

#define FUZZ_EXPECTED 11457115168711874726ULL /* hash de referencia; si cambian fixtures o RNG, recalcular */

static void test_fuzz(void)
{
    uint64_t h = 14695981039346656037ULL;
    /* a) payloads corruptos con el esquema bueno */
    for (int i = 0; i < n_cases; i++) {
        tcase *c = &cases[i];
        if (!c->file) continue;
        uint32_t t;
        if (msg_schema_find_type(&schema, c->type, &t) != MSG_SCHEMA_OK) continue;
        size_t plen = c->flen - 4;
        uint8_t *mut = malloc(plen + 1);
        for (int it = 0; it < 300; it++) {
            memcpy(mut, c->file + 4, plen);
            int flips = 1 + (int)(rng() % 3);
            for (int k = 0; k < flips && plen; k++) {
                mut[rng() % plen] = (uint8_t)rng();
            }
            size_t l = (rng() % 4 == 0) ? (size_t)(rng() % (plen + 1)) : plen;
            uint64_t eh = 1469598103934665603ULL;
            size_t used = 0;
            int rc = msg_schema_decode(&schema, t, mut, l, &HASH_VIS, &eh, &used);
            h = fnv_u64(fnv_u64(fnv_u64(h, (uint64_t)(int64_t)rc), eh), used);
        }
        free(mut);
    }
    /* b) esquemas corruptos: init y, si valida, decode de todos los casos */
    uint8_t *sb = malloc(schema_len);
    for (int it = 0; it < 400; it++) {
        memcpy(sb, schema_blob, schema_len);
        int flips = 1 + (int)(rng() % 4);
        for (int k = 0; k < flips; k++) {
            sb[rng() % schema_len] = (uint8_t)rng();
        }
        msg_schema ms;
        int rc = msg_schema_init(&ms, sb, schema_len);
        h = fnv_u64(h, (uint64_t)(int64_t)rc);
        if (rc != MSG_SCHEMA_OK) continue;
        for (int i = 0; i < n_cases; i += 3) {
            tcase *c = &cases[i];
            if (!c->file) continue;
            uint32_t t = 0;
            msg_schema_find_type(&ms, c->type, &t); /* si no existe, t = 0 */
            uint64_t eh = 1469598103934665603ULL;
            int r2 = msg_schema_decode(&ms, t, c->file + 4, c->flen - 4, &HASH_VIS, &eh, NULL);
            h = fnv_u64(fnv_u64(h, (uint64_t)(int64_t)r2), eh);
        }
    }
    free(sb);
    printf("  fuzz hash = %llu\n", (unsigned long long)h);
    CHECK(h == FUZZ_EXPECTED);
}

int main(void)
{
    printf("== parity_test msg-schema [impl=%s] ==\n", IMPL_NAME);
    schema_blob = load("schema.rsch", &schema_len);
    if (!schema_blob || msg_schema_init(&schema, schema_blob, schema_len) != MSG_SCHEMA_OK) {
        printf("  FALLO no se pudo cargar el esquema\n");
        return 1;
    }
    load_cases();
    CHECK(n_cases >= 24);
    test_schema_api();
    test_bad_schemas();
    test_cases();
    test_errors();
    test_fuzz();
    if (failures) {
        printf("FALLARON %d comprobaciones [impl=%s]\n", failures, IMPL_NAME);
        return 1;
    }
    printf("OK: todos los casos pasaron [impl=%s]\n", IMPL_NAME);
    return 0;
}
