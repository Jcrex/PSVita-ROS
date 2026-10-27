/**
 * msg_schema.h — Contrato C-ABI del módulo dual `msg-schema`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: el equivalente en la Vita de `ros_babel_fish` (rclgd, docs/17): un
 * codec CDR GENÉRICO guiado por un esquema, para decodificar/codificar
 * CUALQUIER mensaje ROS2 cuyo tipo esté en el blob de esquema, sin código
 * generado por tipo y sin malloc. El blob `.rsch` lo genera en el PC
 * `tools/gen_msg_schema.py` a partir de las definiciones reales de Jazzy.
 *
 * Formato del blob (todo little-endian, sin requisitos de alineación):
 *   cabecera 32 B : "RSCH" | u16 version=1 | u16 flags=0 | u32 type_count |
 *                   u32 field_count | u32 types_off | u32 fields_off |
 *                   u32 strings_off | u32 total_len
 *   tipos   12 B  : u32 name_off | u32 field_first | u32 field_count
 *   campos  16 B  : u32 name_off | u8 kind | u8 prim | u8 array | u8 pad |
 *                   u32 type_idx | u32 array_len
 *   strings       : nombres terminados en NUL (offsets relativos a strings_off)
 *   kind 0=PRIM 1=STRING 2=STRUCT; array 0=ninguno 1=fijo(array_len) 2=secuencia
 *   (array_len = cota, 0 = sin cota).
 *
 * Datos: payload CDR XCDR1 little-endian SIN la encapsulación de 4 bytes (como
 * msg-cdr); alineaciones (2/4/8) contadas desde el inicio del payload.
 *
 * Decodificación: API de VISITOR (el codec llama a sus callbacks en orden de
 * campos). Los arrays primitivos se entregan como (puntero, cuenta) DENTRO del
 * payload —cero copias—, little-endian y posiblemente NO alineado: el
 * consumidor usa memcpy. Un callback NULL se ignora; un callback que devuelve
 * distinto de 0 aborta con MSG_SCHEMA_ERR_ABORTED.
 *
 * Codificación: API de SOURCE (el codec pide los valores en orden de campos).
 */
#ifndef VITA_MSG_SCHEMA_H
#define VITA_MSG_SCHEMA_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MSG_SCHEMA_OK              =  0,
    MSG_SCHEMA_ERR_INVALID_ARG = -1, /* puntero nulo o callback obligatorio ausente */
    MSG_SCHEMA_ERR_BAD_SCHEMA  = -2, /* blob mal formado o fuera de rango */
    MSG_SCHEMA_ERR_UNKNOWN_TYPE = -3,
    MSG_SCHEMA_ERR_TRUNCATED   = -4, /* decode: el payload termina antes que el mensaje */
    MSG_SCHEMA_ERR_NO_SPACE    = -5, /* encode: el buffer de salida es pequeño */
    MSG_SCHEMA_ERR_ABORTED     = -6, /* un callback devolvió != 0 */
    MSG_SCHEMA_ERR_TOO_DEEP    = -7, /* anidamiento > MSG_SCHEMA_MAX_DEPTH */
    MSG_SCHEMA_ERR_BAD_VALUE   = -8, /* encode: longitud fija/cota incumplida, string > 4 GiB */
} msg_schema_status;

#define MSG_SCHEMA_MAX_DEPTH 16

typedef enum {
    MSG_PRIM_BOOL = 0, MSG_PRIM_U8 = 1, MSG_PRIM_I8 = 2, MSG_PRIM_U16 = 3,
    MSG_PRIM_I16 = 4, MSG_PRIM_U32 = 5, MSG_PRIM_I32 = 6, MSG_PRIM_U64 = 7,
    MSG_PRIM_I64 = 8, MSG_PRIM_F32 = 9, MSG_PRIM_F64 = 10,
} msg_prim;

typedef enum { MSG_KIND_PRIM = 0, MSG_KIND_STRING = 1, MSG_KIND_STRUCT = 2 } msg_kind;
typedef enum { MSG_ARRAY_NONE = 0, MSG_ARRAY_FIXED = 1, MSG_ARRAY_SEQ = 2 } msg_array;

/** Vista validada de un blob. El llamador aporta la estructura; el blob debe
 *  seguir vivo y sin modificar mientras se use. */
