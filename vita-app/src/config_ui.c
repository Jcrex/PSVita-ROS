/**
 * config_ui.c — Pantalla de configuración de IP (contrato en config_ui.h).
 *
 * SOLO VITA — VALIDAR EN HARDWARE. Dibuja con las primitivas públicas
 * de ui.h (fuente bitmap + rects) y lee los mandos con sceCtrl, igual
 * que main.c. El bucle va al ritmo del vsync (ui_frame_end hace swap
 * con vglWaitVblankStart activado en ui_init).
 */
#include "config_ui.h"

#include <psp2/ctrl.h>
#include <psp2/kernel/processmgr.h>

#include <stdio.h>

#include "ui.h"

/* Auto-repetición de ↑/↓: primer disparo inmediato, luego espera
 * inicial y cadencia (en microsegundos, sceKernelGetProcessTimeWide). */
#define REPEAT_ESPERA_US 350000
#define REPEAT_CADENCIA_US 90000

/* Paleta local (mismo empaquetado RGBA8 que el layout). */
#define C_TITULO 0xffe8e8e2
#define C_TEXTO 0xffb8b8b0
#define C_ACTIVO 0xff58c7f6
#define C_PASIVO 0xff3a3a55
#define C_PANEL 0xff1c1c3a

static void dibujar(const config_ip *ip, int sel)
{
    ui_frame_begin();
    ui_texto(64, 48, C_TITULO, 1.6f, "CONFIGURACION DE RED");
    ui_texto(64, 96, C_TEXTO, 1.0f,
             "IP del micro-ROS Agent y del netlog (la laptop):");

    /* Los 4 octetos como cajas; la seleccionada se resalta. */
    char num[8];
    for (int i = 0; i < 4; i++) {
        const float x = 64.0f + (float)i * 150.0f;
        ui_rect(x, 150.0f, 130.0f, 72.0f, i == sel ? C_ACTIVO : C_PASIVO);
        ui_rect(x + 3, 153.0f, 124.0f, 66.0f, C_PANEL);
        snprintf(num, sizeof num, "%3u", (unsigned)ip->oct[i]);
        ui_texto(x + 34, 172.0f, i == sel ? C_ACTIVO : C_TITULO, 2.0f, num);
        if (i < 3) ui_texto(x + 134, 178.0f, C_TEXTO, 2.0f, ".");
    }

    ui_texto(64, 280, C_TEXTO, 1.0f,
             "IZQ/DER: octeto   ARRIBA/ABAJO: valor (manten = rapido)");
    ui_texto(64, 312, C_TEXTO, 1.0f,
             "TRIANGULO: valor por defecto   X: confirmar y conectar");
    ui_texto(64, 376, C_PASIVO, 1.0f,
             "Se guarda en ux0:/data/vitaros/agent_ip.txt");
    ui_frame_end();
}

bool config_ui_run(config_ip *ip, const config_ip *defecto)
{
    int sel = 0;
    uint32_t prev = 0;
    /* Estado de auto-repetición del boton mantenido (solo ↑/↓). */
    uint32_t rep_boton = 0;
    uint64_t rep_siguiente = 0;

    for (;;) {
        SceCtrlData ctrl;
        sceCtrlPeekBufferPositive(0, &ctrl, 1);
        const uint32_t ahora_btn = ctrl.buttons;
        const uint32_t flanco = ahora_btn & ~prev;
        prev = ahora_btn;
        const uint64_t t = sceKernelGetProcessTimeWide();

        if (flanco & SCE_CTRL_CROSS) return true;
        if (flanco & SCE_CTRL_TRIANGLE) *ip = *defecto;
        if (flanco & SCE_CTRL_LEFT) sel = (sel + 3) % 4;
        if (flanco & SCE_CTRL_RIGHT) sel = (sel + 1) % 4;

        /* ↑/↓ con auto-repetición: flanco dispara ya y arma el timer;
         * mantener repite a cadencia fija. Soltar desarma. */
        const uint32_t updown =
            ahora_btn & (SCE_CTRL_UP | SCE_CTRL_DOWN);
        int delta = 0;
        if (flanco & SCE_CTRL_UP) delta = 1;
        if (flanco & SCE_CTRL_DOWN) delta = -1;
        if (delta != 0) {
            rep_boton = updown;
            rep_siguiente = t + REPEAT_ESPERA_US;
        } else if (updown && updown == rep_boton && t >= rep_siguiente) {
            delta = (updown & SCE_CTRL_UP) ? 1 : -1;
            rep_siguiente = t + REPEAT_CADENCIA_US;
        } else if (!updown) {
            rep_boton = 0;
        }
        if (delta != 0) {
            /* Envuelve 0..255 (uint8_t lo hace solo, documentado). */
            ip->oct[sel] = (uint8_t)(ip->oct[sel] + delta);
        }

        dibujar(ip, sel);
    }
}
