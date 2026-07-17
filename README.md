# bootstrap

Seed-Bootstrap für frische Linux-Maschinen (Debian/Ubuntu). Erzeugt einen GitHub-Key,
installiert [chezmoi](https://www.chezmoi.io/) und zieht die privaten Dotfiles —
anschließend kann direkt das passende Rollen-Bootstrap gestartet werden.

```bash
curl -fsSL https://raw.githubusercontent.com/decebu/bootstrap/main/bootstrap.sh | bash
```

Rolle direkt starten (Verzeichnisname unter `provisioning/`):

```bash
curl -fsSL https://raw.githubusercontent.com/decebu/bootstrap/main/bootstrap.sh | bash -s -- server
```

Reproduzierbar/auditierbar: statt `main` einen Commit-SHA in die URL setzen — dann läuft
exakt der reviewte Stand:

```bash
curl -fsSL https://raw.githubusercontent.com/decebu/bootstrap/<commit-sha>/bootstrap.sh | bash
```

Hinweis: Dieses Repo ist bewusst öffentlich und enthält keine internen Informationen.
Der erzeugte Key ist wertlos, bis er manuell im GitHub-Account freigeschaltet wird.

## Trust-Anker (Supply-Chain)

Das Skript führt bewusst Code aus diesen externen Quellen aus — bei Anpassungen prüfen:

- `get.chezmoi.io` — chezmoi-Installer (als **User** nach `~/.local/bin`, nicht als root).
- `raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh` — Oh-My-Zsh (unattended).
- GitHub-Clones für zsh-Plugins und Powerlevel10k — auf feste Tags gepinnt (`--branch`, `--depth 1`).
- GitHub-Hostkeys werden aus dem Skript in `~/.ssh/known_hosts` gepinnt
  (`StrictHostKeyChecking=yes`), statt den Erstkontakt blind zu akzeptieren.
