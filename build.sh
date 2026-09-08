#!/bin/bash
# Сборка Timato без Xcode: только Command Line Tools.
#   ./build.sh            собрать Timato.app и dist/Timato-<версия>.dmg
#   ./build.sh --app      только Timato.app, без упаковки
set -euo pipefail
cd "$(dirname "$0")"

APP_NAME="Timato"
EXEC_NAME="Timato"
BUNDLE_ID="com.dkovalev.timato"
# Версия — в файле VERSION, одной строкой. Её читает и сборка, и релиз: держать
# номер в двух местах — однажды выпустить образ, который называет себя не тем,
# что он есть, и получить отзыв, к которому не привязать коммит.
VERSION=$(tr -d ' \n' < VERSION)
# Номер сборки — сколько коммитов было на момент сборки, и короткий хеш того
# коммита. По ним из любого бандла достаётся исходник, из которого он собран.
# Прогон тестов собирает копию из одних отслеживаемых файлов, без .git: там git
# молчать обязан, поэтому оба значения имеют запасной ответ, а не роняют сборку.
# Плюс к хешу — знак, что в дереве были незакоммиченные правки: такой бандл
# ни одному коммиту не соответствует, и по отзыву с ним искать нечего.
if git rev-parse --git-dir >/dev/null 2>&1; then
    BUILD=$(git rev-list --count HEAD)
    COMMIT=$(git rev-parse --short HEAD)
    git diff --quiet HEAD || COMMIT="$COMMIT+"
else
    BUILD=0
    COMMIT="unknown"
fi
# Порог системы. Ниже 13.0 не опускается, и это не осторожность, а упор в
# инструменты: до 13.0 Swift подцепляет шимы совместимости
# (libswiftCompatibility56.a и libswiftCompatibilityPacks.a), а в Command Line
# Tools они лежат только под arm64 — x86_64-срез с таким порогом не линкуется.
MIN_MACOS="13.0"
BUILD_DIR="build"
DIST_DIR="dist"
APP="$BUILD_DIR/$APP_NAME.app"

# Собираем в отдельный каталог и публикуем только целый бандл. Иначе упавшая
# компиляция оставляла огрызок .app, который выглядел как готовая сборка.
STAGE="$BUILD_DIR/stage"
APP_STAGE="$STAGE/$APP_NAME.app"
rm -rf "$STAGE"
mkdir -p "$APP_STAGE/Contents/MacOS" "$APP_STAGE/Contents/Resources" "$DIST_DIR"

