#!/usr/bin/env bash
# Crea un acceso directo de RetroHub en el menú de aplicaciones (KDE / SteamOS).
# Uso: ./install-desktop-entry.sh   (desde la carpeta donde descomprimiste RetroHub)
set -e
DIR="$(cd "$(dirname "$0")" && pwd)"
chmod +x "$DIR/RetroHub"
mkdir -p "$HOME/.local/share/applications"
cat > "$HOME/.local/share/applications/retrohub.desktop" <<DESKTOP
[Desktop Entry]
Type=Application
Name=RetroHub
Comment=Gestor de ROMs retro con servidor local y sincronización de partidas
Exec="$DIR/RetroHub"
Icon=$DIR/retrohub.png
Terminal=false
Categories=Game;Utility;
DESKTOP
update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
echo "Listo: RetroHub aparece en el menú de aplicaciones."
echo "Para usarlo en Modo Juego: en Steam, 'Añadir un juego que no es de Steam' y elige RetroHub."
