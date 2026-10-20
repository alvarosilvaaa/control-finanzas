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
  -derivedDataPath build.noindex build -quiet

echo "→ Cerrando la app si está abierta…"
osascript -e "tell application id \"$BUNDLE_ID\" to quit" 2>/dev/null || true
sleep 1

echo "→ Instalando en $DESTINO…"
rm -rf "$DESTINO"
ditto "build.noindex/Build/Products/Release/ControlFinanzas.app" "$DESTINO"

# Hay otras copias con el mismo identificador (compilaciones de Xcode, simulador del iPhone).
# Si macOS las tiene registradas, el Dock puede coger el icono de una de ellas: se quitan del registro.
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
"$LSREGISTER" -dump 2>/dev/null |
  awk -v id="$BUNDLE_ID" '/^path:/ { sub(/^path: */, ""); sub(/ \(0x[0-9a-f]+\)$/, ""); ruta = $0 }
                          /^identifier:/ && $2 == id { print ruta }' | sort -u |
  while read -r copia; do
    [[ "$copia" != "$DESTINO" ]] && "$LSREGISTER" -u "$copia" 2>/dev/null || true
  done
"$LSREGISTER" -f "$DESTINO"

open "$DESTINO"
echo "✓ Finanzas actualizada"
