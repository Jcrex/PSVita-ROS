#!/usr/bin/env bash
# install-skills.sh — instala (o comprueba/desinstala) las skills de IA del repo
# en Claude Code. Instrucciones completas: skills/INSTALAR.md.
#
#   tools/install-skills.sh                 enlaces simbólicos en ~/.claude/skills (recomendado)
#   tools/install-skills.sh --project       enlaces en <repo>/.claude/skills (solo este repo; .claude/ es local)
#   tools/install-skills.sh --copy          copia en vez de enlazar (si los enlaces no se detectan)
#   tools/install-skills.sh --check         solo verifica la instalación y las skills
#   tools/install-skills.sh --uninstall     quita lo que instaló este script
#   tools/install-skills.sh --dest DIR      destino explícito (combinable con --copy/--check/--uninstall)
#
# Es idempotente: se puede ejecutar las veces que haga falta.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$REPO/skills"
DEST="$HOME/.claude/skills"
MODE=link
ACTION=install

while [[ $# -gt 0 ]]; do
    case "$1" in
        --project)   DEST="$REPO/.claude/skills" ;;
        --copy)      MODE=copy ;;
        --check)     ACTION=check ;;
        --uninstall) ACTION=uninstall ;;
        --dest)      DEST="${2:?falta el directorio}"; shift ;;
        -h|--help)   sed -n '2,13p' "$0"; exit 0 ;;
        *) echo "Opción desconocida: $1" >&2; exit 2 ;;
    esac
    shift
done

# Las skills son las carpetas de skills/ que tienen SKILL.md
mapfile -t SKILLS < <(cd "$SRC" && for d in */; do [[ -f "$d/SKILL.md" ]] && echo "${d%/}"; done)
[[ ${#SKILLS[@]} -gt 0 ]] || { echo "No hay skills en $SRC" >&2; exit 1; }

fail=0
ok()  { printf '  [OK]    %s\n' "$*"; }
bad() { printf '  [FALLA] %s\n' "$*"; fail=1; }

# Valida el frontmatter: '---' inicial, name == carpeta, description presente y YAML válido.
check_frontmatter() {
    local s="$1" f="$SRC/$1/SKILL.md"
    python3 -I - "$f" "$s" <<'PY' || return 1
import sys
path, want = sys.argv[1], sys.argv[2]
text = open(path, encoding="utf-8").read()
if not text.startswith("---\n"):
    sys.exit("sin frontmatter '---' al inicio")
head = text.split("---", 2)[1]
try:
    import yaml
    data = yaml.safe_load(head)
except ImportError:  # sin PyYAML: comprobación mínima línea a línea
    data = {}
    for line in head.strip().splitlines():
        k, _, v = line.partition(":")
        data[k.strip()] = v.strip().strip('"')
except Exception as e:  # YAML inválido: Claude Code no cargaría la skill
    sys.exit(f"YAML inválido: {e}")
if data.get("name") != want:
    sys.exit(f"name={data.get('name')!r} no coincide con la carpeta {want!r}")
if not data.get("description"):
    sys.exit("falta description")
PY
}

case "$ACTION" in
install)
    mkdir -p "$DEST"
    echo "Instalando ${#SKILLS[@]} skills en $DEST (modo: $MODE)"
    for s in "${SKILLS[@]}"; do
        target="$DEST/$s"
        if [[ -e "$target" && ! -L "$target" && "$MODE" == link ]]; then
            bad "$s: ya existe $target y no es un enlace (muévelo o usa --copy)"; continue
        fi
        rm -rf "$target"
        if [[ "$MODE" == link ]]; then
            ln -s "$SRC/$s" "$target"
        else
            cp -r "$SRC/$s" "$target"
        fi
        ok "$s"
    done
    chmod +x "$SRC"/*/scripts/*.sh "$SRC"/*/scripts/*.py 2>/dev/null || true
    ;;&
install|check)
    echo "Comprobando en $DEST"
    for s in "${SKILLS[@]}"; do
        if [[ ! -f "$DEST/$s/SKILL.md" ]]; then bad "$s: no instalada ($DEST/$s/SKILL.md)"; continue; fi
        if err="$(check_frontmatter "$s" 2>&1)"; then ok "$s: frontmatter válido"; else bad "$s: $err"; fi
    done
    if bash -n "$SRC/rclgd/scripts/rclgd-docs.sh" 2>/dev/null; then ok "rclgd-docs.sh: sintaxis"; else bad "rclgd-docs.sh: sintaxis"; fi
    for tool in git python3; do
        command -v "$tool" >/dev/null && ok "$tool disponible" || bad "$tool no encontrado"
    done
    [[ $fail -eq 0 ]] && echo "Todo correcto. Reinicia Claude Code para que cargue las skills." \
                      || { echo "Hay fallos (arriba)."; exit 1; }
    ;;
uninstall)
    for s in "${SKILLS[@]}"; do
        if [[ -L "$DEST/$s" ]]; then rm "$DEST/$s"; ok "quitado enlace $s"
        elif [[ -d "$DEST/$s" ]]; then rm -rf "$DEST/$s"; ok "quitada copia $s"
        fi
    done
    ;;
esac
