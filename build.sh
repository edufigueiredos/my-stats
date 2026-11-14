#!/bin/zsh
# Compila e monta "build/My Stats.app" (sem ícone no Dock, assinatura ad hoc local).
# ./build.sh instalar  → também copia para ~/Applications e abre.
set -euo pipefail
cd "$(dirname "$0")"
NOME=ConsumoBateria          # executável e alvo do SwiftPM (interno)
APP_NOME="My Stats"          # nome do app no Finder e no Mac
swift build -c release
APP="build/$APP_NOME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp ".build/release/$NOME" "$APP/Contents/MacOS/$NOME"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Recursos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # gerado por scripts/gerar-icone.swift
codesign --force --sign - "$APP"
echo "Pronto: $APP"
if [[ "${1:-}" == "instalar" ]]; then
  pkill -x "$NOME" 2>/dev/null || true
  # Espera a cópia antiga fechar antes de abrir a nova.
  for _ in $(seq 50); do pgrep -x "$NOME" >/dev/null || break; sleep 0.1; done
  mkdir -p ~/Applications
  rm -rf ~/Applications/$NOME.app        # nome antigo (Consumo de Bateria)
  rm -rf ~/Applications/"$APP_NOME.app"
  cp -R "$APP" ~/Applications/
  open ~/Applications/"$APP_NOME.app"
  echo "Instalado em ~/Applications/$APP_NOME.app"
fi
