import AppKit
import UserNotifications

// Живая проверка настоящего интерфейса: та же `AppDelegate`, то же окно, те же
// кнопки. Проверки нажимают `performClick` и читают, что оказалось на экране, —
// а не сверяют чистые функции, это уже делает `Tests/EngineTests.swift`.
//
// Собирается вместе с `Sources/*.swift` под флагом `-DLIVE_CHECK`, который
// убирает боевую точку входа в `App.swift`. Обязательно внутри копии бандла:
// без bundle identity уведомления не проверить.

private var failures: [String] = []
private var passed = 0

private func check(_ id: String, _ what: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok { passed += 1; print("  ✓ \(id) \(what)"); return }
    let d = detail()
    failures.append("\(id) \(what)\(d.isEmpty ? "" : " — \(d)")")
    print("  ✗ \(id) \(what)\(d.isEmpty ? "" : " — \(d)")")
}

/// Прокрутить главный цикл: без этого не проходят ни раскладка, ни анимации,
/// ни ответы Центра уведомлений.
private func pump(_ seconds: TimeInterval = 0.35) {
    RunLoop.current.run(until: Date().addingTimeInterval(seconds))
}

/// Крутить цикл, пока условие не выполнится или не выйдет время.
@discardableResult
private func wait(upTo seconds: TimeInterval, until done: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !done() && Date() < deadline { pump(0.1) }
    return done()
}

private func descendants<T: NSView>(_ type: T.Type, of view: NSView) -> [T] {
    var found: [T] = []
    if let hit = view as? T { found.append(hit) }
    for sub in view.subviews { found.append(contentsOf: descendants(type, of: sub)) }
    return found
}

/// Видно ли вид на самом деле. Одного родителя мало: кнопки выбора лежат в
/// скрываемом `NSStackView` через промежуточный контейнер — прошлый регресс
/// на этом получил ложное падение.
private func onScreen(_ view: NSView) -> Bool {
    var node: NSView? = view
    while let current = node {
        if current.isHidden { return false }
        node = current.superview
    }
    return true
}

private func hex(_ color: CGColor?) -> String {
    guard let color,
          let rgb = color.converted(to: CGColorSpace(name: CGColorSpace.sRGB)!,
                                    intent: .defaultIntent, options: nil),
          let c = rgb.components, c.count >= 3 else { return "нет цвета" }
    return String(format: "#%02X%02X%02X",
                  Int(c[0] * 255 + 0.5), Int(c[1] * 255 + 0.5), Int(c[2] * 255 + 0.5))
}

@main
enum LiveInterfaceCheck {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        app.delegate = delegate
        // `app.run()` не вызываем: цикл крутится вручную, иначе проверка не
        // получит управление обратно. Поэтому же `NSApp.isRunning` здесь ничего
        // не значит — про «приложение живо» его спрашивать нельзя.
        delegate.applicationDidFinishLaunching(
            Notification(name: NSApplication.didFinishLaunchingNotification))
        pump(0.6)

        guard let window = NSApp.windows.first(where: { $0.title == "Timato" }),
              let content = window.contentView else {
            print("  ✗ окно не создалось — проверять нечего")
            exit(1)
        }
        content.layoutSubtreeIfNeeded()
        pump()

        // Тема приходит из настроек: на светлой машине и с выбранной «Light»
        // весь дизайн-раздел проверял бы не те цвета. Проверка идёт по тёмной
        // теме — она в макете основная, — а светлая проверяется своим разделом
        // («С»). Выбор человека возвращаем перед выходом: настройки общие.
        let savedTheme = Theme.current
        Theme.current = .dark
        pump()

        let root = descendants(RootView.self, of: content).first!
        let controller = window.windowController as! TimerWindowController

        // Место окна приходит из прошлого запуска — оно могло остаться и
        // прижатым к краю экрана, где углы пилюли обязаны быть прямыми.
        // Проверке нужна определённость: ставим окно в середину экрана.
        if let screen = window.screen ?? NSScreen.main {
            window.setFrame(NSRect(origin: NSPoint(x: screen.frame.midX - window.frame.width / 2,
                                                   y: screen.frame.midY - window.frame.height / 2),
                                   size: window.frame.size), display: true)
            pump(0.2)
        }

        // Курсор у проверки свой: настоящая мышь стоит там, где её оставил
        // человек, и от неё зависел бы ёмкий вид — а с ним ширина окна.
        // По умолчанию держим «курсор на окне»: тогда трекер всегда полный,
        // как и был до появления ёмкого вида, и остальные проверки не плывут.
        var pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        controller.pointerLocation = { pointer }
        /// Курсор далеко за пределами любого экрана — окну не на что реагировать.
        let pointerAway = NSPoint(x: -10_000, y: -10_000)
        /// Ширина видимой пилюли: у окна вокруг неё ещё поле под тень.
        func pillWidth() -> CGFloat { window.frame.width - TimerWindowController.shadowMargin * 2 }
        let clock = descendants(FlipClockView.self, of: content).first!
        let bar = descendants(ProgressBar.self, of: content).first!
        let segments = descendants(SegmentsView.self, of: content).first!
        let buttons = descendants(PillButton.self, of: content)

        func button(_ label: String) -> PillButton? {
            buttons.first { $0.accessibilityLabel() == label }
        }
        func visiblePresets() -> [Int] {
            buttons.filter { $0.tag > 0 && onScreen($0) }.map(\.tag).sorted()
        }
        /// Что написано на табло прямо сейчас — по самим разрядам, слева направо.
        func face() -> String {
            String(descendants(DigitSlot.self, of: clock)
                .sorted { $0.frame.minX < $1.frame.minX }
                .map(\.character))
        }
        func backdrop() -> CGColor? {
            root.layer?.sublayers?.compactMap { $0 as? CAShapeLayer }.first?.fillColor
        }
        /// Доля залитой полосы: маска градиента и есть прогресс.
        func filled() -> CGFloat {
            guard let gradient = bar.layer?.sublayers?.compactMap({ $0 as? CAGradientLayer }).first,
                  let mask = gradient.mask, bar.bounds.width > 0 else { return -1 }
            return ((mask.presentation() ?? mask).bounds.width / bar.bounds.width * 100).rounded() / 100
        }

        print("\nЭкран выбора при открытии")
        check("К5", "варианты на экране — ровно 25 и 50", visiblePresets() == [25, 50],
              "видно \(visiblePresets())")
        check("К5", "пятиминутки руками нет — она приходит сама",
              !visiblePresets().contains(5), "видно \(visiblePresets())")
        check("К5", "табло отсчёта скрыто", !onScreen(clock))
        check("К5", "полоса остатка скрыта", !onScreen(bar))
        check("К5", "ряд засечек виден", onScreen(segments))
        check("Д", "фон экрана выбора чёрный", hex(backdrop()) == "#000000", hex(backdrop()))

        print("\nДизайн из макета")
        check("Д", "окно 294×86",
              TimerWindowController.windowSize == NSSize(width: 294, height: 86),
              "\(TimerWindowController.windowSize)")
        check("Д", "скругление окна 8", root.cornerRadii == (8, 8, 8, 8), "\(root.cornerRadii)")
        check("Д", "скругление кнопок 4, а не полукруг",
              PillButton.cornerRadius == 4 && button("25 min")?.layer?.cornerRadius == 4,
              "константа \(PillButton.cornerRadius), у живой кнопки \(button("25 min")?.layer?.cornerRadius ?? -1)")
        check("Д", "кнопка выбора высотой 40 из макета",
              button("25 min")?.frame.height == PillButton.rowHeight,
              "\(button("25 min")?.frame.height ?? -1)")
        check("Д", "фон кнопок отсчёта #1D1D1D", hex(Palette.focus.control.cgColor) == "#1D1D1D",
              hex(Palette.focus.control.cgColor))
        check("Д", "шрифт табло — Nothing 5x7 из бандла",
              DisplayFont.of(size: 24).fontName.lowercased().contains("nothing"),
              DisplayFont.of(size: 24).fontName)

        print("\nК1 · вариант запускает отсчёт")
        button("25 min")?.performClick(nil)
        pump()
        check("К1", "экран сменился на отсчёт",
              onScreen(clock) && button("25 min").map(onScreen) != true)
        check("К1", "на табло 25:00", face() == "25:00", "получено «\(face())»")
        check("К1", "полоса видна и пуста", onScreen(bar) && filled() < 0.05, "залито \(filled())")
        // Сравнение с Доком, а не с конкретным уровнем: «поверх всех окон» на
        // `.floating` (3) было зелёным, пока пилюля пряталась за Доком (20).
        let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
        check("К7", "окно поверх обычных окон и Дока", window.level.rawValue > dockLevel,
              "уровень \(window.level.rawValue), Док \(dockLevel)")
        check("К1", "три кнопки отсчёта на месте",
              ["Pause", "Finish now", "Stop"].allSatisfy { button($0).map(onScreen) == true })

