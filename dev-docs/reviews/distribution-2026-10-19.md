# TileSail: preparação de distribuição

Data: 19 de outubro de 2026. Versão preparada: `0.22.0-beta.1`.

## Implementado

- Menu **About TileSail…**, disponível mesmo antes da permissão de Acessibilidade.
- Painel nativo com Cleverson Cassel (C. Cassel), fundador e CEO da CambioReal, descrição do projeto, versão, identificação do build, links de suporte e créditos AeroSpace/MIT.
- Copyright nos metadados dos bundles Debug e Release, preservando os respectivos IDs.
- `script/build-dmg.sh`: compila Release universal, identifica versão/commit, restaura os arquivos gerados após o build e distingue previews com alterações não commitadas.
- `script/package-dmg.sh`: assinatura ad-hoc quando não há assinatura válida, atalho Applications, instruções, licenças, metadados e checksums. Há alternativa HFS+ → UDZO com ferramentas nativas quando o serviço de discos não permite criar o volume diretamente.
- `script/publish-release.sh`: publica DMG, checksum e metadados a partir de uma tag existente; exige Release universal do commit atual e recusa previews não commitadas. Sem `--publish`, cria rascunho.
- Workflow `.github/workflows/release.yml`: testes, build e publicação ao receber tag `v*`; versões com sufixo são prereleases.
- Notas de release em `dev-docs/releases/0.22.0-beta.1.md` e README atualizado.

## Validação realizada

- Xcode Release: **BUILD SUCCEEDED**, arquiteturas `x86_64 arm64`, bundle `us.cassel.tilesail`, nome e executável TileSail.
- O executável de ambas as arquiteturas contém a versão `0.22.0-beta.1` e os novos créditos.
- 521 testes Swift permitidos passaram. A execução completa incluiu 529 testes; oito casos de sockets foram bloqueados pelo sandbox, gerando dez assertions de falha com `Operation not permitted`.
- 22 testes Python de migração/empacotamento passaram.
- SwiftFormat, SwiftLint, `bash -n` dos três scripts e `git diff --check` sem problemas.
- DMG UDZO criado e checksum interno validado por `hdiutil verify`.
- Assinatura interna verificada por `codesign --verify --deep --strict` durante o empacotamento.
- A proteção de publicação recusou corretamente o pacote com `working_tree_dirty: true` antes de chamar o GitHub.
- Nenhuma instalação ou execução interativa do novo app foi feita. A montagem do DMG e a notarização não foram validadas. Não há identidade Developer ID disponível nesta sessão.

## Artefatos locais

- `.local/installers/TileSail-0.22.0-beta.1-universal.dmg`
- `.local/installers/TileSail-0.22.0-beta.1-universal.dmg.sha256`
- `.local/installers/TileSail-0.22.0-beta.1-universal.dmg.build-info.json`

Este é um preview local de Release: o código ainda não foi commitado. O About inclui o sufixo `-dirty` no identificador do build e os metadados do DMG declaram essa condição. Antes da publicação, é necessário fazer commit e reconstruir a partir desse commit.

## Bloqueios externos

1. `git add` falhou ao criar `.git/index.lock`: **Operation not permitted**. O diretório `.git` está somente leitura para esta sessão; nenhum commit foi criado.
2. `git ls-remote origin HEAD` falhou ao resolver `github.com`; `gh api` também não conseguiu conectar. Nenhum push, tag remota ou release foi publicado. O workflow novo ainda não executou no GitHub.

O histórico e os notices upstream não foram alterados. Os arquivos locais do BMAD/ECC e a cópia `AeroSpaceSmooth/` não devem ser incluídos no commit.

Após liberar escrita em `.git` e conectividade, concluir o commit como `C. Cassel <c@cassel.us>`, enviar o código a `cassel/TileSail` e criar/enviar a tag `v0.22.0-beta.1`. O workflow deve então gerar um novo pacote limpo, em vez de publicar o preview local.
