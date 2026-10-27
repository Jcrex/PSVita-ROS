# `tools/hwprobe/` — sonda de hardware de la Vita

> **Estado: SIN COMPILAR NI EJECUTAR** (escrita en la laptop; validar en el
> PC y en hardware). Propósito: cerrar los **[?]** de
> `docs/14-hardware-vita-memoria-hilos-optimizacion.md` §9.

Mide y envía por UDP (netlog) relojes, núcleos admitidos, ancho de banda de
memoria por tipo de bloque y memoria libre / heap máximo.

```bash
# PC (VitaSDK):
source tools/env-devpc.sh
cmake -DCMAKE_TOOLCHAIN_FILE=$VITASDK/share/vita.toolchain.cmake -B tools/hwprobe/build tools/hwprobe
cmake --build tools/hwprobe/build                       # -> hwprobe.vpk
cmake -DEXTENDED_MEMORY=ON -B tools/hwprobe/build-ext tools/hwprobe && cmake --build tools/hwprobe/build-ext
# laptop:
tools/netlog-listen.sh 9999
```

Instalar el `.vpk` por FTP/USB como la app principal (`docs/guias-vita/`).
Pegar la salida en `docs/14` §9 y quitar el marcador **[?]** de lo resuelto.
