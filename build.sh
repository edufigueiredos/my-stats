#!/bin/zsh
# Compila e monta "build/My Stats.app" (sem ícone no Dock).
#   ./build.sh            → assinatura ad hoc, para uso local
#   ./build.sh instalar   → também copia para ~/Applications e abre
#   ASSINAR="Developer ID Application: …" ./build.sh   → assinatura de distribuição com Hardened Runtime (usado por scripts/publicar-release.sh)
set -euo pipefail
cd "$(dirname "$0")"
NOME=ConsumoBateria          # executável e alvo do SwiftPM (interno)
APP_NOME="My Stats"          # nome do app no Finder e no Mac
ASSINAR="${ASSINAR:--}"
swift build -c release
APP="build/$APP_NOME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp ".build/release/$NOME" "$APP/Contents/MacOS/$NOME"
cp Info.plist "$APP/Contents/Info.plist"
cp Recursos/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"   # gerado por scripts/gerar-icone.swift

# Sparkle (atualização automática, docs/atualizacao.md): o framework vai para Contents/Frameworks (o rpath vem do Package.swift).
# Os serviços XPC do Sparkle só servem a apps em sandbox; o My Stats não é, então saem.
FW="$APP/Contents/Frameworks/Sparkle.framework"
ditto ".build/release/Sparkle.framework" "$FW"
rm -rf "$FW/Versions/B/XPCServices" "$FW/XPCServices"
cp .build/checkouts/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt" 2>/dev/null \
  || cp .build/artifacts/sparkle/Sparkle/LICENSE "$APP/Contents/Resources/Sparkle-LICENSE.txt" 2>/dev/null || true

# Assina de dentro para fora (Autoupdate, Updater.app, framework, app). `codesign --deep` não serve para distribuição.
if [[ "$ASSINAR" == "-" ]]; then OPCOES=(); else OPCOES=(--options runtime --timestamp); fi
codesign --force "${OPCOES[@]}" --sign "$ASSINAR" "$FW/Versions/B/Autoupdate"
codesign --force "${OPCOES[@]}" --sign "$ASSINAR" "$FW/Versions/B/Updater.app"
codesign --force "${OPCOES[@]}" --sign "$ASSINAR" "$FW"
codesign --force "${OPCOES[@]}" --entitlements Recursos/MyStats.entitlements --sign "$ASSINAR" "$APP"   # acesso ao Calendário
codesign --verify --strict "$APP"
echo "Pronto: $APP"

if [[ "${1:-}" == "instalar" ]]; then
  pkill -x "$NOME" 2>/dev/null || true
  # Espera a cópia antiga fechar antes de abrir a nova.
  for _ in $(seq 50); do pgrep -x "$NOME" >/dev/null || break; sleep 0.1; done
  mkdir -p ~/Applications
  rm -rf ~/Applications/$NOME.app        # nome antigo (Consumo de Bateria)
  rm -rf ~/Applications/"$APP_NOME.app"
  ditto "$APP" ~/Applications/"$APP_NOME.app"
  open ~/Applications/"$APP_NOME.app"
  echo "Instalado em ~/Applications/$APP_NOME.app"
fi
