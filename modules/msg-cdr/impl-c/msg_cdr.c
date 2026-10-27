/**
 * msg_cdr.c — Implementación C11 del contrato include/msg_cdr.h.
 *
 * Lectura con un "cursor" sobre el buffer. Las lecturas ensamblan los bytes
 * a mano en little-endian: no dependen de la endianness ni de la alineación
 * del buffer de entrada (que NO tiene por qué estar alineado en memoria).
 */
#include "msg_cdr.h"

#include <string.h>

_Static_assert(sizeof(msg_cdr_transform) == 192, "layout msg_cdr_transform");
_Static_assert(sizeof(msg_cdr_tf_message) == 16 + 32 * 192, "layout tf_message");
_Static_assert(sizeof(msg_cdr_joint_state) == 2912, "layout joint_state");
_Static_assert(sizeof(msg_cdr_marker) == 2840, "layout marker");

typedef struct {
    const uint8_t *b;
    size_t len;
    size_t pos;
} cur;

#define TRY(x)                      \
    do {                            \
        int try_rc_ = (x);          \
        if (try_rc_ != MSG_CDR_OK) {\
            return try_rc_;         \
        }                           \
    } while (0)

/* Salta a la siguiente posición múltiplo de `a` (relativa al inicio de b). */
static int align(cur *c, size_t a)
{
    size_t p = (c->pos + (a - 1)) & ~(a - 1);
    if (p > c->len) {
        return MSG_CDR_ERR_TRUNCATED;
    }
    c->pos = p;
    return MSG_CDR_OK;
}

static int need(const cur *c, size_t n)
{
    return (c->len - c->pos >= n) ? MSG_CDR_OK : MSG_CDR_ERR_TRUNCATED;
}

static int rd_u32(cur *c, uint32_t *v)
{
    TRY(align(c, 4));
    TRY(need(c, 4));
    const uint8_t *p = c->b + c->pos;
    *v = (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) |
         ((uint32_t)p[3] << 24);
    c->pos += 4;
    return MSG_CDR_OK;
}

static int rd_i32(cur *c, int32_t *v)
{
    uint32_t u;
    TRY(rd_u32(c, &u));
    memcpy(v, &u, sizeof u); /* reinterpreta bits (complemento a dos) */
    return MSG_CDR_OK;
}

static int rd_f32(cur *c, float *v)
{
    uint32_t u;
    TRY(rd_u32(c, &u));
    memcpy(v, &u, sizeof u);
    return MSG_CDR_OK;
}

static int rd_f64(cur *c, double *v)
{
    TRY(align(c, 8));
    TRY(need(c, 8));
    const uint8_t *p = c->b + c->pos;
    uint64_t u = 0;
    for (int i = 7; i >= 0; i--) {
        u = (u << 8) | p[i];
    }
    memcpy(v, &u, sizeof u);
    c->pos += 8;
    return MSG_CDR_OK;
}

static int rd_bool(cur *c, uint32_t *v)
{
    TRY(need(c, 1));
    *v = c->b[c->pos] != 0;
    c->pos += 1;
    return MSG_CDR_OK;
}

static int rd_time(cur *c, msg_cdr_time *t)
{
    TRY(rd_i32(c, &t->sec));
    return rd_u32(c, &t->nanosec);
}

/* String CDR: u32 longitud (incluye el NUL) + bytes. dst=NULL => solo saltar. */
static int rd_str(cur *c, char *dst, size_t cap, uint32_t *truncated)
{
    uint32_t len;
    TRY(rd_u32(c, &len));
    TRY(need(c, len));
    if (dst != NULL) {
        size_t content = len > 0 ? (size_t)len - 1 : 0;
        size_t n = content < cap - 1 ? content : cap - 1;
        memcpy(dst, c->b + c->pos, n);
        dst[n] = '\0';
        if (content > cap - 1) {
            (*truncated)++;
        }
    }
    c->pos += len;
    return MSG_CDR_OK;
}

