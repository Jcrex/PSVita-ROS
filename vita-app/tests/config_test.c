/**
 * config_test.c — Batería HOST de la persistencia de IP (src/config.c,
 * sin headers de la Vita). La corre scripts/check-config.sh, que le
 * pasa en argv[1] una ruta temporal escribible para el round-trip.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "config.h"

static int g_checks = 0;
static int g_fallos = 0;

static void check(const char *que, int cond)
{
    g_checks++;
    if (!cond) {
        g_fallos++;
        printf("FALLO %s\n", que);
    }
}

int main(int argc, char **argv)
{
    if (argc < 2) {
        fprintf(stderr, "uso: config_test <ruta-tmp>\n");
        return EXIT_FAILURE;
    }

    config_ip ip;

    /* parse: casos válidos */
    check("parse 192.168.1.108", config_ip_parse("192.168.1.108", &ip) &&
          ip.oct[0] == 192 && ip.oct[1] == 168 && ip.oct[2] == 1 &&
          ip.oct[3] == 108);
    check("parse 0.0.0.0", config_ip_parse("0.0.0.0", &ip));
    check("parse 255.255.255.255", config_ip_parse("255.255.255.255", &ip));
    check("parse con salto de linea final",
          config_ip_parse("10.0.0.1\n", &ip) && ip.oct[0] == 10);

    /* parse: casos inválidos (el archivo corrupto NO puede colar) */
    check("rechaza octeto 256", !config_ip_parse("1.2.3.256", &ip));
    check("rechaza 3 octetos", !config_ip_parse("1.2.3", &ip));
    check("rechaza 5 octetos", !config_ip_parse("1.2.3.4.5", &ip));
    check("rechaza letras", !config_ip_parse("a.b.c.d", &ip));
    check("rechaza vacio", !config_ip_parse("", &ip));
    check("rechaza espacios dentro", !config_ip_parse("1. 2.3.4", &ip));
    check("rechaza basura tras la IP", !config_ip_parse("1.2.3.4x", &ip));
    check("rechaza negativos", !config_ip_parse("-1.2.3.4", &ip));

    /* format */
    ip.oct[0] = 192; ip.oct[1] = 168; ip.oct[2] = 1; ip.oct[3] = 108;
    char buf[16];
    config_ip_format(&ip, buf, sizeof buf);
    check("format 192.168.1.108", strcmp(buf, "192.168.1.108") == 0);

    /* round-trip save -> load */
    char ruta[512];
    snprintf(ruta, sizeof ruta, "%s/agent_ip.txt", argv[1]);
    check("save", config_ip_save(ruta, &ip));
    config_ip leida = {{0, 0, 0, 0}};
    check("load", config_ip_load(ruta, &leida));
    check("round-trip identico", memcmp(&ip, &leida, sizeof ip) == 0);

    /* load de archivo inexistente: false y NO toca el out */
    config_ip intacta = {{9, 9, 9, 9}};
    check("load inexistente devuelve false",
          !config_ip_load("/ruta/que/no/existe/x.txt", &intacta));
    check("load inexistente no toca el valor", intacta.oct[0] == 9);

    /* load de archivo corrupto: false y NO toca el out */
    snprintf(ruta, sizeof ruta, "%s/corrupto.txt", argv[1]);
    FILE *f = fopen(ruta, "w");
    if (f) { fputs("no soy una ip\n", f); fclose(f); }
    check("load corrupto devuelve false", !config_ip_load(ruta, &intacta));
    check("load corrupto no toca el valor", intacta.oct[0] == 9);

    printf("%d/%d checks de config OK\n", g_checks - g_fallos, g_checks);
    return g_fallos ? EXIT_FAILURE : EXIT_SUCCESS;
}
