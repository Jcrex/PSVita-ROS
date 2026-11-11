/**
 * hwprobe.c — sonda de hardware de la PS Vita (docs/14 §9).
 *
 * ¡SIN COMPILAR NI EJECUTAR! Se escribió en la laptop sin VitaSDK ni Vita:
 * validar en el PC (compilación) y en hardware (resultados). Los nombres de
 * funciones salen de vita-headers; si alguna firma no compila, corregir
 * contra $VITASDK/arm-vita-eabi/include/psp2/.
 *
 * Qué mide (cada bloque responde a un [?] de docs/14):
 *   E-H1  relojes (scePower*) y tiempo de un bucle f32 a 333 y 444 MHz
 *   E-H2  núcleos que admite un homebrew (4 hilos con máscara de afinidad)
 *   E-H3  ancho de banda de memcpy en RAM cacheada / no cacheada / CDRAM
 *   E-H4  memoria libre (sceKernelGetFreeMemorySize) y heap máximo de malloc
 * Salida: por UDP con netlog (mismo receptor que la app: tools/netlog-listen.sh).
 */
#include <psp2/kernel/clib.h>
#include <psp2/kernel/processmgr.h>
#include <psp2/kernel/sysmem.h>
#include <psp2/kernel/threadmgr.h>
#include <psp2/power.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>

#include "net_udp.h"
#include "netlog.h"

#ifndef NETLOG_IP
#define NETLOG_IP "192.168.1.108"
#endif
#ifndef NETLOG_PORT
#define NETLOG_PORT 9999
#endif

/* Log + pausa corta: UDP sin control de flujo pierde líneas si van en ráfaga. */
#define LOG(...)                       \
    do {                               \
        netlog_printf(__VA_ARGS__);    \
        sceKernelDelayThread(30000);   \
    } while (0)

/* ----------------------------------------------------------------- E-H1 */
static uint64_t float_loop_us(void)
{
    volatile float acc = 1.0f;
    uint64_t t0 = sceKernelGetProcessTimeWide();
    for (int i = 0; i < 20000000; i++) {
        acc = acc * 1.0000001f + 0.0000001f;
    }
    return sceKernelGetProcessTimeWide() - t0;
}

static void probe_clocks(void)
{
    LOG("[hwprobe] relojes actuales MHz: arm=%d bus=%d gpu=%d xbar=%d",
        scePowerGetArmClockFrequency(), scePowerGetBusClockFrequency(),
        scePowerGetGpuClockFrequency(), scePowerGetGpuXbarClockFrequency());

    int original = scePowerGetArmClockFrequency();
    LOG("[hwprobe] bucle f32 20M iter a %d MHz: %llu us", original,
        (unsigned long long)float_loop_us());

    static const int tries[] = { 333, 444 };
    for (unsigned i = 0; i < sizeof tries / sizeof tries[0]; i++) {
        int rc = scePowerSetArmClockFrequency(tries[i]);
        LOG("[hwprobe] set arm=%d -> rc=0x%08X, ahora=%d MHz", tries[i],
            (unsigned)rc, scePowerGetArmClockFrequency());
        LOG("[hwprobe] bucle f32 a %d MHz: %llu us",
            scePowerGetArmClockFrequency(),
            (unsigned long long)float_loop_us());
    }
    scePowerSetArmClockFrequency(original); /* restaurar */
}

/* ----------------------------------------------------------------- E-H2 */
static volatile int g_cpu_seen[4];
static volatile int g_cpu_last[4];

static int core_thread(SceSize args, void *argp)
{
    (void)args;
    int idx = *(int *)argp;
    volatile uint32_t x = 0;
    for (uint32_t i = 0; i < 30000000u; i++) { /* trabajo para que la planifique */
        x += i;
    }
    SceKernelThreadInfo info;
    memset(&info, 0, sizeof info);
    info.size = sizeof info;
    if (sceKernelGetThreadInfo(sceKernelGetThreadId(), &info) == 0) {
        g_cpu_seen[idx] = info.currentCpuId;
        g_cpu_last[idx] = info.lastExecutedCpuId;
    } else {
        g_cpu_seen[idx] = g_cpu_last[idx] = -99;
    }
    return 0;
}

