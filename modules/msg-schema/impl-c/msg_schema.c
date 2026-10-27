/**
 * msg_schema.c — Implementación C11 del contrato include/msg_schema.h.
 */
#include "msg_schema.h"

#include <string.h>

#define HEADER_LEN 32u
#define TYPE_ROW 12u
#define FIELD_ROW 16u

#define TRY(x)                      \
    do {                            \
        int try_rc_ = (x);          \
        if (try_rc_ != MSG_SCHEMA_OK) { \
            return try_rc_;         \
        }                           \
    } while (0)

static uint32_t ld16(const uint8_t *p) { return (uint32_t)p[0] | ((uint32_t)p[1] << 8); }
static uint32_t ld32(const uint8_t *p)
{
    return (uint32_t)p[0] | ((uint32_t)p[1] << 8) | ((uint32_t)p[2] << 16) | ((uint32_t)p[3] << 24);
}

uint32_t msg_prim_size(msg_prim p)
{
    static const uint8_t sz[11] = { 1, 1, 1, 2, 2, 4, 4, 8, 8, 4, 8 };
    return (unsigned)p <= MSG_PRIM_F64 ? sz[p] : 0;
}

/* ------------------------------------------------------------ esquema */
static int str_ok(const msg_schema *s, uint32_t off)
{
    if (off >= s->strings_len) {
        return 0;
    }
    const uint8_t *p = s->blob + s->strings_off;
    for (uint32_t i = off; i < s->strings_len; i++) {
        if (p[i] == 0) {
            return 1;
        }
    }
    return 0;
}