static int rd_f64n(cur *c, double *v, int n)
{
    for (int i = 0; i < n; i++) {
        TRY(rd_f64(c, &v[i]));
    }
    return MSG_CDR_OK;
}

/* Longitud de secuencia con comprobación de cordura: cada elemento ocupa al
 * menos 1 byte, así un contador absurdo no provoca bucles largos. */
static int rd_seq_len(cur *c, uint32_t *n)
{
    TRY(rd_u32(c, n));
    if (*n > c->len - c->pos) {
        return MSG_CDR_ERR_TRUNCATED;
    }
    return MSG_CDR_OK;
}

static int rd_header(cur *c, msg_cdr_time *stamp, char *frame, uint32_t *trunc)
{
    TRY(rd_time(c, stamp));
    return rd_str(c, frame, MSG_CDR_NAME_MAX, trunc);
}

static int check_args(const uint8_t *buf, const void *out)
{
    return (buf == NULL || out == NULL) ? MSG_CDR_ERR_INVALID_ARG : MSG_CDR_OK;
}

/* ------------------------------------------------------------------ API */

int msg_cdr_strip_encapsulation(const uint8_t *buf, size_t len,
                                const uint8_t **payload, size_t *payload_len)
{
    if (buf == NULL || payload == NULL || payload_len == NULL) {
        return MSG_CDR_ERR_INVALID_ARG;
    }
    if (len < 4) {
        return MSG_CDR_ERR_TRUNCATED;
    }
    if (buf[0] != 0) {
        return MSG_CDR_ERR_INVALID_ARG;
    }
    if (buf[1] == 0x00) {
        return MSG_CDR_ERR_UNSUPPORTED; /* CDR_BE */
    }
    if (buf[1] != 0x01) {
        return MSG_CDR_ERR_INVALID_ARG; /* ni CDR_LE ni CDR_BE */
    }
    *payload = buf + 4;
    *payload_len = len - 4;
    return MSG_CDR_OK;
}

static int rd_transform(cur *c, msg_cdr_transform *t, uint32_t *trunc)
{
    TRY(rd_header(c, &t->stamp, t->frame_id, trunc));
    TRY(rd_str(c, t->child_frame_id, MSG_CDR_NAME_MAX, trunc));
    TRY(rd_f64n(c, t->translation, 3));
    return rd_f64n(c, t->rotation, 4);
}

int msg_cdr_decode_tf_message(const uint8_t *buf, size_t len, msg_cdr_tf_message *out)
{
    TRY(check_args(buf, out));
    memset(out, 0, sizeof *out);
    cur c = { buf, len, 0 };
    uint32_t n;
    TRY(rd_seq_len(&c, &n));
    msg_cdr_transform scratch;
    for (uint32_t i = 0; i < n; i++) {
        msg_cdr_transform *dst = (i < MSG_CDR_MAX_TRANSFORMS) ? &out->items[i] : &scratch;
        TRY(rd_transform(&c, dst, &out->strings_truncated));
    }
    out->count = n < MSG_CDR_MAX_TRANSFORMS ? n : MSG_CDR_MAX_TRANSFORMS;
    out->dropped = n - out->count;
    return out->dropped ? MSG_CDR_ERR_CAPACITY : MSG_CDR_OK;
}

int msg_cdr_decode_joint_state(const uint8_t *buf, size_t len, msg_cdr_joint_state *out)
{
    TRY(check_args(buf, out));
    memset(out, 0, sizeof *out);
    cur c = { buf, len, 0 };
    uint32_t n;

    TRY(rd_header(&c, &out->stamp, out->frame_id, &out->strings_truncated));

    TRY(rd_seq_len(&c, &n)); /* name[] */
    for (uint32_t i = 0; i < n; i++) {
        if (i < MSG_CDR_MAX_JOINTS) {
            TRY(rd_str(&c, out->names[i], MSG_CDR_NAME_MAX, &out->strings_truncated));
        } else {
            TRY(rd_str(&c, NULL, 0, NULL));
        }
    }
    out->name_count = n < MSG_CDR_MAX_JOINTS ? n : MSG_CDR_MAX_JOINTS;
    out->dropped += n - out->name_count;

    double *arrays[3] = { out->position, out->velocity, out->effort };
    uint32_t *counts[3] = { &out->position_count, &out->velocity_count, &out->effort_count };
    for (int a = 0; a < 3; a++) {
        TRY(rd_seq_len(&c, &n));
        for (uint32_t i = 0; i < n; i++) {
            double v;
            TRY(rd_f64(&c, &v));
            if (i < MSG_CDR_MAX_JOINTS) {
                arrays[a][i] = v;
            }
        }
        *counts[a] = n < MSG_CDR_MAX_JOINTS ? n : MSG_CDR_MAX_JOINTS;
        out->dropped += n - *counts[a];
    }
    return out->dropped ? MSG_CDR_ERR_CAPACITY : MSG_CDR_OK;
}

