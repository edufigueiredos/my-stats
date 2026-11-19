#!/usr/bin/env python3
"""Gera o appcast do Sparkle para o pacote que o publicar-release.sh acabou de montar (docs/atualizacao.md).

Uso: fazer-appcast.py <Info.plist do app> <pacote .zip ou .dmg> <saída.xml> <atributos do sign_update>
  <atributos do sign_update>: a linha que o `sign_update` imprime para o pacote (sparkle:edSignature="..." length="...").

A atualização usa o .zip do app, não o DMG: no macOS 27, o Sparkle montar o DMG fazia o sistema oferecer
"Instalar este app?" e, como o Sparkle já tinha ejetado a imagem, dizer "Não foi possível instalar".

O appcast traz só a versão atual: o Sparkle compara com a instalada e só precisa da mais nova. Ele vai como arquivo da
release no GitHub, e o app lê sempre o da última (releases/latest/download/appcast.xml). As notas vêm de
notas-da-versao.json; sem notas para a versão = erro. Depois, o script assina o próprio XML (o app exige appcast assinado).
"""
import html
import json
import os
import plistlib
import re
import sys
from email.utils import formatdate

REPO = "https://github.com/edufigueiredos/my-stats"
RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def notas_html(itens):
    return "<ul>%s</ul>" % "".join("<li>%s</li>" % html.escape(x) for x in itens)


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    plist, pacote, saida, assinatura = sys.argv[1:]
    info = plistlib.load(open(plist, "rb"))
    versao, build = info["CFBundleShortVersionString"], info["CFBundleVersion"]
    min_os = info.get("LSMinimumSystemVersion", "14.0")
    m = re.fullmatch(r'\s*sparkle:edSignature="([A-Za-z0-9+/=]+)"\s+length="(\d+)"\s*', assinatura)
    if not m:
        sys.exit("ERRO: atributos do sign_update inesperados: %r" % assinatura)
    sig, tamanho = m.groups()
    if int(tamanho) != os.path.getsize(pacote):
        sys.exit("ERRO: o tamanho assinado (%s) não é o do pacote (%d)" % (tamanho, os.path.getsize(pacote)))
    tipo = "application/x-apple-diskimage" if pacote.endswith(".dmg") else "application/zip"
    notas = json.load(open(os.path.join(RAIZ, "notas-da-versao.json"), encoding="utf-8")).get(versao)
    if not notas:
        sys.exit("ERRO: faltam as notas da versão %s em notas-da-versao.json" % versao)
    url = "%s/releases/download/v%s/%s" % (REPO, versao, os.path.basename(pacote))
    xml = """<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>My Stats</title>
    <link>%(repo)s</link>
    <language>pt-BR</language>
    <item>
      <title>My Stats %(versao)s</title>
      <pubDate>%(data)s</pubDate>
      <sparkle:version>%(build)s</sparkle:version>
      <sparkle:shortVersionString>%(versao)s</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>%(min_os)s</sparkle:minimumSystemVersion>
      <description><![CDATA[%(notas)s]]></description>
      <enclosure url="%(url)s" type="%(tipo)s" sparkle:edSignature="%(sig)s" length="%(tamanho)s"/>
    </item>
  </channel>
</rss>
""" % {"repo": REPO, "versao": html.escape(versao), "data": formatdate(usegmt=True), "build": html.escape(build),
       "min_os": html.escape(min_os), "notas": notas_html(notas), "url": url, "tipo": tipo, "sig": sig, "tamanho": tamanho}
    open(saida, "w", encoding="utf-8").write(xml)
    print("appcast: %s (versão %s, build %s, %s bytes)" % (saida, versao, build, tamanho))


if __name__ == "__main__":
    main()