# Два среза и склейка. Раньше собирался один arm64: образ жил на своей машине,
# и второй срез был лишним весом. Теперь образ уезжает на чужие машины, среди
# которых есть Intel, — а на Intel arm64-бандл не запускается вовсе.
echo "→ компилирую arm64 и x86_64"
SLICES=()
for ARCH in arm64 x86_64; do
    SLICE="$STAGE/$EXEC_NAME-$ARCH"
    swiftc -O -parse-as-library \
        -target "$ARCH-apple-macos$MIN_MACOS" \
        Sources/*.swift \
        -o "$SLICE"
    SLICES+=("$SLICE")
done
lipo -create "${SLICES[@]}" -output "$APP_STAGE/Contents/MacOS/$EXEC_NAME"
rm -f "${SLICES[@]}"

echo "→ рисую иконку-помидор"
swiftc -O -parse-as-library Icon/MakeIcon.swift Sources/TomatoIcon.swift -o "$BUILD_DIR/make-icon"
rm -rf "$BUILD_DIR/AppIcon.iconset"
"$BUILD_DIR/make-icon" "$BUILD_DIR/AppIcon.iconset" Resources/Tomato.png
iconutil -c icns "$BUILD_DIR/AppIcon.iconset" -o "$APP_STAGE/Contents/Resources/AppIcon.icns"
cp Resources/Tomato.png "$APP_STAGE/Contents/Resources/"
cp Resources/NothingFont5x7.otf "$APP_STAGE/Contents/Resources/"

echo "→ собираю бандл"
cat > "$APP_STAGE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>              <string>$APP_NAME</string>
    <key>CFBundleDisplayName</key>       <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>        <string>$EXEC_NAME</string>
    <key>CFBundleIdentifier</key>        <string>$BUNDLE_ID</string>
    <key>CFBundlePackageType</key>       <string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key>           <string>$BUILD</string>
    <!-- Коммит сборки: приложение подставляет его в форму отзыва. -->
    <key>TimatoCommit</key>              <string>$COMMIT</string>
    <key>LSMinimumSystemVersion</key>    <string>$MIN_MACOS</string>
    <key>NSHighResolutionCapable</key>   <true/>
    <key>LSApplicationCategoryType</key> <string>public.app-category.productivity</string>
    <key>CFBundleIconFile</key>          <string>AppIcon</string>
    <!-- Приложение живёт в строке меню: иконки в доке и переключателе задач нет. -->
    <key>LSUIElement</key>               <true/>
</dict>
</plist>
PLIST
printf 'APPL????' > "$APP_STAGE/Contents/PkgInfo"

echo "→ ad-hoc подпись (без неё система не выдаёт bundle identity и уведомления молчат)"
codesign --force --sign - "$APP_STAGE"

echo "→ проверяю бандл до публикации"
test -x "$APP_STAGE/Contents/MacOS/$EXEC_NAME"
# Оба среза обязательны. Бандл с одним arm64 у автора выглядит совершенно рабочим
# и молча не запускается на Intel-машине — а образ теперь уезжает и туда.
ARCHS=$(lipo -archs "$APP_STAGE/Contents/MacOS/$EXEC_NAME")
for NEED in arm64 x86_64; do
    case " $ARCHS " in
        *" $NEED "*) ;;
        *) echo "   ✗ в бандле нет среза $NEED (есть: $ARCHS)"; exit 1 ;;
    esac
done
test -s "$APP_STAGE/Contents/Resources/AppIcon.icns"
# Не `test -s`: 16 байт мусора с именем .png его проходят, а иконка при этом
# пустая. `sips` отвечает на настоящий вопрос — картинка вообще декодируется.
sips -g pixelWidth "$APP_STAGE/Contents/Resources/Tomato.png" >/dev/null 2>&1 \
    || { echo "   ✗ Tomato.png в бандле не читается как картинка"; exit 1; }
test -s "$APP_STAGE/Contents/Resources/NothingFont5x7.otf"
codesign --verify "$APP_STAGE"
# PlistBuddy при отсутствии ключа печатает текст ошибки в stdout, поэтому
# сверяем значение, а не просто «строка непустая».
GOT_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP_STAGE/Contents/Info.plist")
[ "$GOT_ID" = "$BUNDLE_ID" ] || { echo "   ✗ bundle id: ожидался $BUNDLE_ID, получено «$GOT_ID»"; exit 1; }
# Версию в бандле сверяем с файлом VERSION: её показывает меню и её же несёт
# отзыв, а пустая или устаревшая строка здесь молча обесценит и то, и другое.
GOT_VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP_STAGE/Contents/Info.plist")
[ "$GOT_VERSION" = "$VERSION" ] || { echo "   ✗ версия: ожидалась $VERSION, получено «$GOT_VERSION»"; exit 1; }
echo "   ✓ бандл целый: срезы $ARCHS, читаемая иконка, подпись, bundle id $GOT_ID"
echo "   ✓ версия $VERSION, сборка $BUILD, коммит $COMMIT"

rm -rf "$APP"
mv "$APP_STAGE" "$APP"
rm -rf "$STAGE"
echo "✓ приложение: $APP"

if [ "${1:-}" = "--app" ]; then exit 0; fi

echo "→ упаковываю DMG"
DMG="$DIST_DIR/$APP_NAME-$VERSION.dmg"
DMG_ROOT="$BUILD_DIR/dmgroot"
rm -rf "$DMG_ROOT"; mkdir -p "$DMG_ROOT"
cp -R "$APP" "$DMG_ROOT/"
ln -s /Applications "$DMG_ROOT/Applications"
rm -f "$DMG"
hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" -ov -format UDZO "$DMG" \
    -quiet 2>/dev/null || hdiutil create -volname "$APP_NAME" -srcfolder "$DMG_ROOT" \
    -ov -format UDZO "$DMG" >/dev/null
rm -rf "$DMG_ROOT"
echo "✓ образ: $DMG ($(du -h "$DMG" | cut -f1))"
