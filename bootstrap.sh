#!/bin/bash
set -euo pipefail

# ==============================================================================
# Seed-Bootstrap (public)
#
# Schliesst das Henne-Ei-Problem auf frischen Maschinen: erzeugt den GitHub-Key,
# installiert chezmoi und zieht die (privaten) Dotfiles. Danach stehen die
# Rollen-Bootstraps unter ~/.local/share/provisioning/ bereit.
#
# Aufruf (frische Maschine, nur curl noetig):
#   curl -fsSL https://raw.githubusercontent.com/decebu/bootstrap/main/bootstrap.sh | bash
#   curl -fsSL .../bootstrap.sh | bash -s -- server     # Rolle direkt starten
#
# Dieses Skript enthaelt bewusst KEINE internen Informationen. Ohne manuelle
# Freischaltung des erzeugten Keys im GitHub-Account passiert hier nichts
# Zugriffsrelevantes.
# ==============================================================================

GH_USER="decebu"
DOTFILES_REPO="git@github.com:${GH_USER}/dotfiles.git"
ROLE="${1:-}"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Bei "curl | bash" haengt stdin an der Pipe -> Prompts vom Terminal lesen
if [ ! -t 0 ]; then
    if [ -e /dev/tty ]; then
        exec < /dev/tty
    else
        echo -e "${RED}Kein Terminal verfuegbar - interaktive Eingaben unmoeglich. Abbruch.${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}### Seed-Bootstrap: GitHub-Key + chezmoi + Dotfiles ###${NC}"
echo ""

# ------------------------------------------------------------------
# 1. Basiswerkzeuge
# ------------------------------------------------------------------
if ! command -v git >/dev/null 2>&1 || ! command -v curl >/dev/null 2>&1; then
    echo -e "${YELLOW}--- 1. Installiere git/curl ---${NC}"
    sudo apt update && sudo apt install -y git curl
fi

# ------------------------------------------------------------------
# 2. GitHub SSH Key
# ------------------------------------------------------------------
SSH_KEY_NAME="id_ed25519_github"
SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"

echo -e "${YELLOW}--- 2. GitHub SSH Key ---${NC}"
if [ ! -f "$SSH_KEY_PATH" ]; then
    DEFAULT_COMMENT="$(hostname)"
    read -r -p "Kommentar fuer den Key [$DEFAULT_COMMENT]: " SSH_COMMENT
    SSH_COMMENT=${SSH_COMMENT:-$DEFAULT_COMMENT}
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    ssh-keygen -t ed25519 -C "$SSH_COMMENT" -f "$SSH_KEY_PATH" -N ""
    echo -e "${GREEN}Key erstellt.${NC}"
fi

if ! grep -q "$SSH_KEY_NAME" "$HOME/.ssh/config" 2>/dev/null; then
    cat <<EOT >> "$HOME/.ssh/config"

Host github.com
  IdentityFile ~/.ssh/$SSH_KEY_NAME
  User git
EOT
    chmod 600 "$HOME/.ssh/config"
fi

# ------------------------------------------------------------------
# 3. Key bei GitHub freischalten (menschliches Gate)
# ------------------------------------------------------------------
if ! ssh -T -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "successfully authenticated"; then
    echo -e "${YELLOW}--- BITTE KEY BEI GITHUB HINTERLEGEN ---${NC}"
    echo "https://github.com/settings/ssh/new"
    echo ""
    cat "$SSH_KEY_PATH.pub"
    echo ""
    while true; do
        read -r -p "Key hochgeladen? (j/n): " yn
        case $yn in
            [Jj]* )
                if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
                    echo -e "${GREEN}Verbindung OK.${NC}"
                    break
                else
                    echo -e "${RED}GitHub akzeptiert den Key noch nicht - bitte pruefen.${NC}"
                fi
                ;;
            * ) echo "Bitte erst hochladen.";;
        esac
    done
fi

# ------------------------------------------------------------------
# 4. chezmoi + Dotfiles
# ------------------------------------------------------------------
echo -e "${YELLOW}--- 4. chezmoi + Dotfiles ---${NC}"
if ! command -v chezmoi >/dev/null 2>&1; then
    sudo sh -c "$(curl -fsLS get.chezmoi.io)" -- -b /usr/local/bin
fi
chezmoi init --apply "$DOTFILES_REPO"
echo -e "${GREEN}Dotfiles angewendet.${NC}"

# ------------------------------------------------------------------
# 5. Rollen-Bootstrap starten
# ------------------------------------------------------------------
PROV_DIR="$HOME/.local/share/provisioning"

echo ""
echo -e "${YELLOW}--- 5. Rollen-Bootstrap ---${NC}"

mapfile -t CANDIDATES < <(find "$PROV_DIR" -maxdepth 2 -name 'bootstrap_*.sh' 2>/dev/null | sort)
if [ ${#CANDIDATES[@]} -eq 0 ]; then
    echo -e "${RED}Keine Bootstraps unter $PROV_DIR gefunden.${NC}"
    exit 0
fi

TARGET=""
if [ -n "$ROLE" ]; then
    mapfile -t MATCHES < <(printf '%s\n' "${CANDIDATES[@]}" | grep "/$ROLE/" || true)
    if [ ${#MATCHES[@]} -eq 1 ]; then
        TARGET="${MATCHES[0]}"
    else
        echo -e "${YELLOW}Rolle '$ROLE' nicht eindeutig - bitte manuell waehlen.${NC}"
    fi
fi

if [ -z "$TARGET" ]; then
    echo "Verfuegbare Bootstraps:"
    i=1
    for c in "${CANDIDATES[@]}"; do
        echo "  [$i] ${c#"$PROV_DIR"/}"
        i=$((i+1))
    done
    read -r -p "Nummer waehlen (ENTER = keins starten): " CHOICE
    if [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le ${#CANDIDATES[@]} ]; then
        TARGET="${CANDIDATES[$((CHOICE-1))]}"
    fi
fi

if [ -n "$TARGET" ]; then
    echo -e "${GREEN}Starte: $TARGET${NC}"
    exec bash "$TARGET"
else
    echo "Kein Rollen-Bootstrap gestartet. Spaeter manuell:"
    printf '  bash %s\n' "${CANDIDATES[@]}"
fi
