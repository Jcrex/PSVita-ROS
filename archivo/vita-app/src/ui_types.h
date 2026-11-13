/**
 * ui_types.h — Tipos de la UI declarativa de la app (sin dependencias de
 * la Vita: compila en host, lo usa scripts/check-ui-layout.sh).
 *
 * La UI de la app NO se escribe a mano: se describe en vita-app/ui/layout.json
 * (editable desde la web, /taller/ui) y scripts/gen-ui-header.mjs la convierte
 * en ui_layout.h (un array de estos structs). ui.c recorre ese array cada
 * frame y lo dibuja con vita2d (ADR 0005: excepción a la regla dual — el
 * dibujado es código de app, solo Vita, solo C).
 *
 * Pantalla de la Vita: 960x544. Para label/valor, (x, y) es la esquina
 * superior izquierda aproximada del texto (ui.c compensa la línea base).
 */
#ifndef VITA_UI_TYPES_H
#define VITA_UI_TYPES_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

#define UI_PANTALLA_W 960
#define UI_PANTALLA_H 544
#define UI_MAX_TEXTO 64 /* 63 chars + NUL (mismo límite que el codegen) */

typedef enum {
    UI_W_PANEL = 0, /* rectángulo relleno, borde opcional */
    UI_W_LABEL = 1, /* texto fijo (campo `texto`)         */
    UI_W_VALOR = 2, /* texto dinámico (campo `binding`)   */
} ui_widget_tipo;

/* Datos de la app que un widget `valor` puede mostrar (enum cerrado; si se
 * añade uno hay que tocar: este enum, gen-ui-header.mjs, ui.c y el editor
 * web web/src/lib/ui-layout.ts). */
typedef enum {
    UI_B_NONE = 0,
    UI_B_ESTADO_CONEXION = 1,     /* "CONECTADO" / "SIN CONEXION"    */
    UI_B_CONTADOR_PUBLICADOS = 2, /* mensajes enviados a /vita_hello */
    UI_B_ULTIMO_PC_HELLO = 3,     /* último string recibido del PC   */
    UI_B_AGENTE = 4,              /* "ip:puerto" del micro-ROS Agent */
    UI_B_VEL_LINEAL = 5,          /* escala teleop lineal "0.5 m/s"  */
    UI_B_VEL_LATERAL = 6,         /* escala teleop lateral           */
    UI_B_CMD_VEL = 7,             /* Twist en vivo "x+.. y+.. rz+.." */
    UI_B_CONTADOR_CMD = 8,        /* mensajes enviados a /cmd_vel    */
} ui_binding;

/* Colores en el empaquetado de vita2d RGBA8(r,g,b,a): r | g<<8 | b<<16 | a<<24
 * (los genera gen-ui-header.mjs a partir de "#rrggbb", alfa siempre 0xff). */
typedef struct {
    ui_widget_tipo tipo;
    int16_t x, y;   /* posición en pantalla (0..959, 0..543)      */
    int16_t w, h;   /* solo panel; 0 en label/valor               */
    uint32_t color; /* relleno (panel) o color del texto          */
    uint32_t borde; /* solo panel; 0 = sin borde                  */
    float escala;   /* solo texto: 0.5 .. 3.0                     */
    ui_binding binding;
    char texto[UI_MAX_TEXTO];
} ui_widget;

/* Estado vivo que main.c actualiza y ui_draw() muestra vía bindings. */
typedef struct {
    bool conectado;
    uint32_t contador;
    char ultimo_pc_hello[96];
    char agente[32];
    /* Objetivo 2 (teleop /cmd_vel; ver docs/09 y teleop.h): */
    float vel_lineal;   /* escala de stick izq + cruceta   */
    float vel_lateral;  /* escala del stick derecho        */
    float lin_x, lin_y; /* Twist publicado ahora mismo     */
    float ang_z;
    uint32_t contador_cmd; /* mensajes enviados a /cmd_vel */
} ui_state;

#ifdef __cplusplus
}
#endif

#endif /* VITA_UI_TYPES_H */
