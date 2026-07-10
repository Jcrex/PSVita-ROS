/**
 * camera.h — Cámara orbital del mini-rviz (Etapa B3, docs/11 §1).
 *
 * LÓGICA PURA, SIN HEADERS DE LA VITA: compila en host y se testea con
 * scripts/check-viz-host.sh (misma filosofía que teleop.c). viz.c la
 * convierte en matrices GL con gluLookAt.
 *
 * Convención de ejes: REP 103 / rviz — Z hacia ARRIBA, X adelante,
 * Y a la izquierda. La cámara orbita alrededor de `target`:
 *   eye = target + dist * (cos(pitch)·cos(yaw), cos(pitch)·sin(yaw), sin(pitch))
 * con yaw alrededor de Z y pitch elevándose desde el plano XY.
 */
#ifndef VITA_VIZ_CAMERA_H
#define VITA_VIZ_CAMERA_H

#ifdef __cplusplus
extern "C" {
#endif

/* Límites (clamps de viz_camera_orbit/zoom; ver camera.c). */
#define VIZ_CAM_PITCH_MAX 1.53f /* rad (~87.7°): nunca llega al polo    */
#define VIZ_CAM_DIST_MIN 0.5f   /* m                                    */
#define VIZ_CAM_DIST_MAX 50.0f  /* m                                    */

typedef struct {
    float yaw;       /* rad, alrededor de Z (0 = mirando desde +X)     */
    float pitch;     /* rad, [-PITCH_MAX, PITCH_MAX]                   */
    float dist;      /* m, [DIST_MIN, DIST_MAX]                        */
    float target[3]; /* punto orbitado (por ahora el origen del mundo) */
} viz_camera;

/** Pose inicial: vista isométrica suave a 6 m del origen. */
void viz_camera_init(viz_camera *c);

/** Suma dyaw/dpitch (rad) con clamp del pitch; yaw envuelve libre. */
void viz_camera_orbit(viz_camera *c, float dyaw, float dpitch);

/** Multiplica la distancia por `factor` (>1 aleja) con clamps. */
void viz_camera_zoom(viz_camera *c, float factor);

/** Posición del ojo en el mundo según la fórmula del encabezado. */
void viz_camera_eye(const viz_camera *c, float eye[3]);

#ifdef __cplusplus
}
#endif

#endif /* VITA_VIZ_CAMERA_H */
