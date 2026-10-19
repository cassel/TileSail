# TileSail: revisão de animações e desempenho

Data: 19 de outubro de 2026.

## Escopo e método

Inventário dos 151 arquivos Swift de produção em `Sources/AppBundle`, com foco em layouts, maximização, minimização, Acessibilidade, eventos, tarefas de fundo e encerramento. Aplicados o fluxo de verificação do ECC e as lentes BMAD adversarial, edge-case-hunter e verification-gap. Revisores independentes avaliaram os riscos; uma segunda revisão do diff final não encontrou novos problemas. A cópia local `AeroSpaceSmooth/` e as instalações dos frameworks não foram alteradas.

Esta foi uma revisão de código com testes automatizados e compilação. Não houve medição de CPU, energia ou latência com Instruments, nem ensaio interativo com todos os aplicativos e monitores. Não há promessa de eliminar toda possível lentidão.

## Alterações implementadas

| Área | Problema encontrado | Resultado |
| --- | --- | --- |
| Layouts e maximização do TileSail | Interpolação de posições e tamanhos a cada 16 ms | Motor de animação removido; aplicação direta do quadro final |
| Configuração | Configurações antigas podiam reativar animações | Chaves TOML ainda aceitas; duração padrão 0; nenhum caminho de execução anima, mesmo com duração antiga positiva |
| Interface | Controles permitiam configurar animações removidas | Substituídos por explicação do comportamento imediato |
| Acessibilidade | Escritas repetiam quadros que já estavam corretos | Quadros iguais não geram novas escritas; alterações reais preservam a sequência tamanho–posição–tamanho necessária ao macOS |
| Correção de layout | Deduplicação de destinos impedia corrigir deslocamentos externos | Mesmo destino pode voltar a corrigir a posição real |
| Recusa de tamanho | Cache podia reter IDs de janelas antigas | Entradas fora da transação atual são removidas; verificação assíncrona mantém proteção contra ciclos de redimensionamento |
| Concorrência | Resultado de verificação antigo podia chegar depois da troca de layout | Cancelamento e geração conferidos também depois da leitura AX |
| Scratchpads e estado nativo | Escrita de quadro podia cancelar restauração nativa | Tarefas de visibilidade/tela cheia separadas das tarefas de posicionamento |
| Minimização e tela cheia nativas | Caminhos explícitos não usavam supressão disponível | Mesma supressão via Acessibilidade aplicada; respeitado modo somente leitura |
| Aplicativos sem resposta | Chamadas AX sem limite explícito | Timeout de mensagens AX definido em 1 segundo |
| Encerramento | Janela ausente podia deixar semáforo/futuro sem conclusão | Conclusão mesmo sem janela e esperas limitadas; retorno de fallback quando necessário |
| Dock | Varredura AX ocorria mesmo com ocultação automática | Consulta AX dispensada quando Dock está em ocultação automática |
| Barra de workspaces | Recriação de hierarquia SwiftUI e atualização de painel em todo refresh | Snapshot comparado, controlador reutilizado, quadro atualizado somente quando muda; animação de painel desativada |
| Foco pelo mouse | Sessão de foco repetida sobre a janela já focada | Sessão redundante ignorada |

## Comportamentos preservados e limites

- Efeitos nativos de minimizar e criar/remover Spaces de tela cheia são controlados pelo macOS. A supressão AX é aplicada onde disponível, mas não garante a eliminação desses efeitos.
- A ocultação nativa de workspaces foi preservada. Substituí-la indiscriminadamente por janelas fora da tela pode causar clamping, vazamento para outro monitor e ciclos de reposicionamento; esse risco foi identificado pela revisão BMAD.
- Verificações de aceitação de tamanho continuam assíncronas em duas amostras de 34 ms; não atrasam a aplicação inicial do quadro e não são recriadas para transações idênticas.
- A observação periódica do Dock e a descoberta de itens de menu continuam necessárias para manter áreas de trabalho corretas. A varredura de todos os aplicativos pela barra e os refreshes de descoberta após cliques continuam candidatos a profiling; não foram removidos sem uma substituição funcional validada.
- Identidade Debug `bobko.aerospace.debug`, identidade Release `us.cassel.tilesail`, nomes TileSail, preferências `AeroSpaceSmooth.*`, configuração TOML e avisos MIT foram preservados.
- A versão instalada e o agente de inicialização não foram modificados. Nenhum aplicativo foi iniciado e nenhuma alteração foi publicada.

## Validação

| Verificação | Resultado |
| --- | --- |
| `swift test` completo | Executado: 526 testes antes dos três testes adicionais do futuro; oito casos de sockets falharam com dez assertions por `Operation not permitted` do sandbox |
| Suíte com os dois grupos de sockets excluídos | 521 testes passaram, zero falhas, após todas as alterações |
| Novos testes | Quadro final imediato mesmo com duração legada 1000 ms; correção de deslocamento externo; recusa de tamanho pelo caminho assíncrono; descarte de IDs antigos; padrão sem animação; conclusão de futuro com valor/nil/timeout |
| Xcode Debug | `BUILD SUCCEEDED`, binário universal `x86_64 arm64` |
| Identidade do bundle compilado | Nome e executável `TileSail`; ID `bobko.aerospace.debug` |
| SwiftFormat e SwiftLint | Arquivos alterados e novo teste verificados sem problemas |
| `git diff --check` | Sem problemas |
| Revisão BMAD final | Nenhum novo achado no diff corrigido |
| Launch Services | Tentativa de desregistrar o produto derivado retornou `-10814` (falha de scan/Spotlight); desregistro não confirmado neste ambiente |

O build precisou de caches temporários graváveis e da desativação dos sandboxes internos do compilador/manifesto, pois o sandbox externo já restringe o processo. Assinatura de distribuição, notarização e execução interativa não foram validadas.

Comando de testes reproduzível neste ambiente:

```sh
CLANG_MODULE_CACHE_PATH=/tmp/tilesail-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/tilesail-swift-cache \
swift test --disable-sandbox \
  --cache-path /tmp/tilesail-spm-cache \
  --config-path /tmp/tilesail-spm-config \
  --security-path /tmp/tilesail-spm-security \
  --skip 'SocketEndpointTest|SocketFramingTest'
```

Comando do build validado:

```sh
CFFIXED_USER_HOME=/tmp/tilesail-xcode-home \
CLANG_MODULE_CACHE_PATH=/tmp/tilesail-clang-cache \
SWIFTPM_MODULECACHE_OVERRIDE=/tmp/tilesail-swift-cache \
xcodebuild -IDEPackageSupportDisableManifestSandbox=YES \
  -project xcode/AeroSpace.xcodeproj -scheme AeroSpace \
  -configuration Debug -destination 'generic/platform=macOS' \
  -derivedDataPath xcode/.xcode-build \
  -clonedSourcePackagesDirPath "$PWD/.build" \
  -packageCachePath /tmp/tilesail-spm-cache \
  -disableAutomaticPackageResolution -skipPackageUpdates \
  CODE_SIGNING_ALLOWED=NO 'OTHER_SWIFT_FLAGS=$(inherited) -disable-sandbox' build
```