typedef struct {
    const uint8_t *blob;
    size_t   len;
    uint32_t type_count;
    uint32_t field_count;
    uint32_t types_off;
    uint32_t fields_off;
    uint32_t strings_off;
    uint32_t strings_len;
} msg_schema;

typedef struct {
    const char *name;     /* NUL-terminado, apunta dentro del blob */
    uint8_t  kind;        /* msg_kind  */
    uint8_t  prim;        /* msg_prim (solo si kind == PRIM) */
    uint8_t  array;       /* msg_array */
    uint8_t  pad;
    uint32_t type_idx;    /* solo si kind == STRUCT */
    uint32_t array_len;   /* fijo: longitud; secuencia: cota (0 = sin cota) */
} msg_field_info;

/** Valida el blob (magia, versión, offsets, índices, strings). */
int msg_schema_init(msg_schema *s, const uint8_t *blob, size_t len);
uint32_t msg_schema_type_count(const msg_schema *s);
int msg_schema_find_type(const msg_schema *s, const char *name, uint32_t *type_idx);
int msg_schema_type_name(const msg_schema *s, uint32_t type_idx, const char **name);
int msg_schema_field_count(const msg_schema *s, uint32_t type_idx, uint32_t *count);
int msg_schema_field(const msg_schema *s, uint32_t type_idx, uint32_t field_idx,
                     msg_field_info *out);
/** Tamaño en bytes de una primitiva (1,2,4,8). */
uint32_t msg_prim_size(msg_prim p);

/* ---- Decodificación (visitor) ------------------------------------------ */
/* `name` es el nombre del campo, o NULL cuando el evento es un ELEMENTO de un
 * array (el visitor lleva la cuenta del índice). Un struct raíz llega con
 * begin_struct(NULL). `raw` de prim: valor LE sin signo extendido a 64 bits
 * (bits del float para F32/F64; bool = 0/1; ints con signo como complemento a
 * dos en su ancho, sin extensión de signo). */
typedef struct {
    int (*begin_struct)(void *ctx, const char *name);
    int (*end_struct)(void *ctx);
    int (*prim)(void *ctx, const char *name, int prim, uint64_t raw);
    int (*string)(void *ctx, const char *name, const uint8_t *s, uint32_t len);
    /* secuencia/array fijo de PRIMITIVAS: data -> payload, count elementos LE */
    int (*prim_array)(void *ctx, const char *name, int prim, const uint8_t *data, uint32_t count);
    /* secuencia/array fijo de strings o structs: se avisa del tamaño y luego
     * llegan `count` elementos (string(NULL,..) o begin_struct(NULL)/end_struct) */
    int (*begin_array)(void *ctx, const char *name, uint32_t count);
    int (*end_array)(void *ctx);
} msg_visitor;

/** Decodifica un mensaje. `consumed` (opcional) recibe los bytes leídos. */
int msg_schema_decode(const msg_schema *s, uint32_t type_idx, const uint8_t *buf, size_t len,
                      const msg_visitor *vis, void *ctx, size_t *consumed);

/* ---- Codificación (source) --------------------------------------------- */
typedef struct {
    int (*begin_struct)(void *ctx, const char *name);
    int (*end_struct)(void *ctx);
    int (*prim)(void *ctx, const char *name, int prim, uint64_t *raw);
    int (*string)(void *ctx, const char *name, const uint8_t **s, uint32_t *len);
    /* data: little-endian contiguo; para array FIJO `count` debe igualar su longitud */
    int (*prim_array)(void *ctx, const char *name, int prim, uint32_t fixed_len,
                      const uint8_t **data, uint32_t *count);
    /* nº de elementos de un array/secuencia de strings o structs (fijo: debe igualar) */
    int (*array_len)(void *ctx, const char *name, uint32_t fixed_len, uint32_t *count);
} msg_source;

/** Codifica un mensaje (sin encapsulación) en `out`. Padding a cero. */
int msg_schema_encode(const msg_schema *s, uint32_t type_idx, const msg_source *src, void *ctx,
                      uint8_t *out, size_t cap, size_t *written);

#ifdef __cplusplus
}
#endif

#endif /* VITA_MSG_SCHEMA_H */
