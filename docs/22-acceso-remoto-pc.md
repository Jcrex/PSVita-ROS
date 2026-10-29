# 22 — Acceso remoto al PC de desarrollo desde la laptop

**Fecha:** 2026-10-29. **Estado:** recomendación escrita, **sin aplicar todavía** (falta instalar y probar).

**Para qué:** seguir el proyecto desde la laptop cuando no se esté en la red de casa (192.168.1.x):
ver el progreso, lanzar compilaciones largas (G3 tarda 1–2 h) y controlar el PC CachyOS
(`cachyos-x8664`, 192.168.1.65) a distancia.

## Qué hay ya en el PC (comprobado el 2026-10-29)

| Pieza | Estado |
|---|---|
| `sshd` | instalado, **habilitado y activo**, config por defecto (sin `sshd_config.d`) |
| Sunshine (escritorio remoto) | instalado |
| Suspensión automática de KDE (enchufado) | desactivada (`AutoSuspendAction=0`) |
| Escritorio | KDE Plasma sobre Wayland |
| Tailscale, tmux | **no instalados** (están en los repos de CachyOS; requieren `sudo`) |
| `claude remote-control` | disponible en el Claude Code instalado |

## Recomendación: Tailscale + SSH + tmux (+ Sunshine/Moonlight opcional)

**Por qué Tailscale:** crea una red privada (VPN *mesh* WireGuard) entre la laptop y el PC.
No hay que abrir puertos en el router, funciona detrás de CGNAT y en redes de universidad
(si no puede conectar directo, usa sus relés), y el SSH **no queda expuesto a internet**.

### 1. Tailscale (hacerlo ANTES de irse, con el PC delante)

En el PC:
```bash
sudo pacman -S tailscale tmux
sudo systemctl enable --now tailscaled
sudo tailscale up        # da un enlace: iniciar sesión (Google/GitHub)
tailscale ip -4          # anotar la IP 100.x.y.z
```
En la laptop (misma cuenta):
```bash
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up
ssh jcrex@cachyos-x8664  # MagicDNS resuelve el nombre del PC
```

### 2. Claves SSH en vez de contraseña

En la laptop:
```bash
ssh-keygen -t ed25519            # si no hay ya una clave
ssh-copy-id jcrex@cachyos-x8664
```
**Solo cuando ya entre sin pedir contraseña**, apagar las contraseñas en el PC:
```bash
echo "PasswordAuthentication no" | sudo tee /etc/ssh/sshd_config.d/10-seguro.conf
sudo systemctl restart sshd
```

### 3. Sesiones que sobreviven a cortes: tmux

```bash
tmux new -A -s psvita    # crea o retoma la sesión "psvita"
# salir dejándola viva: Ctrl-b y luego d
```
Toda compilación larga (G3) se lanza **dentro de tmux**.

### 4. Claude Code en remoto

- **Por SSH:** dentro de tmux, `cd ~/Proyectos/PSVita-ROS && claude --continue`.
- **Remote Control (sin VPN):** dentro de tmux en el PC,
  `cd ~/Proyectos/PSVita-ROS && claude remote-control --name psvita-pc`. La sesión aparece en
  claude.ai/code y en la app móvil de Claude. El proceso debe seguir vivo en el PC (por eso, en tmux).
  `claude remote-control -c` retoma la última sesión de esa carpeta.

### 5. Escritorio remoto (opcional): Sunshine + Moonlight

```bash
systemctl --user enable --now sunshine   # en el PC
# configurar usuario en https://localhost:47990
```
En la laptop, instalar **Moonlight** y añadir el PC por su nombre/IP de Tailscale.
No abrir los puertos de Sunshine en el router: solo por Tailscale.

### 6. Que el PC siga accesible tras un reinicio o un corte de luz

- **Autologin** en KDE: Preferencias del sistema → Pantalla de inicio de sesión (SDDM) →
  Comportamiento → iniciar sesión automáticamente (si no, Sunshine no tiene escritorio que mostrar).
  Tailscale y sshd arrancan como servicios del sistema y no lo necesitan.
- **BIOS:** "Restore on AC power loss" = encendido. Wake-on-LAN desde fuera de casa no es práctico.

### 7. Prueba antes de irse

Conectar la laptop a los **datos del móvil** (no al WiFi de casa) y probar `ssh` y Moonlight.

## Límites

- Lo que necesita la **Vita física** (deploy por FTP/USB, probar en hardware: G4+) no se puede hacer
  en remoto. G3 (compilar la plantilla y `verify_runtime.py`) sí, entero.
- El PC tiene que quedar **encendido**.

## Dónde retomar el proyecto

`docs/06-bitacora-estado.md`, primeros bloques (2026-10-29, 2.ª sesión): **G1 y G2 verdes**; siguiente
paso exacto **G3** (VitaGL del port + `VITAGL_ROOT=… tools/build-godot-template.sh`, en tmux).