int msg_cdr_decode_occupancy_grid(const uint8_t *buf, size_t len, msg_cdr_occupancy_grid *out)
{
    TRY(check_args(buf, out));
    memset(out, 0, sizeof *out);
    cur c = { buf, len, 0 };
    TRY(rd_header(&c, &out->stamp, out->frame_id, &out->strings_truncated));
    TRY(rd_time(&c, &out->map_load_time));
    TRY(rd_f32(&c, &out->resolution));
    TRY(rd_u32(&c, &out->width));
    TRY(rd_u32(&c, &out->height));
    TRY(rd_f64n(&c, out->origin_position, 3));
    TRY(rd_f64n(&c, out->origin_orientation, 4));
    uint32_t n;
    TRY(rd_u32(&c, &n));
    TRY(need(&c, n));
    out->data = (const int8_t *)(c.b + c.pos);
    out->data_len = n;
    return MSG_CDR_OK;
}

int msg_cdr_decode_marker(const uint8_t *buf, size_t len, msg_cdr_marker *out)
{
    TRY(check_args(buf, out));
    memset(out, 0, sizeof *out);
    cur c = { buf, len, 0 };
    TRY(rd_header(&c, &out->stamp, out->frame_id, &out->strings_truncated));
    TRY(rd_str(&c, out->ns, MSG_CDR_NAME_MAX, &out->strings_truncated));
    TRY(rd_i32(&c, &out->id));
    TRY(rd_i32(&c, &out->type));
    TRY(rd_i32(&c, &out->action));
    TRY(rd_f64n(&c, out->position, 3));
    TRY(rd_f64n(&c, out->orientation, 4));
    TRY(rd_f64n(&c, out->scale, 3));
    for (int i = 0; i < 4; i++) {
        TRY(rd_f32(&c, &out->color[i]));
    }
    TRY(rd_time(&c, &out->lifetime));
    TRY(rd_bool(&c, &out->frame_locked));

    uint32_t n;
    TRY(rd_seq_len(&c, &n)); /* points[] */
    for (uint32_t i = 0; i < n; i++) {
        double p[3];
        TRY(rd_f64n(&c, p, 3));
        if (i < MSG_CDR_MAX_MARKER_POINTS) {
            memcpy(out->points[i], p, sizeof p);
        }
    }
    out->point_count = n < MSG_CDR_MAX_MARKER_POINTS ? n : MSG_CDR_MAX_MARKER_POINTS;
    out->points_dropped = n - out->point_count;

    TRY(rd_seq_len(&c, &n)); /* colors[] */
    for (uint32_t i = 0; i < n; i++) {
        float col[4];
        for (int k = 0; k < 4; k++) {
            TRY(rd_f32(&c, &col[k]));
        }
        if (i < MSG_CDR_MAX_MARKER_POINTS) {
            memcpy(out->colors[i], col, sizeof col);
        }
    }
    out->color_count = n < MSG_CDR_MAX_MARKER_POINTS ? n : MSG_CDR_MAX_MARKER_POINTS;
    out->colors_dropped = n - out->color_count;

    return (out->points_dropped || out->colors_dropped) ? MSG_CDR_ERR_CAPACITY : MSG_CDR_OK;
}
