# Consumo de Bateria (nome provisório)

App de barra de menus do macOS que mostra quanto da bateria o Mac gasta por hora, por exemplo `−11,3 %/h`, ou `+38,0 %/h` carregando. Não aparece no Dock. Interface em pt-BR, fiel ao desenho aprovado em `docs/desenho/*.dc.html`.

## O que o app mostra
- **Item da barra de menus**: 6 formatos (Empilhado = padrão, Ícone, Valor, Ícone + valor, Duas linhas, Velocímetro) e 5 estados (cheia, carregando, descarregando, na tomada parado, consumo alto). Acima do limite configurado (padrão 20 %/h) o item fica laranja. Clique direito troca o formato, abre Mais informações, Preferências ou sai. O item é um `NSStatusItem` com a composição renderizada em imagem (template quando não há cor).
- **Editor por estado** (Preferências): cada estado tem a sua lista ordenada de peças, escolhidas entre 16 (Ritmo %/h, Ritmo e watts, Ritmo sobre a bateria, Tempo sobre a bateria, Porcentagem, Tempo, Watts, Etiqueta e valor, Ícone, Bateria, Barra vertical, Anel, Velocímetro, Número na pílula, Espaçador, Separador). O botão + abre a paleta, clicar numa peça a tira, arrastar reordena, e cada estado tem a sua cor. A chave "Duas linhas" de cada estado separa a lista em "Linha de cima" e "Linha de baixo", cada uma com o seu + e a sua ordem (arrastar só vale dentro da mesma linha); nas duas linhas o texto usa 10 pt (cima) e 9 pt (baixo) e os desenhos encolhem para ~11 pt; desligar junta tudo numa linha só. Configs salvas antes continuam valendo. Os formatos prontos são predefinições dessas listas.
- **Painel** (clique no item): estado, ritmo médio, agora e última hora, anel com % e tempo, blocos Saindo/Entrando em W, Acaba em/Cheia em (com horário) e Bateria ou Até 80%, gráfico de ritmo (15 min, 1 h, 6 h, 24 h), Quem mais gasta (estimado), e carregando: Para onde vai o que entra (bateria x Mac) e aviso de carga otimizada. Linhas de corrente, tensão, temperatura, saúde (ciclos) e modo de energia.
- **Mais informações**: Visão geral, Histórico, Apps, Saúde da bateria e Alertas; períodos Hoje, 7 dias e 30 dias; gráfico da carga com faixa "na tomada" e previsão tracejada; tabela de trechos; quem mais gastou (Wh); saúde; Exportar CSV.
- **Preferências**: média do ritmo (Agora, 5 min, **15 min = padrão**, 1 h), casas decimais (0 ou 1), sentido (− e +, setas, só cor), tema, colorir a barra, limite de consumo alto, avisos, abrir ao iniciar e quantos dias guardar o histórico.
- **Temas**: os 6 do Budsmith (Gold padrão, Black, White, Neon com cor escolhida, Liquid Glass que segue o sistema, Classic). A abordagem foi copiada de `Budsmith/Sources/FreeBudsUI/Theme.swift`, sem importar o pacote.
- **Avisos** (UserNotifications, só no .app): consumo acima de X %/h por 2 min, bateria abaixo de X%, carregou até X%, carregador abaixo de X W. Cada um dispara uma vez por cruzamento.

## De onde vem cada número
- Lê o serviço `AppleSmartBattery` do IOKit a cada 5 s (timer com folga) e quando o sistema avisa de mudança na energia (`IOPSNotificationCreateRunLoopSource`).
- **%/h instantâneo** = `InstantAmperage` (mA) ÷ `AppleRawMaxCapacity` (mAh, capacidade cheia real) × 100. `MaxCapacity` não serve (vem em %). As chaves "Raw" ficam em `BatteryData`; a corrente vem como UInt64 e o sinal sai do padrão de bits (`int64Value`).
- **%/h na barra** = média ponderada pelo tempo na janela escolhida (padrão 15 min). Ela recomeça ao ligar ou desligar a tomada, para não misturar carga com descarga.
- Temperatura: `Temperature` (centésimos de °C). Ciclos: `CycleCount`. Capacidade de fábrica: `DesignCapacity`.
- Entrada do sistema em W: `PowerTelemetryData/SystemPowerIn`. O que vai para a bateria é V × I; o resto da entrada é do Mac.
- Carregador (potência e nome): `IOPSCopyExternalPowerAdapterDetails`.
- Modo Pouca Energia: `ProcessInfo.isLowPowerModeEnabled`.
- Carga otimizada é uma heurística: na tomada, sem carregar e sem estar cheia, ou `NotChargingReason` diferente de 0.
- Chave ausente neste Mac vira "–"; nada é inventado.

## Consumo por app (estimado)
O macOS não dá energia por app sem privilégio de administrador. O app lê `proc_pid_rusage` (`ri_energy_nj`, ou tempo de CPU se a energia vier zerada) de cada processo a cada 30 s e reparte os watts do sistema (a potência da bateria ou a entrada do carregador) em proporção ao que cada processo usou no intervalo. Processos auxiliares (Helpers) somam no app dono subindo pela árvore de pais. Auxiliares filhos do launchd (serviços XPC, WebContent do Safari) não têm app como pai e caem em "Sistema e outros". Na tomada, só a parte que fica com o Mac é repartida (a entrada do sistema menos o que vai para a bateria). Por isso o painel diz "estimado".
Fica de fora: processos de root e de outros usuários (leitura negada sem privilégio); tela, GPU e rádio não são atribuídos por processo e ficam diluídos entre os apps ou em "Sistema e outros".

## Histórico
- Pasta `~/Library/Application Support/ConsumoBateria/historico/`: 1 ponto por minuto (% , ritmo, W, tomada), um arquivo comprimido por dia, mais o Wh acumulado por app.
- Guarda N dias (padrão 90; troque nas Preferências); o que passa do corte é apagado.
- Exportar CSV em Mais informações.
- O antigo `amostras.json` não é mais gravado: se existir ao iniciar, é lido uma vez para a média continuar e apagado. As amostras de 5 s ficam só em memória (até 1 h).

## Compilar e instalar
```bash
./build.sh            # gera build/ConsumoBateria.app (assinatura ad hoc)
./build.sh instalar   # também copia para ~/Applications e abre
```
"Abrir ao iniciar o Mac" usa `SMAppService.mainApp`. Funciona melhor com o app em `~/Applications`.

## Conferir o visual (`--foto`)
`build/ConsumoBateria.app/Contents/MacOS/ConsumoBateria --foto /caminho/da/pasta` grava PNGs com dados simulados (não toca na bateria nem grava nada do app):
- `barra-<formato>-<estado>.png`: 6 formatos × 5 estados (30 arquivos), e `barra-todos.png` com a grade;
- `painel-descarregando.png` e `painel-carregando.png` (tema Gold);
- `detalhes.png` e `preferencias.png` (tema Gold);
- `tema-gold|black|white|neon|vidro|classico.png`: o painel em cada tema (o Liquid Glass usa um fundo chapado que imita o vidro).