static void probe_cores(void)
{
    for (int core = 0; core < 4; core++) {
        int mask = (1 << core) << 16; /* bits 16-19 = afinidad (threadmgr.h) */
        int idx = core;
        SceUID th = sceKernelCreateThread("hwprobe-core", core_thread,
                                          0x10000100, 0x10000, 0, mask, NULL);
        if (th < 0) {
            LOG("[hwprobe] núcleo %d: create_thread falló rc=0x%08X (máscara no admitida?)",
                core, (unsigned)th);
            continue;
        }
        sceKernelStartThread(th, sizeof idx, &idx);
        sceKernelWaitThreadEnd(th, NULL, NULL);
        sceKernelDeleteThread(th);
        LOG("[hwprobe] núcleo pedido %d (máscara 0x%X): currentCpuId=%d lastExecutedCpuId=%d",
            core, (unsigned)mask, g_cpu_seen[idx], g_cpu_last[idx]);
    }
}

/* ----------------------------------------------------------------- E-H3 */
#define BW_BYTES (4u * 1024 * 1024)
#define BW_ITERS 16

static void bandwidth(const char *name, SceKernelMemBlockType type)
{
    SceUID blk = sceKernelAllocMemBlock(name, type, BW_BYTES, NULL);
    if (blk < 0) {
        LOG("[hwprobe] bw %-10s: alloc falló rc=0x%08X", name, (unsigned)blk);
        return;
    }
    void *base = NULL;
    sceKernelGetMemBlockBase(blk, &base);
    void *host = malloc(BW_BYTES);
    if (!host || !base) {
        LOG("[hwprobe] bw %-10s: sin base/host", name);
        goto out;
    }
    memset(host, 0xA5, BW_BYTES);

    uint64_t t0 = sceKernelGetProcessTimeWide();
    for (int i = 0; i < BW_ITERS; i++) {
        memcpy(base, host, BW_BYTES);            /* escritura al bloque */
    }
    uint64_t w_us = sceKernelGetProcessTimeWide() - t0;

    t0 = sceKernelGetProcessTimeWide();
    for (int i = 0; i < BW_ITERS; i++) {
        memcpy(host, base, BW_BYTES);            /* lectura del bloque */
    }
    uint64_t r_us = sceKernelGetProcessTimeWide() - t0;

    /* MB/s = bytes totales / microsegundos (1 MB/s = 1 byte/us) */
    double total = (double)BW_BYTES * BW_ITERS;
    LOG("[hwprobe] bw %-10s: escritura %.1f MB/s, lectura %.1f MB/s", name,
        total / (double)(w_us ? w_us : 1), total / (double)(r_us ? r_us : 1));
out:
    free(host);
    sceKernelFreeMemBlock(blk);
}

static void probe_bandwidth(void)
{
    bandwidth("RAM-cach", SCE_KERNEL_MEMBLOCK_TYPE_USER_MAIN_RW);
    bandwidth("RAM-nocach", SCE_KERNEL_MEMBLOCK_TYPE_USER_MAIN_NC_RW);
    bandwidth("CDRAM", SCE_KERNEL_MEMBLOCK_TYPE_USER_CDRAM_RW);
}

/* ----------------------------------------------------------------- E-H4 */
static void probe_memory(void)
{
    SceKernelFreeMemorySizeInfo fi;
    memset(&fi, 0, sizeof fi);
    fi.size = sizeof fi;
    int rc = sceKernelGetFreeMemorySize(&fi);
    LOG("[hwprobe] libre (rc=0x%08X): user=%d KB cdram=%d KB phycont=%d KB",
        (unsigned)rc, fi.size_user / 1024, fi.size_cdram / 1024,
        fi.size_phycont / 1024);

    /* Heap de newlib: pedir trozos de 1 MiB hasta que falle. */
    enum { MAX_CHUNKS = 1024 };
    static void *chunks[MAX_CHUNKS];
    int n = 0;
    while (n < MAX_CHUNKS && (chunks[n] = malloc(1024 * 1024)) != NULL) {
        n++;
    }
    LOG("[hwprobe] malloc máximo en trozos de 1 MiB: %d MiB (defecto newlib = 128)", n);
    while (n > 0) {
        free(chunks[--n]);
    }
}

int main(void)
{
    sceKernelDelayThread(2 * 1000 * 1000);
    if (net_udp_init() != NET_UDP_OK || !netlog_init(NETLOG_IP, NETLOG_PORT)) {
        sceClibPrintf("[hwprobe] sin red/netlog\n");
        sceKernelDelayThread(3 * 1000 * 1000);
        return 1;
    }
    LOG("[hwprobe] === inicio (docs/14 §9) ===");
    probe_memory();
    probe_cores();
    probe_clocks();
    probe_bandwidth();
    LOG("[hwprobe] === fin ===");
    sceKernelDelayThread(2 * 1000 * 1000);
    netlog_shutdown();
    net_udp_shutdown();
    return 0;
}