        print("\nК3 · пауза и продолжение")
        button("Pause")?.performClick(nil)
        pump()
        check("К3", "кнопка стала «Resume»", button("Resume") != nil && button("Pause") == nil)
        check("К3", "фон паузы серый #494949", hex(backdrop()) == "#494949", hex(backdrop()))
        let frozen = face()
        pump(1.2)
        check("К3", "на паузе время стоит", face() == frozen, "было \(frozen), стало \(face())")
        button("Resume")?.performClick(nil)
        pump()
        check("К3", "после продолжения кнопка снова «Pause»", button("Pause") != nil)
        check("К3", "фон вернулся в чёрный", hex(backdrop()) == "#000000", hex(backdrop()))

        print("\nК4 · стоп бросает отрезок")
        button("Stop")?.performClick(nil)
        pump()
        check("К4", "вернулся экран выбора",
              visiblePresets() == [25, 50] && !onScreen(clock), "видно \(visiblePresets())")
        check("К4", "ряд за брошенный отрезок не двинулся", segments.filledHalves == 0,
              "половинок \(segments.filledHalves)")

        print("\nД1 · отработанный отрезок и авто-отдых")
        button("25 min")?.performClick(nil)
        pump()
        // Первый переход за запуск, и потому самый дорогой: раньше он поднимал
        // звуковой движок прямо на главном потоке и подвисал на треть секунды,
        // а все следующие переходы шли быстро. Порог с запасом: было ~370 мс,
        // стало ~10 мс, между ними мерить нечего.
        let switchStart = DispatchTime.now().uptimeNanoseconds
        button("Finish now")?.performClick(nil)
        let firstSwitchMs = Double(DispatchTime.now().uptimeNanoseconds - switchStart) / 1_000_000
        check("Д1", "первый переход работа→отдых не подвисает", firstSwitchMs < 150,
              String(format: "главный поток занят %.1f мс", firstSwitchMs))
        pump(0.8)
        check("Д1", "звонок при этом звучит", Chime.isSounding)
        check("Д1", "сам встал отдых 05:00", face() == "05:00", "получено «\(face())»")
        check("Д1", "фон отдыха не чёрный", hex(backdrop()) != "#000000", hex(backdrop()))
        check("Д2", "25 минут закрасили половину черточки", segments.filledHalves == 1,
              "половинок \(segments.filledHalves)")
        check("Д1", "на отдыхе из кнопок только «стоп»",
              button("Stop").map(onScreen) == true
              && button("Pause").map(onScreen) != true
              && button("Finish now").map(onScreen) != true)
        button("Stop")?.performClick(nil)
        pump()
        check("Д1", "после отдыха снова экран выбора", visiblePresets() == [25, 50],
              "видно \(visiblePresets())")
        check("Д2", "ряд сохранился между отрезками", segments.filledHalves == 1,
              "половинок \(segments.filledHalves)")

        // Длинный отрезок берёт длинный отдых: 50 минут — десять, а не пять.
        button("50 min")?.performClick(nil)
        pump()
        button("Finish now")?.performClick(nil)
        pump(0.8)
        check("Д1", "после 50 минут сам встал отдых 10:00", face() == "10:00",
              "получено «\(face())»")
        button("Stop")?.performClick(nil)
        pump()
        check("Д1", "после десятиминутки снова экран выбора", visiblePresets() == [25, 50],
              "видно \(visiblePresets())")
        // Длинный отрезок закрасил целую черточку — возвращаем ряд к тем же
        // половинкам, с какими сюда пришли: дальше на них считают другие проверки.
        _ = delegate.perform(NSSelectorFromString("resetProgress"))
        button("25 min")?.performClick(nil)
        pump()
        button("Finish now")?.performClick(nil)
        pump(0.8)
        button("Stop")?.performClick(nil)
        pump()
        check("Д2", "ряд вернулся к одной половинке", segments.filledHalves == 1,
              "половинок \(segments.filledHalves)")

        print("\nПравки из Figma")

        // 3 — четыре черточки во всю ширину окна, а не короткий ряд засечек.
        check("Ф3", "поначалу черточек четыре", Segments.shown(filledHalves: 0) == 4)
        check("Ф3", "ряд растянут во всю ширину между отступами",
              abs(segments.frame.width - (TimerWindowController.windowSize.width - 32)) < 0.5,
              "ширина \(segments.frame.width)")

        // 3 (второй заход) — полоса отсчёта стоит на той же линии, что и штрихи.
        // Скрытый вид Auto Layout всё равно расставляет, поэтому обе рамки
        // сравнимы, хотя на экране сейчас только одна из них.
        check("Ф3", "полоса отсчёта на одной линии со штрихами",
              bar.frame.minY == segments.frame.minY,
              "полоса \(bar.frame.minY), штрихи \(segments.frame.minY)")

        // 1 (второй заход) — штрихи и полоса стоят на 16 от низа окна.
        let bottomInset = TimerWindowController.windowSize.height - segments.frame.maxY
        check("Ф1", "штрихи на 16 от низа окна", bottomInset == 16, "отступ \(bottomInset)")
        check("Ф1", "полоса отсчёта на 16 от низа окна",
              TimerWindowController.windowSize.height - bar.frame.maxY == 16,
              "отступ \(TimerWindowController.windowSize.height - bar.frame.maxY)")

        // 2, 3 — кнопка сброса той же высоты 40, что и кнопки выбора.
        check("Ф2", "кнопка сброса высотой 40",
              button("Reset progress")?.frame.height == PillButton.rowHeight,
              "\(button("Reset progress")?.frame.height ?? -1)")

        // 4 — 25 минут закрашивают половину черточки, 50 целую.
        check("Ф4", "после 25 минут закрашена половина первой черточки",
              segmentFill(index: 0, filledHalves: segments.filledHalves) == 0.5,
              "половинок \(segments.filledHalves)")

        // 1 — клик по ряду показывает кнопку сброса вместо 25/50, повторный
        // клик возвращает 25/50, а клик по самой кнопке сбрасывает прогресс.
        check("Ф1", "до клика кнопка сброса скрыта",
              button("Reset progress").map(onScreen) != true)
        segments.onClick?()
        pump()
        let reset = button("Reset progress")
        check("Ф1", "клик по штрихам показал кнопку сброса", reset.map(onScreen) == true)
        check("Ф1", "и она заняла место кнопок выбора",
              visiblePresets().isEmpty && reset?.frame.width == segments.frame.width,
              "видно \(visiblePresets()), ширина \(reset?.frame.width ?? -1)")

        segments.onClick?()
        pump()
        check("Ф1", "повторный клик по штрихам вернул 25/50",
              visiblePresets() == [25, 50] && reset.map(onScreen) != true,
              "видно \(visiblePresets())")
        check("Ф1", "и прогресс при этом не тронут", segments.filledHalves == 1,
              "половинок \(segments.filledHalves)")

        segments.onClick?()
        pump()
        reset?.performClick(nil)
        pump()
        check("Ф1", "клик по кнопке сбросил весь прогресс", segments.filledHalves == 0,
              "половинок \(segments.filledHalves)")
        check("Ф1", "после сброса вернулись кнопки выбора",
              visiblePresets() == [25, 50] && reset.map(onScreen) != true,
              "видно \(visiblePresets())")

        segments.onClick?()
        pump()
        check("Ф1", "на пустом ряду сбрасывать нечего — кнопки нет",
              button("Reset progress").map(onScreen) != true)
        segments.onClick?()
        pump()

        // 2 — зелёный хвост полосы у рабочего отсчёта.
        check("Ф2", "полоса кончается зелёным из макета",
              hex(Palette.focus.fill.last?.cgColor) == "#00EF80",
              hex(Palette.focus.fill.last?.cgColor))
        check("Ф2", "до 0.851 полоса белая, дальше начинается хвост",
              Palette.focus.fillStops?.first == 0
              && Palette.focus.fillStops?.last == 1
              && hex(Palette.focus.fill.first?.cgColor) == "#FFFFFF"
              && (Palette.focus.fillStops?[1].doubleValue ?? 0) == 0.851,
              "\(Palette.focus.fillStops ?? [])")
        check("Ф2", "у отдыха зелёного хвоста нет — окно и так зелёное",
              Palette.rest.fillStops == nil)
        check("Ф2", "на паузе хвост тот же самый",
              Palette.focusPaused.fillStops == Palette.focus.fillStops)

