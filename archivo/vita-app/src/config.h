/**
 * config.h — Configuración persistente de la app: la IP del agente
 * micro-ROS / netlog (misma máquina, la laptop por defecto).
 *
 * LÓGICA PURA + stdio, SIN HEADERS DE LA VITA: compila en host y se
 * testea con scripts/check-config.sh. La pantalla interactiva que la
 * edita con los mandos vive en config_ui.{h,c} (solo Vita), y el mkdir
 * del directorio de datos lo hace main.c (sceIoMkdir).
 *
 * Persistencia: un archivo de texto con la IP en decimal punteado
 * ("192.168.1.108\n") en CONFIG_RUTA_IP. Si no existe o está corrupto,
 * se usa el valor por defecto horneado en el .vpk (AGENT_IP).
 */
#ifndef VITA_CONFIG_H
#define VITA_CONFIG_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Mismo directorio de datos que usará el modelo VBM (docs/11 §3). */
#define CONFIG_DIR "ux0:/data/vitaros"
#define CONFIG_RUTA_IP CONFIG_DIR "/agent_ip.txt"

typedef struct {
    uint8_t oct[4]; /* octetos de la IPv4, orden natural de lectura */
} config_ip;

/** "a.b.c.d" -> octetos. false si el formato no es IPv4 decimal
 *  punteado estricto (cuatro números 0-255, nada más en la línea). */
bool config_ip_parse(const char *s, config_ip *out);

/** octetos -> "a.b.c.d" (cap >= 16 para el caso peor + NUL). */
void config_ip_format(const config_ip *ip, char *buf, size_t cap);

/** Lee la IP desde `ruta`. false (sin tocar `out`) si no hay archivo
 *  o el contenido no parsea — el llamador conserva su valor por defecto. */
bool config_ip_load(const char *ruta, config_ip *out);

/** Escribe la IP en `ruta` (el directorio debe existir ya). */
bool config_ip_save(const char *ruta, const config_ip *ip);

#ifdef __cplusplus
}
#endif

#endif /* VITA_CONFIG_H */
