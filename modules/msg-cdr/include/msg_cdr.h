/**
 * msg_cdr.h — Contrato C-ABI del módulo dual `msg-cdr`.
 *
 * ESTE HEADER ES LA VERDAD DEL MÓDULO (docs/03-estrategia-dual-rust-cpp.md).
 *
 * Qué es: deserializadores CDR (XCDR1, little-endian, el formato de ROS2 en
 * DDS/XRCE) de los mensajes que consume el mini-rviz (docs/11):
 *   tf2_msgs/TFMessage · sensor_msgs/JointState · nav_msgs/OccupancyGrid ·
 *   visualization_msgs/Marker
 * Sin malloc, sin estado, sin copias grandes: rellenan structs C planos con
 * topes fijos. Si el mensaje trae más elementos que el tope se guarda lo que
 * cabe, se CUENTA lo descartado en `dropped` y se devuelve MSG_CDR_ERR_CAPACITY
 * (la salida es válida pero parcial; el netlog debe informarlo).
 *
 * Entrada: `buf` es el payload CDR SIN los 4 bytes de encapsulación
 * (`00 01 00 00`), o sea lo que ve `on_topic()` de la app. Las alineaciones
 * (4 para int32/float32, 8 para float64) se cuentan desde el inicio de `buf`.
 * Para ficheros/rosbag con encapsulación use msg_cdr_strip_encapsulation().
 *
 * Definiciones de mensaje: ROS2 Jazzy (verificadas con el paquete `rosbags`,
 * ver tests/gen_fixtures.py). Del Marker solo se leen los campos hasta
 * `colors`; el resto (textura, uv, text, mesh...) se ignora a propósito.
 */
#ifndef VITA_MSG_CDR_H
#define VITA_MSG_CDR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef enum {
    MSG_CDR_OK              =  0,
    MSG_CDR_ERR_INVALID_ARG = -1, /* puntero nulo o encapsulación desconocida   */
    MSG_CDR_ERR_TRUNCATED   = -2, /* el buffer termina antes que el mensaje      */
    MSG_CDR_ERR_CAPACITY    = -3, /* salida parcial: hubo elementos descartados  */
    MSG_CDR_ERR_UNSUPPORTED = -4, /* encapsulación big-endian u otra no soportada */
} msg_cdr_status;

/* Topes (sin malloc). Cambiarlos cambia el tamaño de los structs. */
#define MSG_CDR_NAME_MAX          64  /* strings, incluye el NUL final */
#define MSG_CDR_MAX_TRANSFORMS    32
#define MSG_CDR_MAX_JOINTS        32
#define MSG_CDR_MAX_MARKER_POINTS 64

/* Los strings más largos que NAME_MAX-1 se truncan y se cuentan en
 * `strings_truncated` (no es error). */

typedef struct { int32_t sec; uint32_t nanosec; } msg_cdr_time;

/* geometry_msgs/TransformStamped */
typedef struct {
    msg_cdr_time stamp;
    char   frame_id[MSG_CDR_NAME_MAX];       /* padre */
    char   child_frame_id[MSG_CDR_NAME_MAX]; /* hijo  */
    double translation[3];                   /* x, y, z */
    double rotation[4];                      /* x, y, z, w */
} msg_cdr_transform;

/* tf2_msgs/TFMessage */
typedef struct {
    uint32_t count;              /* elementos válidos en items[] */
    uint32_t dropped;            /* transforms que no cupieron   */
    uint32_t strings_truncated;
    uint32_t reserved;
    msg_cdr_transform items[MSG_CDR_MAX_TRANSFORMS];
} msg_cdr_tf_message;

/* sensor_msgs/JointState */
typedef struct {
    msg_cdr_time stamp;
    char     frame_id[MSG_CDR_NAME_MAX];
    uint32_t name_count;      /* válidos en names[]    */
    uint32_t position_count;  /* válidos en position[] (0 si el array venía vacío) */
    uint32_t velocity_count;
    uint32_t effort_count;
    uint32_t dropped;         /* suma de elementos descartados en los 4 arrays */
    uint32_t strings_truncated;
    char     names[MSG_CDR_MAX_JOINTS][MSG_CDR_NAME_MAX];
    double   position[MSG_CDR_MAX_JOINTS];
    double   velocity[MSG_CDR_MAX_JOINTS];
    double   effort[MSG_CDR_MAX_JOINTS];
} msg_cdr_joint_state;

/* nav_msgs/OccupancyGrid. `data` apunta DENTRO del buffer de entrada (cero
 * copias): solo vale mientras ese buffer siga vivo y sin modificar. Una
 * celda es int8: -1 desconocida, 0..100 probabilidad de ocupación. No se
 * exige data_len == width*height (la app debe comprobarlo antes de dibujar). */
typedef struct {
    msg_cdr_time stamp;
    char     frame_id[MSG_CDR_NAME_MAX];
    msg_cdr_time map_load_time;
    float    resolution;           /* metros por celda */
    uint32_t width;
    uint32_t height;
    double   origin_position[3];
    double   origin_orientation[4]; /* x, y, z, w */
    const int8_t *data;
    uint32_t data_len;
    uint32_t strings_truncated;
} msg_cdr_occupancy_grid;

/* visualization_msgs/Marker (parcial: hasta `colors`) */
typedef struct {
    msg_cdr_time stamp;
    char     frame_id[MSG_CDR_NAME_MAX];
    char     ns[MSG_CDR_NAME_MAX];
    int32_t  id;
    int32_t  type;     /* 0 ARROW 1 CUBE 2 SPHERE 3 CYLINDER 4 LINE_STRIP 5 LINE_LIST ... */
    int32_t  action;   /* 0 ADD/MODIFY 2 DELETE 3 DELETEALL */
    uint32_t frame_locked;
    double   position[3];
    double   orientation[4];
    double   scale[3];
    float    color[4]; /* r, g, b, a */
    msg_cdr_time lifetime;
    uint32_t point_count;      /* válidos en points[] */
    uint32_t color_count;      /* válidos en colors[] */
    uint32_t points_dropped;
    uint32_t colors_dropped;
    uint32_t strings_truncated;
    uint32_t reserved;
    double   points[MSG_CDR_MAX_MARKER_POINTS][3];
    float    colors[MSG_CDR_MAX_MARKER_POINTS][4];
} msg_cdr_marker;

/** Quita la encapsulación de 4 bytes (`00 01 00 00` = CDR_LE). OK si es
 *  little-endian; ERR_UNSUPPORTED si es big-endian (`00 00`); ERR_TRUNCATED si
 *  len < 4; ERR_INVALID_ARG si algún puntero es NULL o el id es desconocido. */
int msg_cdr_strip_encapsulation(const uint8_t *buf, size_t len,
                                const uint8_t **payload, size_t *payload_len);

/* Cada decode: pone `out` a cero, deserializa y devuelve un msg_cdr_status.
 * Con TRUNCATED el contenido de `out` es parcial e inservible. */
int msg_cdr_decode_tf_message(const uint8_t *buf, size_t len, msg_cdr_tf_message *out);
int msg_cdr_decode_joint_state(const uint8_t *buf, size_t len, msg_cdr_joint_state *out);
int msg_cdr_decode_occupancy_grid(const uint8_t *buf, size_t len, msg_cdr_occupancy_grid *out);
int msg_cdr_decode_marker(const uint8_t *buf, size_t len, msg_cdr_marker *out);

#ifdef __cplusplus
}
#endif

#endif /* VITA_MSG_CDR_H */
