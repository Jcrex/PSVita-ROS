/* dlfcn.h — STUB para VitaSDK (newlib).
 *
 * Por que existe:
 *   La newlib de la Vita NO provee dlfcn.h porque la Vita no tiene carga
 *   dinamica de librerias (dlopen/dlsym). Sin embargo, codigo stock de Godot
 *   —p.ej. drivers/gles2/rasterizer_storage_gles2.cpp— hace
 *   `#include <dlfcn.h>` para CUALQUIER target GLES2 (guardado solo por
 *   `#ifndef GLES_OVER_GL`). En la Vita las llamadas reales a dlopen/dlsym
 *   quedan dentro de bloques `#ifdef IPHONE_ENABLED`/`ANDROID_ENABLED`, que
 *   NO se compilan, asi que son codigo muerto: basta con que el header exista
 *   para que el `#include` no rompa. No se referencia ningun simbolo dl*, por
 *   eso este stub es solo declaraciones (sin implementacion) y no hay que
 *   enlazar ninguna libdl.
 *
 *   (El unico consumidor que SI llamaba a dlopen era Bullet/clew.c; ese se
 *   excluye aparte con godot/patches/bullet-vita-no-clew.patch.)
 *
 * build-vita-template.sh copia este archivo a
 *   $VITASDK/arm-vita-eabi/include/dlfcn.h  (si no existe ya).
 */
#ifndef _DLFCN_H_STUB_VITA
#define _DLFCN_H_STUB_VITA

#ifdef __cplusplus
extern "C" {
#endif

/* Flags POSIX; valores irrelevantes en la Vita (nunca se usan en runtime). */
#define RTLD_LAZY   0x0001
#define RTLD_NOW    0x0002
#define RTLD_LOCAL  0x0000
#define RTLD_GLOBAL 0x0100

void *dlopen(const char *__filename, int __flag);
int   dlclose(void *__handle);
void *dlsym(void *__handle, const char *__symbol);
char *dlerror(void);

#ifdef __cplusplus
}
#endif

#endif /* _DLFCN_H_STUB_VITA */
