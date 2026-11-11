/* dlfcn.h — STUB para VitaSDK (newlib), versión Godot 4.
 *
 * Por qué existe:
 *   La newlib de la Vita NO trae dlfcn.h (no hay carga dinámica de librerías),
 *   pero Godot 4 lo incluye sin condiciones en drivers/unix/os_unix.cpp y usa
 *   RTLD_NEXT para buscar iconv. En godot4-vita las funciones dl* las da el
 *   loader (platform/vita/loader/dl_stubs.c): dlopen y dlsym devuelven siempre
 *   NULL y NUNCA miran el handle, así que el valor de RTLD_NEXT/RTLD_DEFAULT da
 *   igual: dlsym(RTLD_NEXT, "iconv") → NULL y Godot sigue sin iconv.
 *
 *   Es un superconjunto del stub de Godot 3.5 (godot/godot35/vitasdk-stubs/),
 *   así que el histórico 3.5 sigue compilando con este instalado.
 *
 * tools/build-godot-template.sh lo copia a $VITASDK/arm-vita-eabi/include/dlfcn.h
 * si allí no existe o le falta RTLD_NEXT (p. ej. está el stub de 3.5).
 */
#ifndef _DLFCN_H_STUB_VITA
#define _DLFCN_H_STUB_VITA

#ifdef __cplusplus
extern "C" {
#endif

/* Flags POSIX; valores irrelevantes en la Vita (los stubs los ignoran). */
#define RTLD_LAZY   0x0001
#define RTLD_NOW    0x0002
#define RTLD_LOCAL  0x0000
#define RTLD_GLOBAL 0x0100

/* Pseudo-handles (mismos valores que glibc). */
#define RTLD_DEFAULT ((void *)0)
#define RTLD_NEXT    ((void *)-1)

void *dlopen(const char *__filename, int __flag);
int   dlclose(void *__handle);
void *dlsym(void *__handle, const char *__symbol);
char *dlerror(void);

#ifdef __cplusplus
}
#endif

#endif /* _DLFCN_H_STUB_VITA */