        // Хвост разложен на промежуточные точки: `CAGradientLayer` смешивает
        // соседние цвета не так, как макет, и на двух точках зелёный выцветал
        // в мятный. Проверяем и что точек много, и что каждая стоит там, где
        // её посчитал бы макет — линейно между белым и зелёным.
        let ramp = Palette.focus.fill
        let rampStops = Palette.focus.fillStops ?? []
        check("Ф2", "хвост разложен на промежуточные точки", ramp.count >= 8,
              "точек \(ramp.count)")
        check("Ф2", "точек цвета и точек положения поровну", ramp.count == rampStops.count,
              "\(ramp.count) против \(rampStops.count)")
        check("Ф2", "положения идут по возрастанию",
              zip(rampStops, rampStops.dropFirst()).allSatisfy { $0.doubleValue <= $1.doubleValue })
        var rampExact = true
        for (color, stop) in zip(ramp.dropFirst(), rampStops.dropFirst()) {
            let t = (stop.doubleValue - 0.851) / (1 - 0.851)
            guard t >= 0, let srgb = color.usingColorSpace(.sRGB) else { continue }
            let want = (r: 1 - t, g: 1 + (239.0 / 255 - 1) * t, b: 1 + (128.0 / 255 - 1) * t)
            if abs(srgb.redComponent - want.r) > 0.01
                || abs(srgb.greenComponent - want.g) > 0.01
                || abs(srgb.blueComponent - want.b) > 0.01 { rampExact = false }
        }
        check("Ф2", "каждая точка хвоста считается как в макете", rampExact)

        // 6 — на паузе фон кнопки ровно такой же, как под курсором.
        check("Ф6", "пауза помечает кнопки как под курсором",
              Palette.focusPaused.controlLifted && Palette.restPaused.controlLifted)
        check("Ф6", "на ходу — нет", !Palette.focus.controlLifted && !Palette.rest.controlLifted)
        // Осветление обязано быть непрозрачным: полупрозрачная кнопка пускала
        // бы через себя фон, и на сером фоне паузы выходила светлее, чем на чёрном.
        let lifted = Palette.focus.control.blended(withFraction: Palette.hoverLiftFraction,
                                                   of: Palette.hoverLift)
        check("Ф6", "осветлённая кнопка непрозрачна и от фона не зависит",
              lifted?.alphaComponent == 1, "альфа \(lifted?.alphaComponent ?? -1)")
        check("Ф6", "на ходу и на паузе заливка кнопок одна и та же",
              Palette.focus.control == Palette.focusPaused.control,
              "\(hex(Palette.focus.control.cgColor)) против \(hex(Palette.focusPaused.control.cgColor))")
        // И то же самое на живой кнопке, а не только в палитре: ставим отсчёт
        // на паузу и читаем цвет слоя прямо из окна.
        button("25 min")?.performClick(nil)
        pump()
        let running = hex(button("Pause")?.layer?.backgroundColor)
        button("Pause")?.performClick(nil)
        pump()
        let onPause = button("Resume")?.layer?.backgroundColor
        check("Ф6", "на паузе фон кнопки светлее, чем на ходу",
              hex(onPause) != running, "и там и там \(running)")
        check("Ф6", "и он непрозрачен — серый фон паузы через кнопку не просвечивает",
              onPause?.alpha == 1, "альфа \(onPause?.alpha ?? -1)")
        check("Ф6", "фон паузы равен осветлению наведения",
              hex(onPause) == hex(lifted?.cgColor),
              "\(hex(onPause)) против \(hex(lifted?.cgColor))")
        button("Stop")?.performClick(nil)
        pump()

        // 7 — клик по табло перебирает цвет свечения.
        button("25 min")?.performClick(nil)
        pump()
        /// Цвет свечения, как он лежит в живом слое окна.
        func glowColor() -> String {
            let gradient = root.layer?.sublayers?.compactMap { $0 as? CAGradientLayer }.first
            return hex((gradient?.colors as? [CGColor])?.first)
        }
        let cycle = [Palette.glow(.purple), Palette.glow(.blue),
                     Palette.glow(.red), Palette.glow(.green)]
        check("Ф7", "по умолчанию свечение зелёное",
              glowColor() == hex(Palette.glow(.green).cgColor), glowColor())
        var cycled = true
        for expected in cycle {
            clock.onClick?()
            pump()
            if glowColor() != hex(expected.cgColor) { cycled = false }
        }
        check("Ф7", "клики по табло дают фиолетовый, синий, красный и снова зелёный", cycled,
              "остановились на \(glowColor())")
        button("Stop")?.performClick(nil)
        pump()

        print("\nПравки: клик по полосе и «стоп» на отдыхе")

        // Б1 — клик по полосе остатка на идущем отсчёте не должен ничего менять.
        // Ряд штрихов спрятан, но лежит ровно под полосой: раньше он забирал
        // нажатие и вываливал кнопки 25/50 поверх табло.
        button("25 min")?.performClick(nil)
        pump()
        let ticking = face()
        // Точка в середине полосы, в координатах корневого вида.
        let onBar = NSPoint(x: bar.frame.midX, y: bar.frame.midY)
        let caught = bar.superview?.hitTest(onBar)
        check("Б1", "нажатие на полосе не попадает в спрятанный ряд штрихов",
              !(caught is SegmentsView), "поймал \(type(of: caught as Any))")
        check("Б1", "спрятанный ряд вообще не участвует в поиске",
              segments.hitTest(onBar) == nil)
        // И тот же путь целиком, как у настоящего клика.
        segments.onClick?()
        pump()
        check("Б1", "кнопки 25/50 не вылезли поверх отсчёта",
              visiblePresets().isEmpty, "видно \(visiblePresets())")
        check("Б1", "кнопка сброса тоже не появилась",
              button("Reset progress").map(onScreen) != true)
        check("Б1", "табло на месте и отсчёт идёт", onScreen(clock)
              && wait(upTo: 3) { face() != ticking }, "табло стоит на \(ticking)")

        // Б2 — «стоп» на отдыхе шириной 128 и с отступом 16 справа.
        check("Б2", "на работе «стоп» квадратный 40",
              button("Stop")?.frame.width == TimerWindowController.controlSize,
              "\(button("Stop")?.frame.width ?? -1)")
        button("Finish now")?.performClick(nil)
        pump()
        let stop = button("Stop")
        check("Б2", "на отдыхе «стоп» шириной 128",
              stop?.frame.width == TimerWindowController.restStopWidth,
              "\(stop?.frame.width ?? -1)")
        if let stop, let inRoot = stop.superview?.convert(stop.frame, to: root) {
            check("Б2", "отступ справа 16",
                  TimerWindowController.windowSize.width - inRoot.maxX == 16,
                  "отступ \(TimerWindowController.windowSize.width - inRoot.maxX)")
            check("Б2", "высота осталась 40",
                  inRoot.height == TimerWindowController.controlSize, "\(inRoot.height)")
        }
        button("Stop")?.performClick(nil)
        pump()
        // Ширину назначает только `showCountdown`, поэтому проверяем её там,
        // где она видна пользователю: на следующем рабочем отрезке.
        button("25 min")?.performClick(nil)
        pump()
        check("Б2", "на следующей работе «стоп» снова квадратный",
              button("Stop")?.frame.width == TimerWindowController.controlSize,
              "\(button("Stop")?.frame.width ?? -1)")
        check("Б2", "и все три кнопки снова на месте",
              ["Pause", "Finish now", "Stop"].allSatisfy { button($0).map(onScreen) == true })
        button("Stop")?.performClick(nil)
        pump()

