/**
 * ui_layout.h — GENERADO por scripts/gen-ui-header.mjs a partir de
 * ui/layout.json. NO EDITAR A MANO: editar el JSON (o desde la web en
 * /taller/ui) y regenerar. Verificación en host: scripts/check-ui-layout.sh.
 */
#ifndef VITA_UI_LAYOUT_H
#define VITA_UI_LAYOUT_H

#include "ui_types.h"

#define UI_FONDO 0xff181010u

static const ui_widget UI_WIDGETS[] = {
    { UI_W_PANEL, 16, 16, 928, 64, 0xff33231cu, 0xfff6823bu, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 32, 0, 0, 0xfff0e8e2u, 0x00000000u, 1.30f, UI_B_NONE, "Vita ROS2 Teleop - /cmd_vel (Objetivo 2)" },
    { UI_W_PANEL, 16, 96, 300, 130, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 110, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Sesion XRCE" },
    { UI_W_VALOR, 32, 142, 0, 0, 0xff80de4au, 0x00000000u, 1.20f, UI_B_ESTADO_CONEXION, "" },
    { UI_W_VALOR, 32, 184, 0, 0, 0xffb8a394u, 0x00000000u, 0.90f, UI_B_AGENTE, "" },
    { UI_W_PANEL, 332, 96, 298, 130, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 348, 110, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Vel lineal (triangulo/X)" },
    { UI_W_VALOR, 348, 148, 0, 0, 0xff15ccfau, 0x00000000u, 1.80f, UI_B_VEL_LINEAL, "" },
    { UI_W_PANEL, 646, 96, 298, 130, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 662, 110, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Vel lateral (stick der vert.)" },
    { UI_W_VALOR, 662, 148, 0, 0, 0xfff8bd38u, 0x00000000u, 1.80f, UI_B_VEL_LATERAL, "" },
    { UI_W_PANEL, 16, 242, 928, 120, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 256, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "/cmd_vel en vivo (geometry_msgs/Twist)" },
    { UI_W_VALOR, 32, 296, 0, 0, 0xfff0e8e2u, 0x00000000u, 1.70f, UI_B_CMD_VEL, "" },
    { UI_W_LABEL, 700, 256, 0, 0, 0xff8b7464u, 0x00000000u, 1.00f, UI_B_NONE, "publicados:" },
    { UI_W_VALOR, 820, 256, 0, 0, 0xff15ccfau, 0x00000000u, 1.00f, UI_B_CONTADOR_CMD, "" },
    { UI_W_PANEL, 16, 378, 928, 96, 0xff281a13u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 392, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Cruceta/stick izq: mover | Stick der: lateral | L/R: girar" },
    { UI_W_LABEL, 32, 428, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "TRIANGULO: +0.5 vel | X: -0.5 vel (0 = STOP) | START: salir" },
    { UI_W_LABEL, 32, 494, 0, 0, 0xff8b7464u, 0x00000000u, 0.90f, UI_B_NONE, "Fase 1 sigue viva: /vita_hello a 1 Hz + eco de /pc_hello abajo" },
    { UI_W_VALOR, 620, 494, 0, 0, 0xff8b7464u, 0x00000000u, 0.90f, UI_B_ULTIMO_PC_HELLO, "" },
};

#define UI_NUM_WIDGETS (sizeof UI_WIDGETS / sizeof UI_WIDGETS[0])

#endif /* VITA_UI_LAYOUT_H */
