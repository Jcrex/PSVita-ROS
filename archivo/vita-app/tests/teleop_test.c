/**
 * teleop_test.c — batería EN HOST del mapeo mandos -> Twist (teleop.c).
 *
 * Corre con scripts/check-teleop.sh (gcc del host, sin VitaSDK). Cubre la
 * tabla de docs/09-objetivo2-control-robot.md: signos REP 103, zona
 * muerta, prioridades digital-sobre-analógico, flancos de cruz/triángulo,
 * topes de las escalas y la rampa del stick derecho.
 */
#include <math.h>
#include <stdio.h>
#include <string.h>

#include "teleop.h"

static int fallos = 0;
static int total = 0;

#define CHECK(cond, msg)                                        \
    do {                                                        \
        total++;                                                \
        if (!(cond)) {                                          \
            fallos++;                                           \
            printf("FALLO: %s (linea %d)\n", msg, __LINE__);    \
        }                                                       \
    } while (0)

#define CHECK_EQ(a, b, msg) CHECK(fabs((a) - (b)) < 1e-9, msg)

/* Entrada neutra: sticks al centro, ningún botón. */
static teleop_entrada neutra(void)
{
    teleop_entrada in;
    memset(&in, 0, sizeof in);
    in.lx = in.ly = in.rx = in.ry = 128;
    return in;
}

