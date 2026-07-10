/**
 * config.c — Persistencia de la IP del agente (contrato en config.h).
 * Sin headers de la Vita: newlib/glibc dan fopen sobre "ux0:/..." en la
 * consola y sobre rutas normales en host (batería check-config.sh).
 */
#include "config.h"

#include <stdio.h>
#include <string.h>

bool config_ip_parse(const char *s, config_ip *out)
{
    /* Parser manual estricto (sin sscanf: acepta espacios y signos).
     * Cuatro grupos de 1-3 dígitos separados por '.', valor <= 255. */
    unsigned val[4];
    int grupo = 0;
    const char *p = s;
    while (grupo < 4) {
        if (*p < '0' || *p > '9') return false;
        unsigned v = 0;
        int digitos = 0;
        while (*p >= '0' && *p <= '9' && digitos < 4) {
            v = v * 10 + (unsigned)(*p - '0');
            p++;
            digitos++;
        }
        if (digitos > 3 || v > 255) return false;
        val[grupo++] = v;
        if (grupo < 4) {
            if (*p != '.') return false;
            p++;
        }
    }
    /* Tras el cuarto octeto solo se admite fin de línea/espacio final. */
    while (*p == '\n' || *p == '\r' || *p == ' ' || *p == '\t') p++;
    if (*p != '\0') return false;

    for (int i = 0; i < 4; i++) out->oct[i] = (uint8_t)val[i];
    return true;
}

void config_ip_format(const config_ip *ip, char *buf, size_t cap)
{
    snprintf(buf, cap, "%u.%u.%u.%u", (unsigned)ip->oct[0],
             (unsigned)ip->oct[1], (unsigned)ip->oct[2],
             (unsigned)ip->oct[3]);
}

bool config_ip_load(const char *ruta, config_ip *out)
{
    FILE *f = fopen(ruta, "r");
    if (!f) return false;
    char linea[64] = {0};
    const bool leido = fgets(linea, sizeof linea, f) != NULL;
    fclose(f);
    if (!leido) return false;
    config_ip tmp;
    if (!config_ip_parse(linea, &tmp)) return false;
    *out = tmp;
    return true;
}

bool config_ip_save(const char *ruta, const config_ip *ip)
{
    FILE *f = fopen(ruta, "w");
    if (!f) return false;
    char buf[16];
    config_ip_format(ip, buf, sizeof buf);
    const bool ok = fprintf(f, "%s\n", buf) > 0;
    fclose(f);
    return ok;
}
