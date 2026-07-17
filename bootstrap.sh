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
#
# Aufbau-Hinweis: Alles lebt in main(), Aufruf ganz unten. Bei "curl | bash"
# liest bash das Skript stueckweise von stdin - erst der main()-Wrapper macht
# die stdin-Umleitung auf /dev/tty (fuer die Prompts) gefahrlos.
# ==============================================================================

GH_USER="decebu"
DOTFILES_REPO="git@github.com:${GH_USER}/dotfiles.git"

# Gepinnte Versionen der Shell-Erweiterungen (Supply-Chain, Audit DOT-03)
ZSH_AUTOSUGGESTIONS_TAG="v0.7.1"
ZSH_SYNTAX_HIGHLIGHTING_TAG="0.8.0"
POWERLEVEL10K_TAG="v1.20.0"

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

# Offizielle GitHub-Hostkeys (https://api.github.com/meta) pinnen, statt den
# Erstkontakt ungeprueft zu akzeptieren (Audit DOT-07).
ensure_github_hostkeys() {
    mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
    if ! grep -q '^github\.com ' "$HOME/.ssh/known_hosts" 2>/dev/null; then
        cat <<'EOT' >> "$HOME/.ssh/known_hosts"
github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOMqqnkVzrm0SdG6UOoqKLsabgH5C9okWi0dh2l9GKJl
github.com ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBEmKSENjQEezOmxkZMy7opKgwFB9nkt5YRrYMjNuG5N87uRgg6CLrbo5wAdT/y6v0mKV0U2w0WZ2YB/++Tpockg=
github.com ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCj7ndNxQowgcQnjshcLrqPEiiphnt+VTTvDP6mHBL9j1aNUkY4Ue1gvwnGLVlOhGeYrnZaMgRK6+PKCUXaDbC7qtbW8gIkhL7aGCsOr/C56SJMy/BCZfxd1nWzAOxSDPgVsmerOBYfNqltV9/hWCqBywINIR+5dIg6JTJ72pcEpEjcYgXkE2YEFXV1JHnsKgbLWNlhScqb2UmyRkQyytRLtL+38TGxkxCflmO+5Z8CSSNY7GidjMIZ7Q4zMjA2n1nGrlTDkzwDCsw+wqFPGQA179cnfGWOWRVruj16z6XyvxvjJwbz0wQZ75XK5tKSb7FNyeIEs4TT4jk+S4dhPeAUC5y+bDYirYgM4GC7uEnztnZyaVWQ7B381AK4Qdrwt51ZqExKbQpTUNn+EjqoTwvqNj4kqx5QUCI0ThS/YkOxJCXmPUWZbhjpCg56i+2aB6CmK2JGhn57K5mj0MNdBXA4/WnwH6XoPWJzK5Nyu2zB3nAZp+S5hpQs+p1vN1/wsjk=
EOT
    fi
}

# GitHub beendet "ssh -T" auch bei Erfolg mit Exit-Code 1 - deshalb Ausgabe
# einfangen (|| true) und auf den Erfolgstext pruefen, statt den Pipeline-
# Status zu verwenden (der waere mit pipefail immer "Fehler").
github_auth_ok() {
    local out
    out=$(ssh -n -T -o StrictHostKeyChecking=yes git@github.com 2>&1 || true)
    printf '%s' "$out" | grep -q "successfully authenticated"
}

main() {
    local ROLE="${1:-}"

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
    local SSH_KEY_NAME="id_ed25519_github"
    local SSH_KEY_PATH="$HOME/.ssh/$SSH_KEY_NAME"

    echo -e "${YELLOW}--- 2. GitHub SSH Key ---${NC}"
    if [ ! -f "$SSH_KEY_PATH" ]; then
        local DEFAULT_COMMENT
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
    ensure_github_hostkeys
    if ! github_auth_ok; then
        echo -e "${YELLOW}--- BITTE KEY BEI GITHUB HINTERLEGEN ---${NC}"
        echo "https://github.com/settings/ssh/new"
        echo ""
        cat "$SSH_KEY_PATH.pub"
        echo ""
        while true; do
            read -r -p "Key hochgeladen? (j/n): " yn
            case $yn in
                [Jj]* )
                    if github_auth_ok; then
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
    # 4. Shell-Umgebung (zsh + Oh My Zsh + Plugins + Powerlevel10k)
    #    Immer installieren - die Dotfiles (.zshrc) setzen sie voraus.
    # ------------------------------------------------------------------
    echo -e "${YELLOW}--- 4. Shell-Umgebung (zsh/OMZ/P10k) ---${NC}"
    if ! command -v zsh >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y zsh
    fi
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
    local ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
        git clone --depth 1 --branch "$ZSH_AUTOSUGGESTIONS_TAG" https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    fi
    if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
        git clone --depth 1 --branch "$ZSH_SYNTAX_HIGHLIGHTING_TAG" https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    fi
    if [ ! -d "$ZSH_CUSTOM/themes/powerlevel10k" ]; then
        git clone --depth 1 --branch "$POWERLEVEL10K_TAG" https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
    fi
    if [ "${SHELL:-}" != "$(command -v zsh)" ]; then
        sudo chsh -s "$(command -v zsh)" "$(whoami)"
    fi

    # ------------------------------------------------------------------
    # 5. chezmoi + Dotfiles
    # ------------------------------------------------------------------
    echo -e "${YELLOW}--- 5. chezmoi + Dotfiles ---${NC}"
    # Installer bewusst NICHT als root pipen (Audit DOT-03): Installation als
    # User nach ~/.local/bin (liegt per Dotfiles im PATH).
    export PATH="$HOME/.local/bin:$PATH"
    if ! command -v chezmoi >/dev/null 2>&1; then
        mkdir -p "$HOME/.local/bin"
        sh -c "$(curl -fsLS get.chezmoi.io)" -- -b "$HOME/.local/bin"
    fi
    chezmoi init --apply "$DOTFILES_REPO"
    echo -e "${GREEN}Dotfiles angewendet.${NC}"

    # ------------------------------------------------------------------
    # 6. Rollen-Bootstrap starten
    # ------------------------------------------------------------------
    local PROV_DIR="$HOME/.local/share/provisioning"

    echo ""
    echo -e "${YELLOW}--- 6. Rollen-Bootstrap ---${NC}"

    local CANDIDATES=()
    mapfile -t CANDIDATES < <(find "$PROV_DIR" -maxdepth 2 -name 'bootstrap_*.sh' 2>/dev/null | sort)
    if [ ${#CANDIDATES[@]} -eq 0 ]; then
        echo -e "${RED}Keine Bootstraps unter $PROV_DIR gefunden.${NC}"
        exit 0
    fi

    local TARGET=""
    if [ -n "$ROLE" ]; then
        local MATCHES=()
        mapfile -t MATCHES < <(printf '%s\n' "${CANDIDATES[@]}" | grep "/$ROLE/" || true)
        if [ ${#MATCHES[@]} -eq 1 ]; then
            TARGET="${MATCHES[0]}"
        else
            echo -e "${YELLOW}Rolle '$ROLE' nicht eindeutig - bitte manuell waehlen.${NC}"
        fi
    fi

    if [ -z "$TARGET" ]; then
        echo "Verfuegbare Bootstraps:"
        local i=1
        local c
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
}

main "$@"
