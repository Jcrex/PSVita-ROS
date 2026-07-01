---
title: "VitaShell"
slug: vitashell
order: 1
description: "Gestor de archivos y servidor FTP/USB: la puerta de entrada de todo homebrew (y de nuestra app ROS2)."
repo: "https://github.com/RealYoti/VitaShell"
essential: true
---

# VitaShell

## Qué es

El gestor de archivos por excelencia de la Vita hackeada: explora todas las
particiones (`ux0:`, `ur0:`, `uma0:`...), instala `.vpk`, copia/borra/edita
archivos, y levanta un **servidor FTP** o conexión **USB** para transferir
desde el PC. Para este proyecto es la herramienta nº 1: así llega
`vita-ros2-hello.vpk` a la consola y así se inspeccionan sus logs.

- Repositorio (fork mantenido): <https://github.com/RealYoti/VitaShell>
- Original (archivado, de TheOfficialFloW): <https://github.com/TheOfficialFloW/VitaShell>

## Instalación

Si seguiste <https://vita.hacks.guide/>, **ya lo tienes** (la guía lo
instala como parte del proceso). Si no:

1. Descarga `VitaShell.vpk` desde la página de *Releases* del repositorio.
2. Súbelo a la consola por el método que tengas disponible (la primera vez
   suele hacerse con VitaDeploy, o con el VitaShell preexistente si
   actualizas).
3. Instálalo abriendo el `.vpk` (X → instalar → aceptar permisos extendidos).

### Actualizar

VitaShell se instala a sí mismo: sube el `.vpk` nuevo por FTP y ábrelo con
la versión vieja.

## Uso que hace este proyecto

### Modo FTP (deploy de la app)

1. Abre VitaShell y pulsa **SELECT** → muestra `ftp://192.168.1.X:1337`.
2. Desde la laptop/PC:
   ```bash
   curl -T build/vita-ros2-hello.vpk "ftp://192.168.1.X:1337/ux0:/"
   ```
3. En VitaShell: `ux0:/` → X sobre el `.vpk` → instalar.

La skill `vita-deploy-logs` del repo automatiza este bucle.

### Modo USB (deploy sin red)

Si tienes la Vita conectada por cable al PC (útil en el PC CachyOS de
desarrollo, que no siempre comparte WiFi con la consola):

1. Conecta el cable USB Vita↔PC.
2. En VitaShell, pulsa **SELECT**: al detectar el cable, activa modo USB
   en vez de FTP (la pantalla cambia y avisa que la partición está
   expuesta como almacenamiento USB).
3. En el PC (Linux), identifica el dispositivo nuevo:
   ```bash
   lsblk
   ```
   Debe aparecer un disco extraíble del tamaño de tu tarjeta de memoria
   (la partición de `ux0:` va formateada en exFAT — soportado nativamente
   desde el kernel 5.4, sin paquetes extra en CachyOS).
4. Móntalo sin sudo con udisks:
   ```bash
   udisksctl mount -b /dev/sdX1   # sustituye sdX1 por lo que muestre lsblk
   ```
5. Copia el `.vpk`:
   ```bash
   cp vita-app/build/vita-ros2-hello.vpk /run/media/$USER/*/
   ```
6. Desmonta limpio **antes** de tocar nada en la Vita:
   ```bash
   udisksctl unmount -b /dev/sdX1
   ```
7. En la Vita: pulsa **SELECT** de nuevo para salir del modo USB, vuelve a
   `ux0:/` en VitaShell, pulsa X sobre el `.vpk` → instalar → acepta el
   aviso de permisos extendidos (la app usa red).
8. Opcional: borra el `.vpk` de `ux0:/` una vez instalado, para no gastar
   espacio de la tarjeta.

> Nota: el `.vpk` de este proyecto trae **la IP del agente/netlog
> baked-in** (por defecto `192.168.1.108`, la laptop — ver
> `vita-app/CMakeLists.txt`). Instalarlo desde el PC por USB no cambia
> eso: para ver la sesión XRCE en marcha (criterios de Fase 1) necesitas
> tener el agente micro-ROS y el listener de netlog corriendo en la
> laptop y ambas máquinas en la misma WiFi (pasos 6-9 de
> `docs/06-bitacora-estado.md`).

### Atajos útiles

| Tecla | Acción |
|---|---|
| SELECT | FTP on/off (USB si está conectado el cable) |
| TRIANGLE | menú contextual (copiar, mover, borrar, propiedades) |
| START | ajustes de VitaShell |
| L / R | cambiar de pestaña / página |

## Problemas comunes

- **"No se puede instalar"** → falta *Activar apps inseguras* en Ajustes → HENkaku.
- **FTP rechaza la conexión** → la Vita entró en suspensión; tócala y
  reactiva SELECT. Mantén la pantalla encendida durante transferencias.
- **La IP cambia** → asigna IP fija a la Vita en el router (recomendado
  para este proyecto: la usarás constantemente).
