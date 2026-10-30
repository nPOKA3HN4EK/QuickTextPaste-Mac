#!/bin/bash
# Запускает тесты. Твой texts.json не меняется: тесты работают с его копией.
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p build/tests

swiftc -swift-version 5 Tests/processor/main.swift Sources/TextProcessor.swift Sources/Models.swift \
    -o build/tests/processor
swiftc -swift-version 5 Tests/autotext/main.swift Sources/Autotext.swift Sources/TextProcessor.swift Sources/Models.swift \
    -o build/tests/autotext

DATA="$HOME/Library/Application Support/QuickTextPasteMac/texts.json"
ARGS=()
if [ -f "$DATA" ]; then
    cp "$DATA" build/tests/texts-copy.json
    ARGS=(build/tests/texts-copy.json)
fi

echo "== Команды и меню =="; build/tests/processor
echo; echo "== Автотекст и данные =="; build/tests/autotext "${ARGS[@]}"
