---
title: "Adrenaline"
slug: adrenaline
order: 7
description: "Convierte el emulador ePSP oculto de la Vita en una PSP completa con CFW. Sin relación técnica con el proyecto ROS2."
repo: "https://github.com/isage/Adrenaline"
essential: false
---

# Adrenaline

## Qué es

La Vita lleva dentro un emulador de PSP oficial (ePSP). **Adrenaline** lo
desbloquea por completo: arranca un CFW de PSP (estilo 6.61 PRO/ME) dentro
de la Vita, con acceso a homebrew de PSP, juegos de PSP/PS1 y todos los
ajustes del emulador (filtrados de pantalla, plugins de PSP, etc.).

- Repositorio (fork mantenido): <https://github.com/isage/Adrenaline>
- Original (TheOfficialFloW): <https://github.com/TheOfficialFloW/Adrenaline>

## Relación con este proyecto

**Ninguna**: nuestra app es homebrew nativo de Vita, no de PSP. Se incluye
en las guías porque es parte del kit clásico de una consola desbloqueada y
el usuario lo pidió documentado.

## Instalación (resumen)

1. Descarga `Adrenaline.vpk` de *Releases* e instálalo vía FTP + VitaShell.
2. Abre Adrenaline desde LiveArea; descargará/instalará la base 6.61.
3. Sigue el asistente del primer arranque (instala los archivos del CFW).
4. Para opciones avanzadas (ubicación de ISOs, plugins PSP), consulta el
   README del repositorio.

## Notas

- Mantén **R** al arrancar Adrenaline para entrar en su recovery.
- Los juegos/homebrew de PSP viven en `ux0:pspemu/`.
- Si usas plugins de taiHEN que tocan el ePSP, pueden interferir;
  Autoplugin marca los conflictos conocidos.
