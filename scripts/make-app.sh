#!/usr/bin/env bash
set -euo pipefail

CONFIG="${1:-debug}"
APP_NAME="Dopishi"
BUNDLE_DIR="dist/${APP_NAME}.app"

# Подпись. Стабильная идентичность (Apple Development) нужна, чтобы TCC
# (Accessibility / Input Monitoring) удерживал разрешения между пересборками -
# ad-hoc подпись их не удерживает. Если сертификат не найден, падаем в ad-hoc
# (тогда разрешения придётся выдавать заново после каждой пересборки).
if [ -z "${CODESIGN_ID:-}" ]; then
    CODESIGN_ID="$(security find-identity -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/{print $2; exit}')"
fi
CODESIGN_ID="${CODESIGN_ID:--}"

echo "==> swift build ($CONFIG)"
# Только продукт приложения - чтобы дев-таргет DopishiBench не утяжелял сборку .app.
swift build -c "$CONFIG" --product DopishiApp
BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)/DopishiApp"

echo "==> assembling $BUNDLE_DIR"
rm -rf "$BUNDLE_DIR"
mkdir -p "$BUNDLE_DIR/Contents/MacOS"
mkdir -p "$BUNDLE_DIR/Contents/Resources"
cp Info.plist "$BUNDLE_DIR/Contents/Info.plist"
if [ -f Resources/Dopishi.icns ]; then
    cp Resources/Dopishi.icns "$BUNDLE_DIR/Contents/Resources/Dopishi.icns"
fi
cp "$BIN_PATH" "$BUNDLE_DIR/Contents/MacOS/${APP_NAME}"

# Встроить динамические зависимости рядом с бинарём (rpath бинаря = @loader_path).
BIN_DIR="$(dirname "$BIN_PATH")"
if [ -d "$BIN_DIR/llama.framework" ]; then
    echo "==> embedding llama.framework"
    cp -R "$BIN_DIR/llama.framework" "$BUNDLE_DIR/Contents/MacOS/llama.framework"
fi

echo "==> codesign: ${CODESIGN_ID}"
# Вложенный фреймворк подписываем первым, затем весь бандл.
if [ -d "$BUNDLE_DIR/Contents/MacOS/llama.framework" ]; then
    codesign --force --sign "$CODESIGN_ID" "$BUNDLE_DIR/Contents/MacOS/llama.framework"
fi
codesign --force --sign "$CODESIGN_ID" "$BUNDLE_DIR"

echo "==> done: $BUNDLE_DIR"
codesign -dv --verbose=2 "$BUNDLE_DIR" 2>&1 | grep -E "Authority=|Signature=|TeamIdentifier=" || true
echo "Запуск:   open \"$BUNDLE_DIR\""
echo "Если права слетели (ad-hoc) или сменилась подпись:"
echo "  tccutil reset Accessibility dev.dopishi.Dopishi"
echo "  tccutil reset ListenEvent dev.dopishi.Dopishi"
