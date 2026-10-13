#!/bin/bash
# Colimy installer.
#   curl -fsSL https://raw.githubusercontent.com/drarekx/colimy/main/install.sh | bash
# Options (pass after `bash -s --`):
#   --no-deps   don't install colima / docker / docker-compose with Homebrew
set -euo pipefail

REPO="drarekx/colimy"
URL="https://github.com/$REPO/releases/latest/download/Colimy.zip"
INSTALL_DEPS=1
for arg in "$@"; do
    [[ "$arg" == "--no-deps" ]] && INSTALL_DEPS=0
done

bold() { printf "\033[1m%s\033[0m\n" "$*"; }
fail() { printf "\033[31mError:\033[0m %s\n" "$*" >&2; exit 1; }

[[ "$(uname)" == "Darwin" ]] || fail "Colimy solo funciona en macOS."
major=$(sw_vers -productVersion | cut -d. -f1)
(( major >= 14 )) || fail "Colimy necesita macOS 14 (Sonoma) o posterior. Tienes $(sw_vers -productVersion)."

bold "Descargando Colimy…"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
curl -fL --progress-bar "$URL" -o "$tmp/Colimy.zip" || fail "No se pudo descargar $URL"
ditto -x -k "$tmp/Colimy.zip" "$tmp"
[[ -d "$tmp/Colimy.app" ]] || fail "El archivo descargado no contiene Colimy.app"

# Close a running copy so it can be replaced.
if pgrep -x Colimy >/dev/null; then
    bold "Cerrando Colimy…"
    osascript -e 'quit app "Colimy"' 2>/dev/null || true
    sleep 1
    pkill -x Colimy 2>/dev/null || true
fi

dest="/Applications"
if [[ ! -w "$dest" ]]; then
    dest="$HOME/Applications"
    mkdir -p "$dest"
fi
rm -rf "$dest/Colimy.app"
mv "$tmp/Colimy.app" "$dest/"
# The app is not notarized; skip the Gatekeeper prompt for this copy.
xattr -dr com.apple.quarantine "$dest/Colimy.app" 2>/dev/null || true
bold "Instalado en $dest/Colimy.app"

if (( INSTALL_DEPS )); then
    brew=""
    for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew "$(command -v brew 2>/dev/null || true)"; do
        [[ -n "$candidate" && -x "$candidate" ]] && { brew="$candidate"; break; }
    done
    if [[ -n "$brew" ]]; then
        # Docker Desktop also provides the docker CLI and compose; don't install them twice.
        tools=(colima docker docker-compose)
        if command -v docker >/dev/null 2>&1 && ! "$brew" list --formula docker >/dev/null 2>&1; then
            tools=(colima)
        fi
        missing=()
        for tool in "${tools[@]}"; do
            "$brew" list --formula "$tool" >/dev/null 2>&1 || missing+=("$tool")
        done
        if (( ${#missing[@]} )); then
            bold "Instalando ${missing[*]}…"
            "$brew" install "${missing[@]}"
        fi
        # Homebrew's compose plugin lives outside Docker's default plugin folder.
        plugins="$("$brew" --prefix)/lib/docker/cli-plugins"
        config="$HOME/.docker/config.json"
        dockerbin="$("$brew" --prefix)/bin/docker"
        [[ -x "$dockerbin" ]] || dockerbin=docker
        if [[ -d "$plugins" ]] && ! "$dockerbin" compose version >/dev/null 2>&1; then
            if [[ ! -f "$config" ]]; then
                mkdir -p "$HOME/.docker"
                printf '{\n  "cliPluginsExtraDirs": ["%s"]\n}\n' "$plugins" > "$config"
                bold "Configurado docker compose en $config"
            else
                echo
                echo "Para usar «docker compose», añade esto a $config:"
                echo "  \"cliPluginsExtraDirs\": [\"$plugins\"]"
            fi
        fi
    else
        echo
        echo "Colimy necesita Colima y el cliente de Docker."
        echo "Instala Homebrew (https://brew.sh) y luego ejecuta:  brew install colima docker docker-compose"
    fi
fi

open "$dest/Colimy.app"
bold "¡Listo! Colimy está en la barra de menú."
