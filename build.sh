#!/bin/zsh
# Compila e monta build/ConsumoBateria.app (sem ícone no Dock, assinatura ad hoc local).
# ./build.sh instalar  → também copia para ~/Applications e abre.
set -euo pipefail
cd "$(dirname "$0")"
NOME=ConsumoBateria
swift build -c release
APP=build/$NOME.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/$NOME" "$APP/Contents/MacOS/$NOME"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - "$APP"
echo "Pronto: $APP"
if [[ "${1:-}" == "instalar" ]]; then
  pkill -x "$NOME" 2>/dev/null || true
  mkdir -p ~/Applications
  rm -rf ~/Applications/$NOME.app
  cp -R "$APP" ~/Applications/
  open ~/Applications/$NOME.app
  echo "Instalado em ~/Applications/$NOME.app"
fi