        print("\nУ · пилюля доходит до физических углов экрана")
        // Ловушка, ради которой эта проверка и написана: «поверх всех окон» и
        // прилипание к углу могут быть на месте, а окно всё равно упирается
        // в невидимую преграду — полосу меню сверху и Док снизу. Границей
        // считается `frame` экрана, а не `visibleFrame`.
        if let screen = window.screen ?? NSScreen.main {
            let inset = (window as? SnappingWindow)?.contentInset ?? 0
            let pillSize = TimerWindowController.windowSize
            let saved = window.frame

            /// Ставит окно так, чтобы видимая пилюля оказалась в точке `origin`.
            func placePill(at origin: NSPoint) {
                window.setFrame(NSRect(origin: NSPoint(x: origin.x - inset, y: origin.y - inset),
                                       size: window.frame.size), display: true)
                pump(0.2)
            }
            /// Видимая пилюля без поля под тень.
            func pill() -> NSRect { window.frame.insetBy(dx: inset, dy: inset) }

            // Подводим почти к углу — остаток окно должно пройти прилипанием.
            placePill(at: NSPoint(x: screen.frame.maxX - pillSize.width - 10,
                                  y: screen.frame.maxY - pillSize.height - 10))
            check("У", "прилипла к верхнему правому углу экрана",
                  abs(pill().maxX - screen.frame.maxX) < 0.5
                      && abs(pill().maxY - screen.frame.maxY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")
            check("У", "верх пилюли выше полосы меню",
                  pill().maxY > screen.visibleFrame.maxY,
                  "верх \(pill().maxY), видимая область кончается на \(screen.visibleFrame.maxY)")
            // Скругление остаётся только у того угла, обе стороны которого
            // лежат внутри экрана. У пилюли в правом верхнем углу это левый
            // нижний: остальные три сошлись на кромке.
            check("У", "у верхнего правого угла экрана скруглён один угол — левый нижний",
                  root.cornerRadii == (0, 0, 0, pillCornerRadius), "\(root.cornerRadii)")

            placePill(at: NSPoint(x: screen.frame.minX + 10, y: screen.frame.minY + 10))
            check("У", "прилипла к нижнему левому углу экрана",
                  abs(pill().minX - screen.frame.minX) < 0.5
                      && abs(pill().minY - screen.frame.minY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")
            check("У", "низ пилюли ниже Дока", pill().minY < screen.visibleFrame.minY,
                  "низ \(pill().minY), видимая область начинается с \(screen.visibleFrame.minY)")
            check("У", "у нижнего левого угла экрана скруглён один угол — правый верхний",
                  root.cornerRadii == (0, pillCornerRadius, 0, 0), "\(root.cornerRadii)")

            // Одной стороны довольно: прижатым боком у окна прямые оба угла
            // на этом боку, хотя ни в какой угол экрана оно не приклеено.
            placePill(at: NSPoint(x: screen.frame.minX - 50, y: screen.frame.midY))
            check("У", "прижата к левой стороне экрана, но не в углу",
                  abs(pill().minX - screen.frame.minX) < 0.5
                      && pill().minY > screen.frame.minY && pill().maxY < screen.frame.maxY,
                  "пилюля \(pill()), экран \(screen.frame)")
            check("У", "у прижатого бока прямые оба угла, у свободного — скруглённые",
                  root.cornerRadii == (0, pillCornerRadius, pillCornerRadius, 0),
                  "\(root.cornerRadii)")

            // Центр кромки тянет так же, как угол, и по всем четырём сторонам:
            // подводим почти к середине края — остаток проходит прилипанием.
            placePill(at: NSPoint(x: screen.frame.midX - pillSize.width / 2 + 12,
                                  y: screen.frame.maxY - pillSize.height - 10))
            check("У", "прилипла к центру верхней кромки",
                  abs(pill().midX - screen.frame.midX) < 0.5
                      && abs(pill().maxY - screen.frame.maxY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")

            placePill(at: NSPoint(x: screen.frame.midX - pillSize.width / 2 - 12,
                                  y: screen.frame.minY + 10))
            check("У", "прилипла к центру нижней кромки",
                  abs(pill().midX - screen.frame.midX) < 0.5
                      && abs(pill().minY - screen.frame.minY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")

            placePill(at: NSPoint(x: screen.frame.minX + 10,
                                  y: screen.frame.midY - pillSize.height / 2 + 12))
            check("У", "прилипла к центру левой кромки",
                  abs(pill().minX - screen.frame.minX) < 0.5
                      && abs(pill().midY - screen.frame.midY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")

            placePill(at: NSPoint(x: screen.frame.maxX - pillSize.width - 10,
                                  y: screen.frame.midY - pillSize.height / 2 - 12))
            check("У", "прилипла к центру правой кромки",
                  abs(pill().maxX - screen.frame.maxX) < 0.5
                      && abs(pill().midY - screen.frame.midY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")

            // В стороне от середины кромка не тянет: вдоль края окно едет
            // свободно, иначе его нельзя было бы поставить рядом с центром.
            placePill(at: NSPoint(x: screen.frame.midX - pillSize.width / 2 - 60,
                                  y: screen.frame.maxY - pillSize.height))
            check("У", "в стороне от центра кромка к середине не тянет",
                  abs(pill().midX - (screen.frame.midX - 60)) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")

            // Вдали от краёв пилюля снова скруглена вся.
            placePill(at: NSPoint(x: screen.frame.midX, y: screen.frame.midY))
            check("У", "вдали от краёв скругление вернулось",
                  root.cornerRadii == (pillCornerRadius, pillCornerRadius,
                                       pillCornerRadius, pillCornerRadius),
                  "\(root.cornerRadii)")

            // Та же таблица без окна: чистой функцией, всеми четырьмя углами.
            check("У", "ничего не касается — скруглены все четыре",
                  cornerRadii(touching: [], radius: 8) == (8, 8, 8, 8),
                  "\(cornerRadii(touching: [], radius: 8))")
            check("У", "прижат верх — прямые оба верхних",
                  cornerRadii(touching: .top, radius: 8) == (0, 0, 8, 8),
                  "\(cornerRadii(touching: .top, radius: 8))")
            check("У", "прижаты низ и право — скруглён только левый верхний",
                  cornerRadii(touching: [.bottom, .right], radius: 8) == (8, 0, 0, 0),
                  "\(cornerRadii(touching: [.bottom, .right], radius: 8))")

            // Притяжение — тоже чистой функцией, на выдуманном экране 1000×1000.
            let box = NSRect(x: 0, y: 0, width: 1000, height: 1000)
            check("У", "у середины верхней кромки притягивает центр",
                  snapSpot(for: NSRect(x: 410, y: 890, width: 200, height: 100),
                           on: box, within: 24) == .topCenter)
            check("У", "у самого угла важнее угол, а не центр",
                  snapSpot(for: NSRect(x: 5, y: 890, width: 200, height: 100),
                           on: box, within: 24) == .topLeft)
            check("У", "кромка без середины не тянет",
                  snapSpot(for: NSRect(x: 300, y: 890, width: 200, height: 100),
                           on: box, within: 24) == nil)
            check("У", "середина без кромки не тянет",
                  snapSpot(for: NSRect(x: 410, y: 450, width: 200, height: 100),
                           on: box, within: 24) == nil)
            check("У", "ёмкая ширина ловит ту же середину и встаёт по ней",
                  snapSpot(for: NSRect(x: 460, y: 890, width: 100, height: 100),
                           on: box, within: 24)?
                      .origin(for: NSSize(width: 100, height: 100), on: box)
                      == NSPoint(x: 450, y: 900))

            window.setFrame(saved, display: true)
            pump(0.2)
        } else {
            check("У", "экран найден", false, "NSScreen недоступен")
        }

        print("\nП · окно запоминает своё место")
        // Ловушка: имя для автосохранения выдавалось окну до центрирования при
        // сборке, и первое же программное перемещение затирало место, оставленное
        // в прошлый раз. Место «восстанавливалось» — из значения, записанного
        // секунду назад тем же запуском.
        let frameKey = "NSWindow Frame " + (window.frameAutosaveName.isEmpty ? "TimatoWindow"
                                                                             : window.frameAutosaveName)
        check("П", "окну выдано имя для запоминания места", !window.frameAutosaveName.isEmpty,
              "имя «\(window.frameAutosaveName)»")
        let before = window.frame
        let moved = NSRect(origin: NSPoint(x: 320, y: 240), size: window.frame.size)
        window.setFrame(moved, display: true)
        pump(0.3)
        let saved = UserDefaults.standard.string(forKey: frameKey) ?? ""
        let numbers = saved.split(separator: " ").compactMap { Double($0) }
        check("П", "новое место записано в настройки",
              numbers.count >= 2 && abs(numbers[0] - window.frame.origin.x) < 1
                  && abs(numbers[1] - window.frame.origin.y) < 1,
              "в настройках «\(saved)», окно на \(window.frame.origin)")
        // Место окна теперь и правда переживает запуски, поэтому проверка обязана
        // вернуть окно на место: иначе каждый прогон тестов утаскивал бы пилюлю
        // пользователя туда, где её оставил последний тест.
        window.setFrame(before, display: true)
        pump(0.3)

        print("\nК8 · помидор в строке меню")
        let statusImage = TomatoIcon.statusBarImage()
        check("К8", "иконка непустого размера",
              statusImage.size.width > 1 && statusImage.size.height > 1, "размер \(statusImage.size)")
        var ink = 0
        if let tiff = statusImage.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            for x in 0..<rep.pixelsWide where ink == 0 {
                for y in 0..<rep.pixelsHigh
                where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.1 {
                    ink += 1
                }
            }
        }
        check("К8", "в иконке есть чернила, а не прозрачный квадрат", ink > 0,
              "непрозрачных пикселей \(ink)")
        check("К8", "иконка помечена шаблонной — система перекрасит под тему", statusImage.isTemplate)

        print("\nР20 · Cmd+W закрывает окно, отсчёт при этом идёт")
        button("25 min")?.performClick(nil)
        pump()
        let beforeClose = face()
        let closeItem = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "w" }
        check("Р20", "пункт «Close Window» в меню есть", closeItem != nil)
        if let closeItem, let action = closeItem.action {
            check("Р20", "у пункта есть свой обработчик, а не системный performClose:",
                  closeItem.target != nil && action != #selector(NSWindow.performClose(_:)),
                  "target \(String(describing: closeItem.target)), action \(action)")
            // Именно это AppKit делает перед тем, как отдать Cmd+W пункту:
            // прогоняет автовалидацию меню и смотрит, включён ли пункт. Раньше
            // здесь и обрывалось — `performClose:` у `.borderless` окна гасил
            // пункт, и до действия сочетание не доходило.
            closeItem.menu?.update()
            check("Р20", "после автовалидации меню пункт включён — Cmd+W дойдёт",
                  closeItem.isEnabled, "пункт выключен")
            // Настоящий путь сочетания клавиш, а не вызов действия в обход
            // меню: ровно это AppKit делает, когда пользователь жмёт Cmd+W.
            let cmdW = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                windowNumber: window.windowNumber, context: nil,
                characters: "w", charactersIgnoringModifiers: "w", isARepeat: false, keyCode: 13)!
            let handled = NSApp.mainMenu?.performKeyEquivalent(with: cmdW) ?? false
            pump()
            check("Р20", "Cmd+W разобран меню и отдан обработчику", handled,
                  "performKeyEquivalent вернул false")
            check("Р20", "окно закрылось", !window.isVisible, "окно всё ещё на экране")
        }
        check("К8", "при закрытом окне отсчёт продолжает идти",
              wait(upTo: 3) { face() != beforeClose },
              "табло стоит на \(beforeClose)")
        // Меню `NSStatusItem` из дерева видов не достаётся — зовём тот же
        // метод делегата, который висит на пункте с итогом.
        _ = delegate.perform(NSSelectorFromString("showTimer"))
        pump()
        check("К8", "клик по «Summary» возвращает окно", window.isVisible, "окно не вернулось")
        check("К8", "вернулся тот же отсчёт, а не экран выбора", onScreen(clock))
        button("Stop")?.performClick(nil)
        pump()
        let hideItem = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "h" }
        check("К8", "Cmd+H на месте", hideItem != nil)
        check("К8", "Cmd+Q на месте",
              NSApp.mainMenu?.items.first?.submenu?.items.contains { $0.keyEquivalent == "q" } == true)

        print("\nМеню в строке меню")

        let statusMenu = delegate.statusMenu
        let titles = statusMenu?.items.map { $0.isSeparatorItem ? "———" : $0.title } ?? []
        check("М", "пункты меню ровно те, что просили, и в том же порядке",
              titles.count == 12 && titles[0].hasPrefix("Summary — ")
              && Array(titles.dropFirst()) == ["Mute", "———", "Size", "Theme",
                                               "———", "Guide", "Feedback",
                                               AppDelegate.updatesTitle(),
                                               "———", "Reset", "Quit"], "\(titles)")
        check("М", "пункта «Show Timer» больше нет", !titles.contains("Show Timer"))

        // Дороги наружу. Проверяется не то, что браузер открылся, а то, что
        // именно в него уедет: заголовок пункта обязан называть установленную
        // версию, а форма отзыва — принести версию, сборку, коммит и систему.
        // Спрашивать это у человека бесполезно — таких вещей про себя не знают,
        // а без них отзыв не привязать ни к коммиту, ни к машине.
        check("М", "версия читается из бандла, а не осталась заглушкой",
              Release.version != "dev", Release.version)
        check("М", "пункт обновлений называет установленную версию",
              AppDelegate.updatesTitle() == "Updates — " + Release.version,
              AppDelegate.updatesTitle())

        let feedback = URLComponents(string: Release.feedback)
        let sent = { (name: String) in feedback?.queryItems?.first { $0.name == name }?.value }
        check("М", "отзыв уходит в форму feedback.yml того самого репозитория",
              feedback?.host == "github.com"
              && feedback?.path == "/kvlllvd/Timato/issues/new"
              && sent("template") == "feedback.yml", Release.feedback)
        check("М", "в форму подставлены версия, сборка и коммит",
              sent("version") == Release.stamp
              && Release.stamp.hasPrefix(Release.version + " (")
              && Release.stamp.hasSuffix(")")
              && !Release.stamp.contains("unknown"), Release.stamp)
        check("М", "и система вместе со срезом, на котором приложение работает",
              sent("system")?.hasPrefix("macOS ") == true
              && (sent("system")?.hasSuffix("Apple Silicon") == true
                  || sent("system")?.hasSuffix("Intel") == true), sent("system") ?? "—")

        // Вид трекера — вложенным меню: наружу вынесен один заголовок, оба
        // варианта внутри, адаптивный первым.
        let modeSubmenu = statusMenu?.items.first { $0.title == "Size" }?.submenu
        check("М", "«Size» — выпадающий список из двух видов",
              modeSubmenu?.items.map(\.title) == ["Adaptive", "Full"],
              "\(modeSubmenu?.items.map(\.title) ?? [])")

        // Тема — таким же вложенным меню рядом: три пункта и галочка ровно на
        // выбранном, а не на том, во что он разрешился.
        let themeMenu = statusMenu?.items.first { $0.title == "Theme" }?.submenu
        check("М", "«Theme» — выпадающий список из трёх тем",
              themeMenu?.items.map(\.title) == ["Light", "Dark", "System"],
              "\(themeMenu?.items.map(\.title) ?? [])")
        check("М", "галочка стоит на выбранной теме",
              themeMenu?.items.filter { $0.state == .on }.map(\.title) == [Theme.current.title],
              "\(themeMenu?.items.filter { $0.state == .on }.map(\.title) ?? [])")

        // «Mute» — один пункт на два состояния: заголовок называет действие,
        // а не текущее положение звука.
        func muteTitle() -> String {
            if let statusMenu { statusMenu.delegate?.menuNeedsUpdate?(statusMenu) }
            return statusMenu?.items[1].title ?? "нет"
        }
        check("М", "по умолчанию звук включён", !Notifier.isMuted && muteTitle() == "Mute", muteTitle())
        _ = delegate.perform(NSSelectorFromString("toggleMute"))
        pump()
        check("М", "«Mute» глушит звонок", Notifier.isMuted)
        check("М", "и пункт становится «Unmute»", muteTitle() == "Unmute", muteTitle())
        _ = delegate.perform(NSSelectorFromString("toggleMute"))
        pump()
        check("М", "«Unmute» возвращает звук", !Notifier.isMuted && muteTitle() == "Mute", muteTitle())

        // Дальше по проверке отрезки заканчиваются полтора десятка раз подряд —
        // и каждый звонит. Что звонок звучит, уже проверено выше (Д1), слушать
        // его ещё пятнадцать раз незачем: до конца проверки звук выключен.
        Notifier.isMuted = true

        /// Заголовок пункта итога так, как его увидит пользователь: считается
        /// перед показом меню, а не при сборке.
        func summary() -> String {
            if let statusMenu { statusMenu.delegate?.menuNeedsUpdate?(statusMenu) }
            return statusMenu?.items.first?.title ?? "нет"
        }

        // Считаем от нуля: до этого места по ходу проверки уже набежали отрезки.
        _ = delegate.perform(NSSelectorFromString("resetProgress"))
        pump()
        check("М", "после сброса итог нулевой", summary() == "Summary — 0 h", summary())

        button("25 min")?.performClick(nil)
        pump()
        button("Finish now")?.performClick(nil)
        pump()
        check("М", "25 минут дают полчаса", summary() == "Summary — 0,5 h", summary())
        button("Stop")?.performClick(nil)
        pump()

        button("50 min")?.performClick(nil)
        pump()
        button("Finish now")?.performClick(nil)
        pump()
        check("М", "50 минут добавляют целый час", summary() == "Summary — 1,5 h", summary())
        button("Stop")?.performClick(nil)
        pump()

        // Итог не обнуляется вместе с рядом: ряд показывает круг, итог — сумму
        // за весь сеанс. Догоняем ряд до края и проверяем, что итог идёт дальше.
        for _ in 0..<3 {
            button("50 min")?.performClick(nil)
            pump()
            button("Finish now")?.performClick(nil)
            pump()
            button("Stop")?.performClick(nil)
            pump()
        }
        check("М", "за четвёртой черточкой ряд разросся до восьми",
              segments.filledHalves == 9 && Segments.shown(filledHalves: 9) == 8,
              "половинок \(segments.filledHalves)")
        check("М", "итог считает те же 4,5 часа", summary() == "Summary — 4,5 h", summary())

        for _ in 0..<4 {
            button("50 min")?.performClick(nil)
            pump()
            button("Finish now")?.performClick(nil)
            pump()
            button("Stop")?.performClick(nil)
            pump()
        }
        check("М", "ряд заполнен целиком", segments.filledHalves == Segments.capacity,
              "половинок \(segments.filledHalves)")
        check("М", "итог уже больше, чем показывает ряд", summary() == "Summary — 8,5 h", summary())

        // Следующий отрезок начинает ряд заново — а итог просто растёт дальше.
        button("50 min")?.performClick(nil)
        pump()
        button("Finish now")?.performClick(nil)
        pump()
        button("Stop")?.performClick(nil)
        pump()
        check("М", "ряд пошёл по второму кругу", segments.filledHalves == 2,
              "половинок \(segments.filledHalves)")
        check("М", "итог круг не заметил", summary() == "Summary — 9,5 h", summary())

        check("М", "целое число часов пишется без хвоста",
              AppDelegate.summaryTitle(halves: 6) == "Summary — 3 h",
              AppDelegate.summaryTitle(halves: 6))
        check("М", "половина штриха — это полчаса",
              AppDelegate.summaryTitle(halves: 5) == "Summary — 2,5 h",
              AppDelegate.summaryTitle(halves: 5))
        check("М", "верхней границы нет: набегает и двадцать часов",
              AppDelegate.summaryTitle(halves: 40) == "Summary — 20 h",
              AppDelegate.summaryTitle(halves: 40))

        // «Reset» в меню обнуляет и ряд, и итог.
        _ = delegate.perform(NSSelectorFromString("resetProgress"))
        pump()
        check("М", "«Reset» обнуляет итог совсем", summary() == "Summary — 0 h", summary())
        check("М", "«Reset» обнулил и ряд штрихов", segments.filledHalves == 0,
              "половинок \(segments.filledHalves)")

        print("\nВ · Adaptive и Full")

        let full = TimerWindowController.windowSize.width
        let compact = TimerWindowController.compactWidth
        /// Сколько ждать свёртывания: пауза плюс запас на саму анимацию.
        let foldWait = TimerWindowController.foldDelay + 2
        func modeItem(_ title: String) -> NSMenuItem? {
            statusMenu?.items.first { $0.title == "Size" }?.submenu?.items.first { $0.title == title }
        }
        /// Выбор пункта вида — тем же путём, каким его выбирает мышь.
        func choose(_ title: String) {
            guard let item = modeItem(title) else { return }
            _ = delegate.perform(NSSelectorFromString("chooseMode:"), with: item)
            pump(0.1)
        }
        func states() -> [String: NSControl.StateValue] {
            if let statusMenu { statusMenu.delegate?.menuNeedsUpdate?(statusMenu) }
            return ["Adaptive": modeItem("Adaptive")?.state ?? .mixed,
                    "Full": modeItem("Full")?.state ?? .mixed]
        }

        check("В", "ёмкий вид из макета — 136 в ширину", compact == 136, "\(compact)")
        check("В", "по умолчанию выбран Full",
              controller.viewMode == .alwaysFull
              && states() == ["Adaptive": .off, "Full": .on], "\(states())")

        // Full: курсора нет, отсчёт идёт — и всё равно полный вид,
        // сколько бы ни ждали.
        pointer = pointerAway
        button("25 min")?.performClick(nil)
        pump(TimerWindowController.foldDelay + 1)
        check("В", "в Full рабочий отсчёт без курсора не сворачивается",
              pillWidth() == full, "\(pillWidth())")
        button("Stop")?.performClick(nil)
        pump()

        choose("Adaptive")
        check("В", "выбор Adaptive переставляет галочку",
              controller.viewMode == .adaptive
              && states() == ["Adaptive": .on, "Full": .off], "\(states())")

        // Курсор на пилюле: отсчёт начинается в полном виде.
        pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        button("25 min")?.performClick(nil)
        pump()
        check("В", "под курсором отсчёт идёт полным видом", pillWidth() == full, "\(pillWidth())")

        // Курсор ушёл с окна — тем же путём, каким это делает `mouseExited`.
        pointer = pointerAway
        controller.syncWidth(animated: true)
        pump(min(2, TimerWindowController.foldDelay - 1))
        check("В", "сразу за курсором трекер не сворачивается — держит паузу",
              pillWidth() == full, "через 2 с ширина \(pillWidth())")
        check("В", "после паузы сворачивается до 136",
              wait(upTo: foldWait) { pillWidth() == compact }, "\(pillWidth())")
        check("В", "в ёмком виде остаются табло и полоса", onScreen(clock) && onScreen(bar))
        check("В", "высота при этом не меняется",
              window.frame.height - TimerWindowController.shadowMargin * 2
                  == TimerWindowController.windowSize.height, "\(window.frame.height)")

        // Курсор вернулся на пилюлю — полный вид возвращается сразу, без паузы.
        pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        controller.syncWidth(animated: true)
        pump(0.1)
        let midway = pillWidth()
        check("В", "под курсором возвращается полный вид",
              wait(upTo: 2) { pillWidth() == full }, "\(pillWidth())")
        check("В", "разворачивается плавно, а не прыжком", midway > compact && midway < full,
              "через 0,1 с ширина \(midway)")
        check("В", "и кнопки отсчёта снова на месте",
              ["Pause", "Finish now", "Stop"].allSatisfy { button($0).map(onScreen) == true })

        // Курсор ушёл и вернулся, не дождавшись конца паузы: свёртывание отменено.
        pointer = pointerAway
        controller.syncWidth(animated: true)
        pump(1)
        pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        controller.syncWidth(animated: true)
        pump(TimerWindowController.foldDelay)
        check("В", "вернувшийся до конца паузы курсор её отменяет",
              pillWidth() == full, "\(pillWidth())")

        pointer = pointerAway
        controller.syncWidth(animated: true)
        _ = wait(upTo: foldWait) { pillWidth() == compact }
        button("Pause")?.performClick(nil)
        check("В", "на паузе полный вид возвращается сразу: «Resume» нужен под рукой",
              wait(upTo: 2) { pillWidth() == full }, "\(pillWidth())")
        button("Resume")?.performClick(nil)
        check("В", "после продолжения снова сворачивается",
              wait(upTo: foldWait) { pillWidth() == compact }, "\(pillWidth())")

        button("Finish now")?.performClick(nil)
        pump(0.5)
        check("В", "на пятиминутке всегда полный вид",
              face() == "05:00" && wait(upTo: 2) { pillWidth() == full },
              "табло «\(face())», ширина \(pillWidth())")
        button("Stop")?.performClick(nil)
        pump(0.5)
        check("В", "на экране выбора всегда полный вид", pillWidth() == full, "\(pillWidth())")

        // Ловушка, ради которой это дописано: у пилюли, приклеенной к центру
        // кромки, ёмкий вид держался левым краем — и съезжал с центра ровно
        // на половину разницы между полной и ёмкой шириной.
        if let screen = window.screen ?? NSScreen.main {
            let inset = TimerWindowController.shadowMargin
            let saved = window.frame
            func pill() -> NSRect { window.frame.insetBy(dx: inset, dy: inset) }
            func centered() -> Bool { abs(pill().midX - screen.frame.midX) < 0.5 }

            // Почти к середине верхней кромки — остаток проходит прилипанием.
            window.setFrame(NSRect(origin: NSPoint(x: screen.frame.midX - window.frame.width / 2 + 12,
                                                   y: screen.frame.maxY - window.frame.height + 12),
                                   size: window.frame.size), display: true)
            pump(0.2)
            check("В", "полный вид приклеился к центру верхней кромки",
                  centered() && abs(pill().maxY - screen.frame.maxY) < 0.5,
                  "пилюля \(pill()), экран \(screen.frame)")

            pointer = pointerAway
            button("25 min")?.performClick(nil)
            controller.syncWidth(animated: true)
            check("В", "свернувшись, пилюля остаётся ровно по центру кромки",
                  wait(upTo: foldWait) { pillWidth() == compact } && centered(),
                  "ширина \(pillWidth()), пилюля \(pill()), экран \(screen.frame)")

            button("Stop")?.performClick(nil)
            check("В", "и развернувшись обратно — с того же центра",
                  wait(upTo: 2) { pillWidth() == full } && centered(),
                  "пилюля \(pill()), экран \(screen.frame)")

            window.setFrame(saved, display: true)
            pump(0.2)
        }

        // Курсор возвращаем на окно: дальше проверки про полный вид.
        pointer = NSPoint(x: window.frame.midX, y: window.frame.midY)
        controller.syncWidth(animated: false)
        pump()

        print("\nТ · трекер таскают за любое место")
        // Настоящую мышь проверка не двигает: окну подменяется курсор, а события
        // нажатия и переноса синтезируются и кладутся в очередь заранее — цикл
        // переноса разбирает их и живого человека не ждёт.
        if let snapping = window as? SnappingWindow, let screen = window.screen ?? NSScreen.main {
            // Подальше от краёв: у края окно упрётся или прилипнет, и сдвиг
            // будет не тот, что задан.
            window.setFrame(NSRect(origin: NSPoint(x: screen.frame.midX - window.frame.width / 2,
                                                   y: screen.frame.midY - window.frame.height / 2),
                                   size: window.frame.size), display: true)
            pump(0.2)

            func synthetic(_ type: NSEvent.EventType) -> NSEvent {
                NSEvent.mouseEvent(with: type, location: .zero, modifierFlags: [],
                                   timestamp: ProcessInfo.processInfo.systemUptime,
                                   windowNumber: window.windowNumber, context: nil,
                                   eventNumber: 0, clickCount: 1, pressure: 1)!
            }

            /// Тащит вид на 40 точек по обеим осям и возвращает, куда уехало окно.
            ///
            /// Курсор читается по одной точке за вызов: сначала место нажатия,
            /// потом отход за порог (это и есть «перенос, а не клик»), потом
            /// старт переноса и сам сдвиг. Дальше точка не меняется, поэтому
            /// сколько бы событий переноса ни разобрал цикл окна, уедет оно
            /// ровно на заданные 40 точек: сдвиг считается от старта переноса
            /// до последнего прочтения курсора.
            func drag(_ view: NSView) -> NSSize {
                let path = [NSPoint(x: 500, y: 500), NSPoint(x: 560, y: 500),
                            NSPoint(x: 560, y: 500), NSPoint(x: 600, y: 540)]
                var step = 0
                snapping.pointerLocation = {
                    defer { step += 1 }
                    return path[min(step, path.count - 1)]
                }
                let before = window.frame.origin
                // Событий переноса посылается с запасом. Ровно двух не хватало:
                // одно забирает порог, второе достаётся циклу переноса — и если
                // хоть одно по дороге терялось, окно не двигалось вовсе, а
                // проверка «не тащится» врала на исправном коде.
                for _ in 0..<4 { NSApp.postEvent(synthetic(.leftMouseDragged), atStart: false) }
                NSApp.postEvent(synthetic(.leftMouseUp), atStart: false)
                view.mouseDown(with: synthetic(.leftMouseDown))
                pump(0.2)
                snapping.pointerLocation = { NSEvent.mouseLocation }
                return NSSize(width: window.frame.origin.x - before.x,
                              height: window.frame.origin.y - before.y)
            }

            /// Нажатие без переноса: мышь стоит на месте, отпустили — это клик.
            func tap(_ view: NSView) {
                snapping.pointerLocation = { NSPoint(x: 500, y: 500) }
                NSApp.postEvent(synthetic(.leftMouseUp), atStart: false)
                view.mouseDown(with: synthetic(.leftMouseDown))
                pump(0.2)
                snapping.pointerLocation = { NSEvent.mouseLocation }
            }

            // Ряд черточек: раньше он забирал нажатие себе, и утащить окно
            // за него было нельзя.
            if let segmentsRow = descendants(SegmentsView.self, of: content).first {
                let moved = drag(segmentsRow)
                check("Т", "окно тащится за ряд черточек", moved == NSSize(width: 40, height: 40),
                      "уехало на \(moved)")
                check("Т", "перенос за ряд не выкатил кнопку сброса",
                      button("Reset progress").map(onScreen) != true)
            }

            // Кнопка выбора: перенос за неё не должен запускать отсчёт.
            if let preset = button("25 min") {
                let moved = drag(preset)
                check("Т", "окно тащится за кнопку выбора", moved == NSSize(width: 40, height: 40),
                      "уехало на \(moved)")
                check("Т", "перенос за кнопку не запустил отсчёт", !onScreen(clock))

                // А обычное нажатие на месте кнопку по-прежнему нажимает.
                tap(preset)
                check("Т", "нажатие без переноса запускает отсчёт", onScreen(clock),
                      "экран отсчёта не открылся")
            }

            // Кнопка отсчёта: перенос за «паузу» не должен ставить на паузу.
            if let pause = button("Pause") {
                let moved = drag(pause)
                check("Т", "окно тащится за кнопку отсчёта", moved == NSSize(width: 40, height: 40),
                      "уехало на \(moved)")
                check("Т", "перенос за «паузу» отсчёт не остановил", button("Pause") != nil,
                      "кнопка стала «Resume»")
            }
            button("Stop")?.performClick(nil)
            pump()

            // Табло тоже часть трекера: за него окно таскали и раньше — теперь
            // тем же порогом, что и всё остальное.
            let movedByClock = drag(clock)
            check("Т", "окно тащится за табло", movedByClock == NSSize(width: 40, height: 40),
                  "уехало на \(movedByClock)")
        }

        // Трекер тащат прямо из рабочего окна, не активируя его отдельным
        // кликом. Проверка не перечисляет классы, а щупает пилюлю сеткой точек:
        // нажатие достаётся тому виду, что лежит под курсором, и любая точка,
        // чей вид от первого нажатия отказался, — это место, за которое окно
        // с первого раза не сдвинуть. Так ловятся и служебные виды AppKit
        // внутри кнопок: их никто не писал, а под курсор они попадают.
        func firstMouseHoles() -> [String] {
            var holes: Set<String> = []
            for x in stride(from: content.frame.minX, to: content.frame.maxX, by: 3) {
                for y in stride(from: content.frame.minY, to: content.frame.maxY, by: 3) {
                    guard let hit = content.hitTest(NSPoint(x: x, y: y)),
                          !hit.acceptsFirstMouse(for: nil) else { continue }
                    holes.insert(String(describing: type(of: hit)))
                }
            }
            return holes.sorted()
        }

        let choiceHoles = firstMouseHoles()
        check("Т", "на экране выбора первый клик уже тащит, а не активирует",
              choiceHoles.isEmpty, "первое нажатие теряют: \(choiceHoles.joined(separator: ", "))")

        button("25 min")?.performClick(nil)
        pump()
        let clockHoles = firstMouseHoles()
        check("Т", "на отсчёте первый клик уже тащит, а не активирует",
              clockHoles.isEmpty, "первое нажатие теряют: \(clockHoles.joined(separator: ", "))")
        button("Stop")?.performClick(nil)
        pump()

        print("\nГ · окно «Guide»")
        // Гайд — единственное место, где кнопки названы словами: сами кнопки
        // отсчёта иконочные, и как они называются, человек узнаёт только здесь.
        // Поэтому расхождение имён ловится именно тут, а не глазами.
        // Имена кнопок сверяем на идущем отрезке: на стоящем таймере кнопка
        // паузы подписана «Resume», и сверка имён была бы про другое состояние.
        button("25 min")?.performClick(nil)
        pump()
        _ = delegate.perform(NSSelectorFromString("openGuide"))
        pump(0.5)
        func guideWindows() -> [NSWindow] { NSApp.windows.filter { $0.title == "Guide" } }
        check("Г", "окно «Guide» открылось", guideWindows().count == 1,
              "окон с таким заголовком: \(guideWindows().count)")

        if let guide = guideWindows().first, let guideContent = guide.contentView {
            guideContent.layoutSubtreeIfNeeded()
            let guideText = descendants(NSTextField.self, of: guideContent).map(\.stringValue)
            check("Г", "гайд не пустой", guideText.count >= 8, "подписей \(guideText.count)")
            check("Г", "ширина 500 из макета", guide.frame.width == 500, "\(guide.frame.width)")
            // Высота считается по содержимому: если раскладка развалилась,
            // окно схлопывается в полосу — и это надо ловить.
            check("Г", "высота выросла под содержимое", guide.frame.height > 300,
                  "\(guide.frame.height)")

            // Черта в списке дышит свободнее пунктов: по 8 точек сверх обычного
            // шага сверху и снизу. С общим шагом она стоит от соседей ровно так
            // же, как они друг от друга, и читается очередной строкой списка,
            // а не границей между «про окно» и «про отсчёт». Меряется по живой
            // раскладке, а не по константам: константу правят и в одном месте.
            if let divider = descendants(NSView.self, of: guideContent)
                .first(where: { $0.frame.height == 1 && $0.frame.width > 100 }),
               let list = divider.superview {
                // Полноширинные блоки списка сверху вниз. Лого уже, чем они,
                // и в ряд не попадает.
                let blocks = list.subviews
                    .filter { $0.frame.width == divider.frame.width }
                    .sorted { $0.frame.minY < $1.frame.minY }
                let gaps = zip(blocks, blocks.dropFirst()).map { $1.frame.minY - $0.frame.maxY }
                // Обычный шаг — самый частый и самый тесный: подпись и заметка
                // отбиты от списка сильнее, черта тоже.
                let step = gaps.min() ?? 0
                let index = blocks.firstIndex(of: divider) ?? 0
                let around = index > 0 && index < gaps.count ? [gaps[index - 1], gaps[index]] : []
                check("Г", "черта отбита от пунктов на 8 точек сверх обычного шага",
                      step == 16 && around == [24, 24], "шаг \(step), вокруг черты \(around)")
            }

            // Одно имя у продукта. Раньше здесь стоял «Timato», а бандл, DMG и
            // README звали приложение «Timer» — человек видел два разных имени.
            check("Г", "гайд зовёт продукт так же, как окно отсчёта",
                  guideText.contains(window.title), "в гайде \(guideText.prefix(2))")

            // Каждое имя кнопки из гайда обязано быть настоящей кнопкой окна.
            // Так поймано расхождение «Next» в гайде против «Finish now» в тултипе.
            for name in ["Finish now", "Pause", "Stop"] {
                check("Г", "«\(name)» из гайда — настоящая кнопка окна",
                      guideText.contains(name) && button(name) != nil,
                      "в гайде \(guideText.contains(name)), кнопка есть \(button(name) != nil)")
            }

            _ = delegate.perform(NSSelectorFromString("openGuide"))
            pump(0.4)
            check("Г", "повторное открытие не плодит второе окно", guideWindows().count == 1,
                  "окон \(guideWindows().count)")

            // Крестик закрывает только гайд. И открыть его снова после закрытия
            // должно быть безопасно: окно с `isReleasedWhenClosed = true` тут
            // оставило бы висячую ссылку в делегате.
            guide.performClose(nil)
            pump(0.4)
            check("Г", "крестик закрыл гайд", !guide.isVisible)
            check("Г", "окно отсчёта при этом на месте", window.isVisible)
            _ = delegate.perform(NSSelectorFromString("openGuide"))
            pump(0.5)
            check("Г", "после закрытия гайд открывается снова",
                  guideWindows().first?.isVisible == true)
            guideWindows().forEach { $0.close() }
            pump(0.3)
        }
        button("Stop")?.performClick(nil)
        pump()

        print("\nС · светлая тема")
        // Светлая тема — один вид на все состояния: фон в ней не меняется ни
        // на отдыхе, ни на паузе. Это и есть главное, что здесь проверяется.
        func trackColor() -> CGColor? {
            bar.layer?.sublayers?.first { !($0 is CAGradientLayer) }?.backgroundColor
        }
        Theme.current = .light
        pump()
        check("С", "фон экрана выбора светлый #F8F8F8", hex(backdrop()) == "#F8F8F8", hex(backdrop()))
        check("С", "ряд черточек перекрасился под тему",
              hex(segments.colors.done.cgColor) == "#1B1B1B"
              && hex(segments.colors.todo.cgColor) == "#EEEEEE",
              "\(hex(segments.colors.done.cgColor)) на \(hex(segments.colors.todo.cgColor))")
        check("С", "кнопки выбора светлые #EEEEEE",
              hex(button("25 min")?.layer?.backgroundColor) == "#EEEEEE",
              hex(button("25 min")?.layer?.backgroundColor))

        button("25 min")?.performClick(nil)
        pump()
        check("С", "фон отсчёта тот же светлый", hex(backdrop()) == "#F8F8F8", hex(backdrop()))
        check("С", "табло тёмное #1B1B1B", hex(clock.textColor.cgColor) == "#1B1B1B",
              hex(clock.textColor.cgColor))
        check("С", "трек полосы светлый #EEEEEE", hex(trackColor()) == "#EEEEEE", hex(trackColor()))
        check("С", "полоса остатка тёмная, без зелёного хвоста",
              Palette.day.fill.allSatisfy { hex($0.cgColor) == "#1B1B1B" }
              && Palette.day.fillStops == nil,
              "\(Palette.day.fill.map { hex($0.cgColor) })")
        check("С", "свечения в углу нет",
              Palette.look(kind: .focus, paused: false, skin: .light).glow == nil)

        // Пауза и отдых от темы не зависят: серый и зелёный там говорят о
        // состоянии, а не об оформлении, — светлая тема их не касается.
        button("Pause")?.performClick(nil)
        pump()
        check("С", "пауза серая, как и в тёмной теме", hex(backdrop()) == "#494949",
              hex(backdrop()))
        button("Resume")?.performClick(nil)
        pump()
        check("С", "после продолжения фон снова светлый", hex(backdrop()) == "#F8F8F8",
              hex(backdrop()))
        check("С", "отдых остаётся зелёным",
              Palette.look(kind: .rest, paused: false, skin: .light).backdrop
              == Palette.rest.backdrop
              && Palette.look(kind: .rest, paused: true, skin: .light).backdrop
              == Palette.restPaused.backdrop)
        button("Finish now")?.performClick(nil)
        pump(0.8)
        check("С", "и живьём: отдых в светлой теме зелёный",
              hex(backdrop()) == hex(Palette.rest.backdrop.cgColor), hex(backdrop()))
        button("Stop")?.performClick(nil)
        pump()
        check("С", "после отдыха вернулся светлый экран выбора",
              hex(backdrop()) == "#F8F8F8", hex(backdrop()))

        // Гайд светлеет вместе с трекером — и на уже открытом окне тоже:
        // контроллер гайда один на всё приложение и переживает смену темы.
        _ = delegate.perform(NSSelectorFromString("openGuide"))
        pump(0.5)
        func guideBackdrop() -> CGColor? {
            guideWindows().first?.contentView?.layer?.backgroundColor
        }
        check("С", "гайд в светлой теме светлый", hex(guideBackdrop()) == "#F8F8F8",
              hex(guideBackdrop()))
        // Пункт про свечение из гайда не пропадает — к нему приписана оговорка:
        // в светлой теме свечения нет, но про клик по табло человек узнать должен.
        let lightGuideText = guideWindows().first?.contentView.map {
            descendants(NSTextField.self, of: $0).map(\.stringValue)
        } ?? []
        check("С", "пункт про смену цвета в гайде остался",
              lightGuideText.contains { $0.hasPrefix("Cycles the corner glow") },
              "\(lightGuideText.filter { $0.contains("glow") })")
        check("С", "и помечен как только для тёмной темы",
              lightGuideText.contains { $0.contains("(Dark theme only.)") },
              "\(lightGuideText.filter { $0.contains("glow") })")

        // Тень: в светлой теме она плотнее и собрана теснее — иначе светлая
        // пилюля сливается со светлым столом под ней.
        func shadow() -> (Float, CGFloat, CGFloat) {
            let layer = content.layer
            return (layer?.shadowOpacity ?? 0, layer?.shadowRadius ?? 0,
                    -(layer?.shadowOffset.height ?? 0))
        }
        check("С", "тень светлой темы — лёгкая и небольшая", shadow() == (0.112, 5, 1),
              "\(shadow())")
        Theme.current = .dark
        pump(0.4)
        check("С", "открытый гайд перекрасился обратно", hex(guideBackdrop()) == "#000000",
              hex(guideBackdrop()))
        guideWindows().forEach { $0.close() }
        pump(0.3)
        check("С", "трекер вернулся в тёмную тему", hex(backdrop()) == "#000000", hex(backdrop()))
        check("С", "и тень вернулась к тёмной", shadow() == (0.18, 7, 2), "\(shadow())")

        print("\nК2 · уведомление доходит до Центра")
        // Боевой `Notifier.fire` отдаёт `withCompletionHandler: nil` — ошибку
        // доставки он глотает. Здесь тот же путь, но с обработчиком, иначе
        // «баннер не пришёл» выглядело бы как «всё хорошо».
        let center = UNUserNotificationCenter.current()
        var settings: UNNotificationSettings?
        center.getNotificationSettings { found in DispatchQueue.main.async { settings = found } }
        wait(upTo: 5) { settings != nil }
        if let settings {
            print("     authorizationStatus \(settings.authorizationStatus.rawValue), "
                  + "alertSetting \(settings.alertSetting.rawValue)")
        }
        check("К2", "bundle identity есть — без неё уведомления молчат",
              Bundle.main.bundleIdentifier == "com.dkovalev.timato",
              Bundle.main.bundleIdentifier ?? "нет")

        let banner = UNMutableNotificationContent()
        banner.title = "Time for a break"
        banner.body = "25 min done — \(Presets.restAfter(minutes: 25)) min break started"
        let id = "live-check-" + UUID().uuidString
        var addError: Error??
        center.add(UNNotificationRequest(identifier: id, content: banner, trigger: nil)) { error in
            DispatchQueue.main.async { addError = .some(error) }
        }
        wait(upTo: 5) { addError != nil }
        check("К2", "Центр принял уведомление без ошибки", (addError ?? nil) == nil,
              "\(String(describing: addError ?? nil))")

        var delivered: [UNNotification]?
        center.getDeliveredNotifications { found in DispatchQueue.main.async { delivered = found } }
        wait(upTo: 5) { delivered != nil }
        check("К2", "уведомление лежит в Центре уведомлений",
              delivered?.contains { $0.request.identifier == id } == true,
              "в Центре \(delivered?.count ?? -1) наших записей")
        // За собой убираем: регресс не должен оставлять баннеры пользователю.
        center.removeDeliveredNotifications(withIdentifiers: [id])
        pump(0.3)

        // Тема человека возвращается до итога: проверка не должна менять
        // настройки приложения, чем бы она сама ни закончилась.
        Theme.current = savedTheme

        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("ЗЕЛЁНО · \(passed) живых проверок")
            exit(0)
        }
        print("КРАСНО · \(passed) прошло, \(failures.count) упало:")
        failures.forEach { print("   • \($0)") }
        exit(1)
    }
}
