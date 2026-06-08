---
name: vita-deploy-logs
description: Use when deploying a built .vpk to a real PS Vita over FTP and capturing its runtime logs — drives the upload/install/launch loop and network log capture.
---

## Cuándo usar esta skill

Invocar esta skill cuando se tenga un `.vpk` construido (con la skill `vita-build-package`) y se quiera desplegarlo en una PS Vita real para probarlo y capturar sus logs de ejecución. Cubre el ciclo completo: subida por FTP, instalación, lanzamiento y lectura de logs por red.

---

## Precondiciones

Antes de comenzar, verificar que se cumplen todas las condiciones siguientes:

1. **La PS Vita tiene VitaShell instalado** y está en **modo FTP activo**. Para activar el modo FTP en VitaShell: abrir VitaShell → pulsar `Select`. La consola muestra su dirección IP y puerto (normalmente `:1337`).

2. **La Vita y el PC están en la misma red local.** Anotar la IP de la Vita (p. ej. `192.168.1.XXX`) y el puerto FTP (p. ej. `1337`). Estos valores se usan en todos los comandos de subida.

3. **El `.vpk` existe y tiene tamaño mayor que cero** (verificado con la skill `vita-build-package`).

4. **`curl` está disponible en el PC** o se tiene un cliente FTP alternativo.

---

## Paso 1 — Subir el `.vpk` a la Vita por FTP

Usar `curl` para transferir el archivo al almacenamiento de la Vita:

```bash
curl -T <app>.vpk "ftp://<vita-ip>:1337/ux0:/<app>.vpk"
```

- `ux0:` es la tarjeta de memoria (o almacenamiento interno según el modelo).
- Reemplazar `<vita-ip>` con la IP que muestra VitaShell y `<app>.vpk` con el nombre del archivo.

Si se prefiere un cliente FTP gráfico (FileZilla, etc.), conectar a `<vita-ip>:1337` sin credenciales (acceso anónimo) y copiar el `.vpk` a `ux0:/`.

**Nota de estado — validar en hardware:** la velocidad de transferencia por WiFi varía; archivos grandes pueden tardar varios segundos. Confirmar que la transferencia completa antes de continuar.

---

## Paso 2 — Instalar desde VitaShell

Una vez transferido el `.vpk`:

1. En VitaShell, navegar a `ux0:/`.
2. Seleccionar el archivo `.vpk`.
3. Pulsar `X` para instalar. VitaShell ejecuta la instalación y añade la app a la LiveArea.
4. Salir de VitaShell.

Si ya existe una versión anterior instalada con el mismo ID de título, VitaShell preguntará si sobreescribir. Confirmar que sí para actualizar.

---

## Paso 3 — Lanzar la app y capturar logs

### Método de captura de logs

La PS Vita (homebrew) no tiene salida de consola accesible directamente. Los logs de ejecución se capturan por red redirigiendo `sceClibPrintf` (o un wrapper equivalente) a un socket UDP hacia el PC. Este es el método habitual en el ecosistema homebrew (estilo PrincessLog).

**En el PC**, antes de lanzar la app, poner a escuchar el receptor de logs:

```bash
# Con netcat en modo UDP:
nc -u -l <puerto>

# Con socat (alternativa más robusta):
socat UDP-RECV:<puerto> STDOUT
```

Reemplazar `<puerto>` con el puerto UDP configurado en el código de la app (p. ej. `18194`, valor habitual en PrincessLog).

**En la Vita**, lanzar la app desde la LiveArea. Los mensajes de `sceClibPrintf` / `psvDebugScreenPrintf` redirigidos a UDP aparecerán en la terminal del PC en tiempo real.

**Nota de estado — validar en hardware:** el método exacto de redirección de logs (PrincessLog, socket propio, o debugScreen) depende de cómo el código de la app inicialice la salida. Este workflow se afina tras la primera prueba en hardware real. Si la app no envía logs, revisar que la inicialización del socket de log apunta a la IP del PC y al puerto correcto.

---

## Bucle de iteración

El ciclo completo de desarrollo embebido en la Vita sigue este flujo:

```
[Editar código en el PC]
       ↓
[vita-build-package] → produce <app>.vpk
       ↓
[vita-deploy-logs: subir] → curl -T ... ftp://...
       ↓
[vita-deploy-logs: instalar] → VitaShell en la Vita
       ↓
[vita-deploy-logs: lanzar + leer logs] → nc -u -l <puerto>
       ↓
[Analizar logs, identificar el problema]
       ↓
[Volver al inicio]
```

Cada iteración completa este ciclo. No saltarse el paso de lectura de logs: en hardware embebido, la diferencia entre "compila" y "funciona" es frecuentemente visible solo en los logs de ejecución.

---

## Nota de estado general

Los pasos de esta skill están marcados como **"validar en hardware"** porque la PS Vita real del proyecto aún no se ha usado en el desarrollo. Las instrucciones reflejan el procedimiento documentado y probado por la comunidad homebrew, pero pueden requerir ajustes menores (puerto FTP, ruta de destino, método de captura de logs) según el firmware de la consola, la versión de VitaShell y la configuración de red específica.

Al realizar la primera prueba real, anotar cualquier desviación del procedimiento documentado aquí y actualizar esta skill con los valores concretos validados.