int main(void)
{
    teleop_estado st;
    teleop_twist tw;
    teleop_entrada in;

    /* --- Normalización de ejes: centro y zona muerta dan 0; extremos ±1;
     * el borde de la zona muerta arranca en 0 (sin salto). --- */
    CHECK_EQ(teleop_normalizar_eje(128), 0.0, "centro = 0");
    CHECK_EQ(teleop_normalizar_eje(128 + TELEOP_STICK_MUERTA - 1), 0.0,
             "dentro de la zona muerta = 0");
    CHECK_EQ(teleop_normalizar_eje(128 - TELEOP_STICK_MUERTA + 1), 0.0,
             "zona muerta simetrica = 0");
    CHECK_EQ(teleop_normalizar_eje(255), 1.0, "tope derecho/abajo = +1");
    CHECK_EQ(teleop_normalizar_eje(0), -1.0, "tope izquierdo/arriba = -1");
    CHECK(teleop_normalizar_eje(128 + TELEOP_STICK_MUERTA) > 0.0 &&
              teleop_normalizar_eje(128 + TELEOP_STICK_MUERTA) < 0.05,
          "salida de la zona muerta arranca cerca de 0");

    /* --- Neutro: twist cero y escalas iniciales. --- */
    teleop_init(&st);
    CHECK_EQ(st.vel_lineal, TELEOP_VEL_INICIAL, "vel_lineal inicial");
    CHECK_EQ(st.vel_lateral, TELEOP_LATERAL_INICIAL, "vel_lateral inicial");
    in = neutra();
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, 0.0, "neutro: lin_x = 0");
    CHECK_EQ(tw.lin_y, 0.0, "neutro: lin_y = 0");
    CHECK_EQ(tw.ang_z, 0.0, "neutro: ang_z = 0");
    CHECK_EQ(tw.lin_z, 0.0, "neutro: lin_z = 0 siempre");
    CHECK_EQ(tw.ang_x, 0.0, "neutro: ang_x = 0 siempre");
    CHECK_EQ(tw.ang_y, 0.0, "neutro: ang_y = 0 siempre");

    /* --- Stick izquierdo: adelante (ly=0) => lin_x = +vel_lineal;
     * izquierda (lx=0) => ang_z positivo (REP 103). --- */
    teleop_init(&st);
    in = neutra();
    in.ly = 0;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, TELEOP_VEL_INICIAL, "stick izq arriba: lin_x = +vel");
    in = neutra();
    in.ly = 255;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, -TELEOP_VEL_INICIAL, "stick izq abajo: lin_x = -vel");
    in = neutra();
    in.lx = 0;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.ang_z, TELEOP_VEL_INICIAL, "stick izq izquierda: ang_z > 0");
    in = neutra();
    in.lx = 255;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.ang_z, -TELEOP_VEL_INICIAL, "stick izq derecha: ang_z < 0");

    /* --- Cruceta: digital a vel_lineal y con prioridad sobre el stick. --- */
    teleop_init(&st);
    in = neutra();
    in.arriba = true;
    in.ly = 255; /* stick a tope hacia atras: debe ser ignorado */
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, TELEOP_VEL_INICIAL, "cruceta arriba manda sobre stick");
    in = neutra();
    in.abajo = true;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, -TELEOP_VEL_INICIAL, "cruceta abajo: lin_x = -vel");
    in = neutra();
    in.izquierda = true;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_y, TELEOP_VEL_INICIAL, "cruceta izq: lin_y = +vel");
    in = neutra();
    in.derecha = true;
    in.rx = 0; /* stick lateral a tope contrario: ignorado */
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_y, -TELEOP_VEL_INICIAL, "cruceta der manda sobre stick");
    in = neutra();
    in.arriba = in.abajo = true;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, 0.0, "cruceta arriba+abajo se anulan");

    /* --- L/R: giro fijo, prioridad sobre el stick, L+R se anulan. --- */
    teleop_init(&st);
    in = neutra();
    in.l = true;
    in.lx = 255; /* stick pidiendo giro contrario: ignorado */
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.ang_z, TELEOP_GIRO_LR, "L: ang_z = +0.5 fijo");
    in = neutra();
    in.r = true;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.ang_z, -TELEOP_GIRO_LR, "R: ang_z = -0.5 fijo");
    in = neutra();
    in.l = in.r = true;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.ang_z, 0.0, "L+R se anulan");

    /* --- Triangulo/cruz: flancos, paso 0.5, topes 2.0 y 0.0 (stop). --- */
    teleop_init(&st);
    in = neutra();
    in.triangulo = true;
    teleop_update(&st, &in, 0.05, &tw); /* flanco: 0.5 -> 1.0 */
    CHECK_EQ(st.vel_lineal, 1.0, "triangulo sube 0.5");
    teleop_update(&st, &in, 0.05, &tw); /* mantenido: sin cambio */
    CHECK_EQ(st.vel_lineal, 1.0, "triangulo mantenido no repite");
    in.triangulo = false;
    teleop_update(&st, &in, 0.05, &tw);
    in.triangulo = true;
    teleop_update(&st, &in, 0.05, &tw); /* 1.0 -> 1.5 */
    in.triangulo = false;
    teleop_update(&st, &in, 0.05, &tw);
    in.triangulo = true;
    teleop_update(&st, &in, 0.05, &tw); /* 1.5 -> 2.0 */
    in.triangulo = false;
    teleop_update(&st, &in, 0.05, &tw);
    in.triangulo = true;
    teleop_update(&st, &in, 0.05, &tw); /* tope */
    CHECK_EQ(st.vel_lineal, TELEOP_VEL_MAX, "vel_lineal topa en 2.0");

    teleop_init(&st); /* 0.5 */
    in = neutra();
    in.cruz = true;
    teleop_update(&st, &in, 0.05, &tw); /* 0.5 -> 0.0 */
    CHECK_EQ(st.vel_lineal, 0.0, "cruz baja 0.5 (queda en stop)");
    in.cruz = false;
    teleop_update(&st, &in, 0.05, &tw);
    in.cruz = true;
    teleop_update(&st, &in, 0.05, &tw); /* suelo */
    CHECK_EQ(st.vel_lineal, 0.0, "vel_lineal no baja de 0");

    /* Con vel_lineal = 0, stick izquierdo y cruceta quedan muertos (STOP). */
    in = neutra();
    in.ly = 0;
    in.arriba = false;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_x, 0.0, "stop: stick izq no mueve");
    in = neutra();
    in.izquierda = true;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_y, 0.0, "stop: cruceta no mueve");

    /* --- Stick derecho: lateral proporcional + rampa vertical. --- */
    teleop_init(&st);
    in = neutra();
    in.rx = 0; /* izquierda a tope */
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_y, TELEOP_LATERAL_INICIAL, "stick der izq: lin_y = +lat");
    in = neutra();
    in.rx = 255;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_y, -TELEOP_LATERAL_INICIAL, "stick der der: lin_y = -lat");

    /* Rampa: 1 s a tope hacia arriba => +0.5 exacto (en 20 pasos de 50 ms). */
    teleop_init(&st);
    in = neutra();
    in.ry = 0; /* arriba a tope */
    for (int i = 0; i < 20; i++) {
        teleop_update(&st, &in, 0.05, &tw);
    }
    CHECK_EQ(st.vel_lateral, TELEOP_LATERAL_INICIAL + TELEOP_LATERAL_RAMPA,
             "1 s arriba a tope sube vel_lateral 0.5");
    /* 10 s hacia abajo: clampa en 0 y el lateral queda muerto. */
    in.ry = 255;
    for (int i = 0; i < 200; i++) {
        teleop_update(&st, &in, 0.05, &tw);
    }
    CHECK_EQ(st.vel_lateral, 0.0, "vel_lateral clampa en 0");
    in = neutra();
    in.rx = 0;
    teleop_update(&st, &in, 0.05, &tw);
    CHECK_EQ(tw.lin_y, 0.0, "vel_lateral 0: stick der no mueve");
    /* 10 s hacia arriba: clampa en el tope 2.0. */
    in = neutra();
    in.ry = 0;
    for (int i = 0; i < 200; i++) {
        teleop_update(&st, &in, 0.05, &tw);
    }
    CHECK_EQ(st.vel_lateral, TELEOP_VEL_MAX, "vel_lateral topa en 2.0");

    printf("[teleop_test] %d/%d checks OK\n", total - fallos, total);
    return fallos == 0 ? 0 : 1;
}
