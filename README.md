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
