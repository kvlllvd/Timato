#!/bin/bash
# Автотесты по acceptance criteria. Каждая проверка названа номером критерия.
#
# Скрипт всегда пересобирает приложение целиком. Раньше он компилировал только
# ядро и переиспользовал старый бандл из build/ — и печатал «ВСЁ ЗЕЛЁНО» на коде,
# который не компилируется.
set -uo pipefail
cd "$(dirname "$0")"
mkdir -p build
FAILED=0
APP="build/Timato.app"
EXEC="$APP/Contents/MacOS/Timato"

echo "════ Сборка приложения целиком ════"
if ./build.sh --app > /tmp/timer-build.log 2>&1; then
    echo "  ✓ все исходники компилируются, бандл целый"
else
    echo "  ✗ сборка упала — дальше тестировать нечего:"
    tail -15 /tmp/timer-build.log | sed 's/^/     /'
    exit 1
fi

echo
echo "════ Сборка из клона · только отслеживаемые файлы ════"
# Ловушка, на которую проект уже наступал: нужный файл лежит в рабочем дереве,
# но не добавлен в git — и репозиторий после коммита не собирается, хотя у автора
# всё зелено. Собираем копию из одних отслеживаемых файлов: это ровно то, что
# получит `git clone` после `git commit -am`. Удалённые из дерева, но ещё
# отслеживаемые файлы пропускаются — их удаление коммит тоже унесёт.
CLONE=$(mktemp -d)
git ls-files -z | while IFS= read -r -d '' f; do
    [ -f "$f" ] || continue
    mkdir -p "$CLONE/$(dirname "$f")"
    cp "$f" "$CLONE/$f"
done
if (cd "$CLONE" && ./build.sh --app) > /tmp/timer-clone.log 2>&1; then
    echo "  ✓ репозиторий собирается из одних отслеживаемых файлов"
else
    echo "  ✗ из клона не собирается — что-то нужное не добавлено в git:"
    tail -5 /tmp/timer-clone.log | sed 's/^/     /'
    UNTRACKED=$(git ls-files --others --exclude-standard | head -5 | tr '\n' ' ')
    [ -n "$UNTRACKED" ] && echo "     не в git: $UNTRACKED"
    FAILED=1
fi
rm -rf "$CLONE"

echo
echo "════ Тесты ядра ════"
swiftc -O -parse-as-library Sources/TimerEngine.swift Sources/Notifier.swift Tests/EngineTests.swift -o build/tests || exit 1
./build/tests || FAILED=1

echo
echo "════ Ф1.4 · окно поверх всех окон ════"
swiftc -O -parse-as-library Tests/WindowLevelCheck.swift -o build/window-check || exit 1
pkill -f "$EXEC" 2>/dev/null
sleep 0.3
open "$APP"
PID=""
for _ in $(seq 1 20); do
    sleep 0.3
    PID=$(pgrep -f "$EXEC" | head -1)
    [ -n "$PID" ] && ./build/window-check "$PID" >/dev/null 2>&1 && break
done
if [ -z "$PID" ]; then
    echo "  ✗ Ф1.4 приложение не запустилось"; FAILED=1
else
    ./build/window-check "$PID" || FAILED=1
fi
pkill -f "$EXEC" 2>/dev/null

echo
echo "════ Ф2.4 · подпись и bundle identity ════"
if codesign --verify "$APP" 2>/dev/null; then
    echo "  ✓ Ф2.4 ad-hoc подпись валидна"
else
    echo "  ✗ Ф2.4 подпись не проходит проверку"; FAILED=1
fi
BID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$APP/Contents/Info.plist" 2>/dev/null)
if [ "$BID" = "com.dkovalev.timato" ]; then
    echo "  ✓ Ф2.4 bundle identifier: $BID"
else
    echo "  ✗ Ф2.4 bundle identifier: получено «$BID»"; FAILED=1
fi
# Образ уезжает на чужие машины, среди них есть Intel. Бандл с одним arm64
# у автора выглядит рабочим и на Intel не запускается вовсе.
ARCHS=$(lipo -archs "$EXEC" 2>/dev/null)
if [[ "$ARCHS" == *arm64* && "$ARCHS" == *x86_64* ]]; then
    echo "  ✓ Ф2.4 бандл universal: $ARCHS"
else
    echo "  ✗ Ф2.4 в бандле не оба среза: «$ARCHS»"; FAILED=1
fi

