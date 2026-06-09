---
title: "iTLS-Enso"
slug: itls-enso
order: 2
description: "Añade TLS 1.2 al firmware: imprescindible para que la consola descargue por HTTPS moderno."
repo: "https://github.com/SKGleba/iTLS-Enso"
essential: true
---

# iTLS-Enso

## Qué es

El firmware de la Vita se quedó congelado con TLS antiguo, así que la
mayoría de servidores HTTPS modernos rechazan sus conexiones (navegador,
descargas nativas, varias homebrew que bajan contenido). **iTLS-Enso**
instala módulos de TLS 1.2 a nivel de sistema y los engancha en el
arranque (de ahí el "-Enso").

- Repositorio: <https://github.com/SKGleba/iTLS-Enso>

## Por qué lo recomienda este proyecto

Sin TLS moderno, herramientas como VitaDeploy, PKGj o el propio navegador
fallan al descargar de GitHub y similares. Instalarlo temprano ahorra
errores raros de red "que no son culpa tuya". (Nuestra app ROS2 usa UDP
plano y NO depende de iTLS; esto es para el ecosistema.)

## Instalación

1. Descarga `iTLS-Enso.vpk` de *Releases* del repositorio.
2. Súbelo por FTP (VitaShell, SELECT) e instálalo.
3. Abre la app **iTLS-Enso** en LiveArea.
4. Pulsa el botón de **instalar los módulos** y después el de
   **enganchar al arranque (boot)**.
5. Reinicia la consola.

## Verificar

Abre el navegador de la Vita y entra en `https://github.com` — debe cargar
sin error de certificado/conexión.

## Notas

- Compatible con firmware 3.60–3.74 con HENkaku/enso.
- Si en el futuro restauras o actualizas el firmware, repite el proceso.
