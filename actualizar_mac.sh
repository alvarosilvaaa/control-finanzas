#!/bin/zsh
# Compila la app de Mac y la instala (o actualiza) en /Applications/Finanzas.app.
# La URL, el token y los datos se conservan: viven fuera de la app.
set -euo pipefail

cd "$(dirname "$0")"
DESTINO="/Applications/Finanzas.app"
BUNDLE_ID="com.alvarosilva.ControlFinanzas"

echo "→ Compilando…"
xcodebuild -project ControlFinanzas.xcodeproj -scheme ControlFinanzas \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath build build -quiet

echo "→ Cerrando la app si está abierta…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 1

echo "→ Instalando en $DESTINO…"
rm -rf "$DESTINO"
ditto "build/Build/Products/Release/ControlFinanzas.app" "$DESTINO"

open "$DESTINO"
echo "✓ Finanzas actualizada"