echo
echo "════ Живой интерфейс · настоящее окно и его кнопки ════"
# Проверка нажимает кнопки живого окна и читает, что на табло. Собирается из тех
# же Sources со своим @main (флаг -DLIVE_CHECK убирает боевую точку входа) и
# обязательно внутри копии бандла: без bundle identity уведомление не проверить.
# Бандл остаётся в build/ — упавшую проверку можно перезапустить руками.
LIVE_APP="build/LiveCheck.app"
rm -rf "$LIVE_APP"
cp -R "$APP" "$LIVE_APP"
if swiftc -O -parse-as-library -DLIVE_CHECK -target arm64-apple-macos13.0 \
        Sources/*.swift Tests/LiveInterfaceCheck.swift \
        -o "$LIVE_APP/Contents/MacOS/Timato" > /tmp/timer-live.log 2>&1; then
    codesign --force --sign - "$LIVE_APP" >/dev/null 2>&1
    "$LIVE_APP/Contents/MacOS/Timato" || FAILED=1
else
    echo "  ✗ живая проверка не собралась:"
    tail -10 /tmp/timer-live.log | sed 's/^/     /'
    FAILED=1
fi

echo
# Прошлый прогон мог оставить образ подключённым — тогда attach падает с
# «Resource temporarily unavailable», и проверка врала бы про сломанный DMG.
detach_stale_image() {
    hdiutil info 2>/dev/null \
        | awk '/^image-path/ {p=$3} /^\/dev\/disk/ {if (index(p, "dist/Timato.dmg") > 0) print $1}' \
        | while read -r dev; do hdiutil detach "$dev" -force -quiet 2>/dev/null || true; done
}

echo "════ Ф3.1–Ф3.3 · DMG ════"
detach_stale_image
if ./build.sh > /tmp/timer-dmg.log 2>&1 && [ -f "dist/Timato.dmg" ]; then
    echo "  ✓ Ф3.1 ./build.sh создал dist/Timato.dmg ($(du -h dist/Timato.dmg | cut -f1))"
else
    echo "  ✗ Ф3.1 DMG не собрался"; FAILED=1
fi
MP=$(hdiutil attach "dist/Timato.dmg" -nobrowse -readonly 2>/dev/null | grep -o '/Volumes/.*$' | head -1)
if [ -z "$MP" ]; then detach_stale_image; sleep 0.5
    MP=$(hdiutil attach "dist/Timato.dmg" -nobrowse -readonly 2>/dev/null | grep -o '/Volumes/.*$' | head -1)
fi
if [ -n "$MP" ]; then
    if [ -d "$MP/Timato.app" ]; then echo "  ✓ Ф3.2 внутри образа есть Timato.app"; else echo "  ✗ Ф3.2 в образе нет Timato.app"; FAILED=1; fi
    if [ -L "$MP/Applications" ]; then echo "  ✓ Ф3.2 внутри образа есть ссылка на /Applications"; else echo "  ✗ Ф3.2 в образе нет ссылки на /Applications"; FAILED=1; fi
    # Проверяем именно копию из образа: раздаётся она, а не build/.
    DMG_ARCHS=$(lipo -archs "$MP/Timato.app/Contents/MacOS/Timato" 2>/dev/null)
    if [[ "$DMG_ARCHS" == *arm64* && "$DMG_ARCHS" == *x86_64* ]]; then
        echo "  ✓ Ф3.2 приложение в образе universal: $DMG_ARCHS"
    else
        echo "  ✗ Ф3.2 в образе не оба среза: «$DMG_ARCHS»"; FAILED=1
    fi
    # Ф3.3: запускаем именно ту копию, что лежит в образе.
    rm -rf /tmp/timer-from-dmg && mkdir -p /tmp/timer-from-dmg
    cp -R "$MP/Timato.app" /tmp/timer-from-dmg/ 2>/dev/null
    hdiutil detach "$MP" -quiet 2>/dev/null
    open /tmp/timer-from-dmg/Timato.app 2>/dev/null
    DMG_PID=""
    for _ in $(seq 1 20); do
        sleep 0.3
        DMG_PID=$(pgrep -f "/tmp/timer-from-dmg/Timato.app/Contents/MacOS/Timato" | head -1)
        [ -n "$DMG_PID" ] && break
    done
    if [ -n "$DMG_PID" ]; then
        echo "  ✓ Ф3.3 приложение из образа запускается (pid $DMG_PID)"
    else
        echo "  ✗ Ф3.3 приложение из образа не запустилось"; FAILED=1
    fi
    pkill -f "/tmp/timer-from-dmg/Timato.app/Contents/MacOS/Timato" 2>/dev/null
    rm -rf /tmp/timer-from-dmg
else
    echo "  ✗ Ф3.2 образ не монтируется"; FAILED=1
fi
detach_stale_image

echo
if [ "$FAILED" -eq 0 ]; then echo "══ ВСЁ ЗЕЛЁНО ══"; else echo "══ ЕСТЬ ПАДЕНИЯ ══"; fi
exit $FAILED
