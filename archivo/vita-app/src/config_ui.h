/**
 * config_ui.h — Pantalla interactiva de configuración de la IP del
 * agente/netlog al arrancar la app (SOLO Vita: sceCtrl + ui.h).
 *
 * Pedida por el usuario el 2026-07-10: la IP a la que publica la Vita
 * se escribe desde la propia consola (por defecto 192.168.1.108, la
 * laptop) y se recuerda entre arranques (config.h).
 */
#ifndef VITA_CONFIG_UI_H
#define VITA_CONFIG_UI_H

#include <stdbool.h>

#include "config.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Bucle bloqueante de edición: cruceta ←/→ elige octeto, ↑/↓ lo cambia
 * (con auto-repetición al mantener), △ restaura `defecto`, X confirma.
 * `ip` entra con el valor inicial (cargado o por defecto) y sale con el
 * elegido. Devuelve false si la UI no está inicializada (sin pantalla
 * no hay edición posible: el llamador sigue con el valor inicial).
 */
bool config_ui_run(config_ip *ip, const config_ip *defecto);

#ifdef __cplusplus
}
#endif

#endif /* VITA_CONFIG_UI_H */