int msg_schema_init(msg_schema *s, const uint8_t *blob, size_t len)
{
    if (s == NULL || blob == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    if (len < HEADER_LEN || memcmp(blob, "RSCH", 4) != 0 || ld16(blob + 4) != 1) {
        return MSG_SCHEMA_ERR_BAD_SCHEMA;
    }
    uint32_t tcount = ld32(blob + 8), fcount = ld32(blob + 12);
    uint32_t toff = ld32(blob + 16), foff = ld32(blob + 20), soff = ld32(blob + 24);
    uint32_t total = ld32(blob + 28);
    if (total != len || toff < HEADER_LEN || foff < toff || soff < foff) {
        return MSG_SCHEMA_ERR_BAD_SCHEMA;
    }
    /* tablas dentro del blob (sin desbordar u32/size_t) */
    if ((uint64_t)toff + (uint64_t)tcount * TYPE_ROW != foff ||
        (uint64_t)foff + (uint64_t)fcount * FIELD_ROW != soff) {
        return MSG_SCHEMA_ERR_BAD_SCHEMA;
    }
    s->blob = blob;
    s->len = len;
    s->type_count = tcount;
    s->field_count = fcount;
    s->types_off = toff;
    s->fields_off = foff;
    s->strings_off = soff;
    s->strings_len = total - soff;

    for (uint32_t t = 0; t < tcount; t++) {
        const uint8_t *r = blob + toff + (size_t)t * TYPE_ROW;
        uint32_t first = ld32(r + 4), n = ld32(r + 8);
        /* n == 0 prohibido: un struct sin campos no consumiría bytes y un array
         * enorme de ellos permitiría bucles interminables con un blob corrupto. */
        if (!str_ok(s, ld32(r)) || n == 0 || (uint64_t)first + n > fcount) {
            return MSG_SCHEMA_ERR_BAD_SCHEMA;
        }
    }
    for (uint32_t f = 0; f < fcount; f++) {
        const uint8_t *r = blob + foff + (size_t)f * FIELD_ROW;
        uint8_t kind = r[4], prim = r[5], array = r[6];
        if (!str_ok(s, ld32(r)) || kind > MSG_KIND_STRUCT || array > MSG_ARRAY_SEQ) {
            return MSG_SCHEMA_ERR_BAD_SCHEMA;
        }
        if (kind == MSG_KIND_PRIM && prim > MSG_PRIM_F64) {
            return MSG_SCHEMA_ERR_BAD_SCHEMA;
        }
        if (kind == MSG_KIND_STRUCT && ld32(r + 8) >= tcount) {
            return MSG_SCHEMA_ERR_BAD_SCHEMA;
        }
        if (array == MSG_ARRAY_FIXED && ld32(r + 12) == 0) {
            return MSG_SCHEMA_ERR_BAD_SCHEMA;
        }
    }
    return MSG_SCHEMA_OK;
}

uint32_t msg_schema_type_count(const msg_schema *s)
{
    return s == NULL ? 0 : s->type_count;
}

static const char *pool(const msg_schema *s, uint32_t off)
{
    return (const char *)(s->blob + s->strings_off + off);
}

int msg_schema_type_name(const msg_schema *s, uint32_t idx, const char **name)
{
    if (s == NULL || name == NULL || s->blob == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    if (idx >= s->type_count) {
        return MSG_SCHEMA_ERR_UNKNOWN_TYPE;
    }
    *name = pool(s, ld32(s->blob + s->types_off + (size_t)idx * TYPE_ROW));
    return MSG_SCHEMA_OK;
}

int msg_schema_find_type(const msg_schema *s, const char *name, uint32_t *idx)
{
    if (s == NULL || name == NULL || idx == NULL || s->blob == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    for (uint32_t t = 0; t < s->type_count; t++) {
        const char *n;
        TRY(msg_schema_type_name(s, t, &n));
        if (strcmp(n, name) == 0) {
            *idx = t;
            return MSG_SCHEMA_OK;
        }
    }
    return MSG_SCHEMA_ERR_UNKNOWN_TYPE;
}

int msg_schema_field_count(const msg_schema *s, uint32_t idx, uint32_t *count)
{
    if (s == NULL || count == NULL || s->blob == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    if (idx >= s->type_count) {
        return MSG_SCHEMA_ERR_UNKNOWN_TYPE;
    }
    *count = ld32(s->blob + s->types_off + (size_t)idx * TYPE_ROW + 8);
    return MSG_SCHEMA_OK;
}

int msg_schema_field(const msg_schema *s, uint32_t tidx, uint32_t fidx, msg_field_info *out)
{
    if (s == NULL || out == NULL || s->blob == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    if (tidx >= s->type_count) {
        return MSG_SCHEMA_ERR_UNKNOWN_TYPE;
    }
    const uint8_t *t = s->blob + s->types_off + (size_t)tidx * TYPE_ROW;
    if (fidx >= ld32(t + 8)) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    const uint8_t *r = s->blob + s->fields_off + (size_t)(ld32(t + 4) + fidx) * FIELD_ROW;
    out->name = pool(s, ld32(r));
    out->kind = r[4];
    out->prim = r[5];
    out->array = r[6];
    out->pad = 0;
    out->type_idx = ld32(r + 8);
    out->array_len = ld32(r + 12);
    return MSG_SCHEMA_OK;
}

/* ------------------------------------------------------------ decode */
typedef struct {
    const msg_schema *s;
    const uint8_t *b;
    size_t len;
    size_t pos;
    const msg_visitor *v;
    void *ctx;
} dec;

static int d_align(dec *d, size_t a)
{
    size_t p = (d->pos + (a - 1)) & ~(a - 1);
    if (p > d->len) {
        return MSG_SCHEMA_ERR_TRUNCATED;
    }
    d->pos = p;
    return MSG_SCHEMA_OK;
}

static int d_need(const dec *d, size_t n)
{
    return (d->len - d->pos >= n) ? MSG_SCHEMA_OK : MSG_SCHEMA_ERR_TRUNCATED;
}

static int d_u32(dec *d, uint32_t *v)
{
    TRY(d_align(d, 4));
    TRY(d_need(d, 4));
    *v = ld32(d->b + d->pos);
    d->pos += 4;
    return MSG_SCHEMA_OK;
}

static uint64_t ld_raw(const uint8_t *p, uint32_t size)
{
    uint64_t v = 0;
    for (int i = (int)size - 1; i >= 0; i--) {
        v = (v << 8) | p[i];
    }
    return v;
}

#define CB(call)                                   \
    do {                                           \
        if ((call) != 0) {                         \
            return MSG_SCHEMA_ERR_ABORTED;         \
        }                                          \
    } while (0)

static int dec_struct(dec *d, uint32_t tidx, const char *name, int depth);

static int dec_string(dec *d, const char *name)
{
    uint32_t n;
    TRY(d_u32(d, &n));
    TRY(d_need(d, n));
    if (d->v->string != NULL) {
        CB(d->v->string(d->ctx, name, d->b + d->pos, n > 0 ? n - 1 : 0));
    }
    d->pos += n;
    return MSG_SCHEMA_OK;
}

static int dec_field(dec *d, const msg_field_info *f, int depth)
{
    const msg_visitor *v = d->v;
    if (f->array == MSG_ARRAY_NONE) {
        if (f->kind == MSG_KIND_PRIM) {
            uint32_t sz = msg_prim_size((msg_prim)f->prim);
            TRY(d_align(d, sz));
            TRY(d_need(d, sz));
            if (v->prim != NULL) {
                CB(v->prim(d->ctx, f->name, f->prim, ld_raw(d->b + d->pos, sz)));
            }
            d->pos += sz;
            return MSG_SCHEMA_OK;
        }
        if (f->kind == MSG_KIND_STRING) {
            return dec_string(d, f->name);
        }
        return dec_struct(d, f->type_idx, f->name, depth + 1);
    }

    uint32_t count = f->array_len;
    if (f->array == MSG_ARRAY_SEQ) {
        TRY(d_u32(d, &count));
        if (count > d->len - d->pos) {
            return MSG_SCHEMA_ERR_TRUNCATED; /* cada elemento ocupa >= 1 byte */
        }
    }
    if (f->kind == MSG_KIND_PRIM) {
        uint32_t sz = msg_prim_size((msg_prim)f->prim);
        if (count > SIZE_MAX / sz) {
            return MSG_SCHEMA_ERR_TRUNCATED; /* evita desbordar size_t en 32 bits */
        }
        size_t bytes = (size_t)count * sz;
        if (count > 0) {
            TRY(d_align(d, sz));
        }
        TRY(d_need(d, bytes));
        if (v->prim_array != NULL) {
            CB(v->prim_array(d->ctx, f->name, f->prim, d->b + d->pos, count));
        }
        d->pos += bytes;
        return MSG_SCHEMA_OK;
    }
    if (v->begin_array != NULL) {
        CB(v->begin_array(d->ctx, f->name, count));
    }
    for (uint32_t i = 0; i < count; i++) {
        if (f->kind == MSG_KIND_STRING) {
            TRY(dec_string(d, NULL));
        } else {
            TRY(dec_struct(d, f->type_idx, NULL, depth + 1));
        }
    }
    if (v->end_array != NULL) {
        CB(v->end_array(d->ctx));
    }
    return MSG_SCHEMA_OK;
}

static int dec_struct(dec *d, uint32_t tidx, const char *name, int depth)
{
    if (depth > MSG_SCHEMA_MAX_DEPTH) {
        return MSG_SCHEMA_ERR_TOO_DEEP;
    }
    uint32_t nf;
    TRY(msg_schema_field_count(d->s, tidx, &nf));
    if (d->v->begin_struct != NULL) {
        CB(d->v->begin_struct(d->ctx, name));
    }
    for (uint32_t i = 0; i < nf; i++) {
        msg_field_info f;
        TRY(msg_schema_field(d->s, tidx, i, &f));
        TRY(dec_field(d, &f, depth));
    }
    if (d->v->end_struct != NULL) {
        CB(d->v->end_struct(d->ctx));
    }
    return MSG_SCHEMA_OK;
}

int msg_schema_decode(const msg_schema *s, uint32_t type_idx, const uint8_t *buf, size_t len,
                      const msg_visitor *vis, void *ctx, size_t *consumed)
{
    if (s == NULL || s->blob == NULL || buf == NULL || vis == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    dec d = { s, buf, len, 0, vis, ctx };
    TRY(dec_struct(&d, type_idx, NULL, 0));
    if (consumed != NULL) {
        *consumed = d.pos;
    }
    return MSG_SCHEMA_OK;
}

/* ------------------------------------------------------------ encode */
typedef struct {
    const msg_schema *s;
    uint8_t *out;
    size_t cap;
    size_t pos;
    const msg_source *src;
    void *ctx;
} enc;

static int e_pad(enc *e, size_t a)
{
    size_t p = (e->pos + (a - 1)) & ~(a - 1);
    if (p > e->cap) {
        return MSG_SCHEMA_ERR_NO_SPACE;
    }
    memset(e->out + e->pos, 0, p - e->pos);
    e->pos = p;
    return MSG_SCHEMA_OK;
}

static int e_room(const enc *e, size_t n)
{
    return (e->cap - e->pos >= n) ? MSG_SCHEMA_OK : MSG_SCHEMA_ERR_NO_SPACE;
}

static int e_u32(enc *e, uint32_t v)
{
    TRY(e_pad(e, 4));
    TRY(e_room(e, 4));
    for (int i = 0; i < 4; i++) {
        e->out[e->pos + i] = (uint8_t)(v >> (8 * i));
    }
    e->pos += 4;
    return MSG_SCHEMA_OK;
}

static int enc_struct(enc *e, uint32_t tidx, int depth);

static int enc_string(enc *e, const char *name)
{
    const uint8_t *p = NULL;
    uint32_t n = 0;
    if (e->src->string == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    CB(e->src->string(e->ctx, name, &p, &n));
    if (n == UINT32_MAX || (p == NULL && n > 0)) {
        return MSG_SCHEMA_ERR_BAD_VALUE;
    }
    TRY(e_u32(e, n + 1));
    TRY(e_room(e, (size_t)n + 1));
    if (n > 0) {
        memcpy(e->out + e->pos, p, n);
    }
    e->out[e->pos + n] = 0;
    e->pos += (size_t)n + 1;
    return MSG_SCHEMA_OK;
}

static int enc_field(enc *e, const msg_field_info *f, int depth)
{
    const msg_source *src = e->src;
    if (f->array == MSG_ARRAY_NONE) {
        if (f->kind == MSG_KIND_PRIM) {
            uint32_t sz = msg_prim_size((msg_prim)f->prim);
            uint64_t raw = 0;
            if (src->prim == NULL) {
                return MSG_SCHEMA_ERR_INVALID_ARG;
            }
            CB(src->prim(e->ctx, f->name, f->prim, &raw));
            TRY(e_pad(e, sz));
            TRY(e_room(e, sz));
            for (uint32_t i = 0; i < sz; i++) {
                e->out[e->pos + i] = (uint8_t)(raw >> (8 * i));
            }
            e->pos += sz;
            return MSG_SCHEMA_OK;
        }
        if (f->kind == MSG_KIND_STRING) {
            return enc_string(e, f->name);
        }
        if (src->begin_struct != NULL) {
            CB(src->begin_struct(e->ctx, f->name));
        }
        TRY(enc_struct(e, f->type_idx, depth + 1));
        if (src->end_struct != NULL) {
            CB(src->end_struct(e->ctx));
        }
        return MSG_SCHEMA_OK;
    }

    uint32_t fixed = f->array == MSG_ARRAY_FIXED ? f->array_len : 0;
    uint32_t count = 0;
    if (f->kind == MSG_KIND_PRIM) {
        const uint8_t *data = NULL;
        uint32_t sz = msg_prim_size((msg_prim)f->prim);
        if (src->prim_array == NULL) {
            return MSG_SCHEMA_ERR_INVALID_ARG;
        }
        CB(src->prim_array(e->ctx, f->name, f->prim, fixed, &data, &count));
        if ((fixed && count != fixed) || (f->array == MSG_ARRAY_SEQ && f->array_len && count > f->array_len) ||
            (data == NULL && count > 0)) {
            return MSG_SCHEMA_ERR_BAD_VALUE;
        }
        if (f->array == MSG_ARRAY_SEQ) {
            TRY(e_u32(e, count));
        }
        if (count > 0) {
            TRY(e_pad(e, sz));
            if ((size_t)count > (e->cap - e->pos) / sz) {
                return MSG_SCHEMA_ERR_NO_SPACE;
            }
            memcpy(e->out + e->pos, data, (size_t)count * sz);
            e->pos += (size_t)count * sz;
        }
        return MSG_SCHEMA_OK;
    }
    if (src->array_len == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    CB(src->array_len(e->ctx, f->name, fixed, &count));
    if ((fixed && count != fixed) || (f->array == MSG_ARRAY_SEQ && f->array_len && count > f->array_len)) {
        return MSG_SCHEMA_ERR_BAD_VALUE;
    }
    if (f->array == MSG_ARRAY_SEQ) {
        TRY(e_u32(e, count));
    }
    for (uint32_t i = 0; i < count; i++) {
        if (f->kind == MSG_KIND_STRING) {
            TRY(enc_string(e, NULL));
        } else {
            if (src->begin_struct != NULL) {
                CB(src->begin_struct(e->ctx, NULL));
            }
            TRY(enc_struct(e, f->type_idx, depth + 1));
            if (src->end_struct != NULL) {
                CB(src->end_struct(e->ctx));
            }
        }
    }
    return MSG_SCHEMA_OK;
}

static int enc_struct(enc *e, uint32_t tidx, int depth)
{
    if (depth > MSG_SCHEMA_MAX_DEPTH) {
        return MSG_SCHEMA_ERR_TOO_DEEP;
    }
    uint32_t nf;
    TRY(msg_schema_field_count(e->s, tidx, &nf));
    for (uint32_t i = 0; i < nf; i++) {
        msg_field_info f;
        TRY(msg_schema_field(e->s, tidx, i, &f));
        TRY(enc_field(e, &f, depth));
    }
    return MSG_SCHEMA_OK;
}

int msg_schema_encode(const msg_schema *s, uint32_t type_idx, const msg_source *src, void *ctx,
                      uint8_t *out, size_t cap, size_t *written)
{
    if (s == NULL || s->blob == NULL || src == NULL || out == NULL) {
        return MSG_SCHEMA_ERR_INVALID_ARG;
    }
    enc e = { s, out, cap, 0, src, ctx };
    if (src->begin_struct != NULL) {
        CB(src->begin_struct(ctx, NULL));
    }
    TRY(enc_struct(&e, type_idx, 0));
    if (src->end_struct != NULL) {
        CB(src->end_struct(ctx));
    }
    if (written != NULL) {
        *written = e.pos;
    }
    return MSG_SCHEMA_OK;
}
