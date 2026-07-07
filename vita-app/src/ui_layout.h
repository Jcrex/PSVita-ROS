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
    { UI_W_PANEL, 16, 16, 928, 72, 0xff33231cu, 0xfff6823bu, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 34, 0, 0, 0xfff0e8e2u, 0x00000000u, 1.40f, UI_B_NONE, "Vita ROS2 Hello - micro-ROS sobre WiFi" },
    { UI_W_PANEL, 16, 112, 456, 160, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 128, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Sesion XRCE" },
    { UI_W_VALOR, 32, 164, 0, 0, 0xff80de4au, 0x00000000u, 1.30f, UI_B_ESTADO_CONEXION, "" },
    { UI_W_VALOR, 32, 212, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_AGENTE, "" },
    { UI_W_PANEL, 488, 112, 456, 160, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 504, 128, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Publicados en /vita_hello" },
    { UI_W_VALOR, 504, 170, 0, 0, 0xff15ccfau, 0x00000000u, 2.00f, UI_B_CONTADOR_PUBLICADOS, "" },
    { UI_W_PANEL, 16, 296, 928, 128, 0xff2b1d16u, 0xff50362au, 1.00f, UI_B_NONE, "" },
    { UI_W_LABEL, 32, 312, 0, 0, 0xffb8a394u, 0x00000000u, 1.00f, UI_B_NONE, "Ultimo /pc_hello recibido" },
    { UI_W_VALOR, 32, 352, 0, 0, 0xfff0e8e2u, 0x00000000u, 1.20f, UI_B_ULTIMO_PC_HELLO, "" },
    { UI_W_LABEL, 32, 500, 0, 0, 0xff8b7464u, 0x00000000u, 1.00f, UI_B_NONE, "START = salir" },
};

#define UI_NUM_WIDGETS (sizeof UI_WIDGETS / sizeof UI_WIDGETS[0])

#endif /* VITA_UI_LAYOUT_H */
