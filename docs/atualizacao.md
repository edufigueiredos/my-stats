# Atualização automática e releases

## Como o app se atualiza
- Biblioteca: [Sparkle](https://sparkle-project.org) 2.10.0 (licença MIT), pelo Swift Package Manager.
- Onde procura: `SUFeedURL` no `Info.plist` aponta para `releases/latest/download/appcast.xml`, o appcast da última release do GitHub. Ele traz só a versão mais nova e o link do `.zip` do app daquela release (o DMG é só para quem baixa pelo site: no macOS 27, o Sparkle montar um DMG fazia o sistema mostrar "Instalar este app?" e depois "Não foi possível instalar").
- Quando: uma vez por dia (`SUScheduledCheckInterval` 86400) e no clique direito na bateria > "Procurar atualizações…".
- Segurança: o app exige o appcast assinado (`SURequireSignedFeed`) e confere a assinatura EdDSA do `.zip` antes de abri-lo (`SUVerifyUpdateBeforeExtraction`). A chave pública está no `Info.plist` (`SUPublicEDKey`); a privada fica só no Chaveiro de quem publica, conta `my-stats` do Sparkle.
- O My Stats vive na barra de menus: se a versão nova chega com o app em segundo plano, sai uma notificação e o menu do clique direito mostra "Atualizar para a versão X…"; a janela do Sparkle abre no clique (`Sources/ConsumoBateria/Atualizador.swift`).
- O binário solto do `swift build` não tem `Info.plist`, então não procura nada. Para testar com um appcast local: `MYSTATS_APPCAST=<url>` no ambiente.

## Publicar uma versão
1. Escreva as notas em `notas-da-versao.json` (frases curtas, em português).
2. `./scripts/publicar-release.sh 0.3.0`: sobe a versão no `Info.plist`, monta o app com Developer ID e Hardened Runtime, gera o DMG, notariza e carimba na Apple (DMG e app), zipa o app, assina o `.zip` e o appcast com a chave EdDSA, commita, cria a tag e a release com o DMG, o `.zip` e o `appcast.xml`. Na primeira vez o macOS pergunta se o `sign_update` pode usar a chave: "Permitir Sempre".
3. Quem tem o app recebe a versão em até um dia.

Variável opcional: `NOTARY_PROFILE` (perfil do `notarytool`; padrão `bridgeloop-notary`, que serve à mesma equipe Apple).

## Chave privada: guarde uma cópia
Sem ela, nenhum app instalado aceita atualização nova, e todo mundo teria que baixar de novo. Exporte uma vez e guarde fora do Mac:

    .build/artifacts/sparkle/Sparkle/bin/generate_keys --account my-stats -x <arquivo>

Depois de guardar, apague o arquivo exportado. Para usar em outro Mac: `generate_keys --account my-stats -f <arquivo>`.
