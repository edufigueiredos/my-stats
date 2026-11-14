#!/bin/zsh
# Publica uma versão do My Stats no GitHub, já pronta para a atualização automática (docs/atualizacao.md).
#   1. Escreva as notas da versão em notas-da-versao.json ("0.3.0": ["frase curta", ...]).
#   2. ./scripts/publicar-release.sh 0.3.0
# Faz: sobe a versão no Info.plist, monta o app assinado com Developer ID, gera o DMG, notariza e carimba na Apple,
# assina DMG e appcast com a chave EdDSA do Chaveiro (conta "my-stats" do Sparkle), commita, cria a tag e a release.
set -euo pipefail
cd "$(dirname "$0")/.."
VERSAO="${1:?uso: scripts/publicar-release.sh <versão, ex. 0.3.0>}"
NOTARIZAR_COM="${NOTARY_PROFILE:-bridgeloop-notary}"   # um perfil do notarytool serve a todos os apps da mesma equipe Apple
SPARKLE_BIN=.build/artifacts/sparkle/Sparkle/bin
DEVID="$(security find-identity -v -p codesigning | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p' | head -1)"
[[ -n "$DEVID" ]] || { echo "ERRO: falta o certificado Developer ID Application no Chaveiro." >&2; exit 1; }
[[ -z "$(git status --porcelain -- Sources Package.swift build.sh Recursos)" ]] || { echo "ERRO: há mudanças de código sem commit." >&2; exit 1; }
git rev-parse "v$VERSAO" >/dev/null 2>&1 && { echo "ERRO: a tag v$VERSAO já existe." >&2; exit 1; }
python3 -c "import json,sys; sys.exit(0 if json.load(open('notas-da-versao.json')).get('$VERSAO') else 1)" \
  || { echo "ERRO: escreva as notas da versão $VERSAO em notas-da-versao.json." >&2; exit 1; }

# Versão: a de mostrar é a pedida; o build (o que o Sparkle compara) sobe sempre.
BUILD_ANTES="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' Info.plist)"
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSAO" Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $((BUILD_ANTES + 1))" Info.plist

ASSINAR="$DEVID" ./build.sh
APP="build/My Stats.app"

mkdir -p dist
DMG="dist/My-Stats-$VERSAO.dmg"
APPCAST="dist/appcast.xml"
rm -f "$DMG" "$APPCAST"
PALCO="$(mktemp -d)"
ditto "$APP" "$PALCO/My Stats.app"
ln -s /Applications "$PALCO/Applications"
hdiutil create -volname "My Stats" -srcfolder "$PALCO" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$PALCO"
codesign --force --timestamp --sign "$DEVID" "$DMG"

echo "Notarizando (a Apple costuma levar de 1 a 15 minutos)..."
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARIZAR_COM" --wait
xcrun stapler staple "$DMG"
xcrun stapler validate "$DMG"
spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG"

# Na primeira vez o macOS pergunta se o sign_update pode usar a chave: "Permitir Sempre".
SIG="$("$SPARKLE_BIN/sign_update" --account my-stats "$DMG")"
python3 scripts/fazer-appcast.py "$APP/Contents/Info.plist" "$DMG" "$APPCAST" "$SIG"
"$SPARKLE_BIN/sign_update" --account my-stats "$APPCAST"
"$SPARKLE_BIN/sign_update" --account my-stats --verify "$APPCAST"

NOTAS="$(python3 -c "import json; print('\n'.join('- ' + x for x in json.load(open('notas-da-versao.json'))['$VERSAO']))")"
git add Info.plist notas-da-versao.json
git commit -q -m "Versão $VERSAO"
git tag "v$VERSAO"
git push -q origin HEAD "v$VERSAO"
gh release create "v$VERSAO" "$DMG" "$APPCAST" --title "My Stats $VERSAO" \
  --notes "$NOTAS"$'\n\n'"Baixe o \`My-Stats-$VERSAO.dmg\`, abra e arraste o My Stats para Aplicativos. Quem já tem o app recebe esta versão sozinho em até um dia (ou no clique direito na bateria > Procurar atualizações…)."
echo "Publicada: https://github.com/edufigueiredos/my-stats/releases/tag/v$VERSAO"
