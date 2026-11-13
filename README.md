# Consumo de Bateria (nome provisório)

App de barra de menus do macOS que mostra quanto da bateria o Mac gasta por hora, por exemplo `−8,3 %/h`, ou `+x %/h` quando está carregando. Não aparece no Dock.

## Como mede
- Lê o serviço `AppleSmartBattery` do IOKit a cada 5 s (timer com folga) e também quando o sistema avisa que algo mudou na energia (`IOPSNotificationCreateRunLoopSource`).
- **%/h instantâneo** = `InstantAmperage` (mA) ÷ `AppleRawMaxCapacity` (mAh, a capacidade cheia real) × 100.
  - `MaxCapacity` não serve: no Apple Silicon ela vem em % (100).
  - Neste Mac as chaves "Raw" ficam dentro de `BatteryData`.
  - A corrente vem como UInt64; o valor com sinal sai do padrão de bits (`int64Value`).
- **%/h na barra** = média ponderada pelo tempo dos últimos 10 min. A janela recomeça quando a tomada é ligada ou desligada, para não misturar carga com descarga.
- O menu mostra a média, o valor instantâneo, o %, o tempo restante (estimativa própria pela média e a do sistema), a potência (V × A), a corrente, a tensão, a carga em mAh e o gráfico da última hora.
- O histórico da última hora fica em `~/Library/Application Support/ConsumoBateria/amostras.json`, gravado uma vez por minuto e ao sair.

## Compilar e instalar
```bash
./build.sh            # gera build/ConsumoBateria.app (assinatura ad hoc)
./build.sh instalar   # também copia para ~/Applications e abre
```
"Abrir ao iniciar o Mac" usa `SMAppService.mainApp`. Funciona melhor com o app em `~/Applications`.

Para conferir o visual sem abrir o menu: `build/ConsumoBateria.app/Contents/MacOS/ConsumoBateria --foto /caminho/painel.png` (usa o histórico salvo).
