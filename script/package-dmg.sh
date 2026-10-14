#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -ne 2 ]]; then
    echo "Usage: $0 PATH/TileSail.app OUTPUT.dmg" >&2
    exit 1
fi
app="$1"
output="$2"
[[ "$output" = /* ]] || output="$PWD/$output"
[[ -d "$app" && "$output" = *.dmg ]] || { echo "Expected TileSail.app and a .dmg output." >&2; exit 1; }
[[ ! -e "$output" ]] || { echo "Output already exists: $output" >&2; exit 1; }
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist")" = TileSail ]]

stage="$(mktemp -d "${TMPDIR:-/tmp}/tilesail-dmg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$(dirname "$output")"
ditto "$app" "$stage/TileSail.app"
cmp "$app/Contents/MacOS/TileSail" "$stage/TileSail.app/Contents/MacOS/TileSail"
# This development installer uses an ad-hoc signature, without a notarization ticket.
codesign --force --deep --sign - "$stage/TileSail.app"
codesign --verify --deep --strict "$stage/TileSail.app"
(cd "$stage" && shasum -a 256 TileSail.app/Contents/MacOS/TileSail > BUILD-EXECUTABLE.sha256)
ln -s /Applications "$stage/Aplicativos"
cp LICENSE.txt NOTICE.md "$stage/"
ditto legal "$stage/legal"
git rev-parse HEAD > "$stage/BUILD-COMMIT.txt"
cat > "$stage/LEIA-ME.txt" <<'EOF'
TileSail — versão de desenvolvimento para macOS 13 ou posterior

Este instalador contém uma compilação Debug para Apple Silicon.
Não possui assinatura Developer ID nem notarização da Apple.
O macOS pode exigir autorização em Ajustes do Sistema > Privacidade e Segurança.

1. Encerre o TileSail/AeroSpace antes de substituir o aplicativo.
2. Arraste TileSail.app para Aplicativos (ou substitua sua instalação atual).
   Mantenha apenas um gerenciador de janelas ativo.
3. Abra TileSail e conceda permissão de Acessibilidade, se solicitada.

Configurações TOML e preferências AeroSpaceSmooth continuam compatíveis.
Se sua inicialização automática aponta para outra pasta, preserve esse caminho
ao atualizar ou ajuste o agente para o novo caminho do aplicativo.

Código e licenças: https://github.com/cassel/TileSail
EOF
hdiutil create -volname TileSail -srcfolder "$stage" -format UDZO "$output"
hdiutil verify "$output"
(cd "$(dirname "$output")" && shasum -a 256 "$(basename "$output")" > "$(basename "$output").sha256")
mkdir -p .local/installers
printf '%s\n' "$output" > .local/installers/latest-dmg-path.txt
echo "Created $output"
