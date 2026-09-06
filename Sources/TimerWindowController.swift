import AppKit

// MARK: - Палитра

/// Цвет в записи макета: `0xRRGGBB` и, отдельно, прозрачность.
func designColor(_ value: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: alpha)
}

/// Все цвета одного состояния окна сразу: фон, текст, заливка кнопок, трек и полоса.
///
/// Состояний в макете ровно четыре — работа и отдых, каждое на ходу и на паузе —
/// и каждое взято целиком, а не собрано из общих цветов с поправками: на паузе
/// меняется не только фон, но и трек с полосой, и вывести одно из другого нечем.
struct Look {
    let backdrop: NSColor
    let text: NSColor
    /// Заливка кнопок — и цифровых пилюль, и круглых иконок.
    let control: NSColor
    /// Иконка, пока на кнопку не навели. Своя у каждого состояния: на чёрном
    /// это серый, на зелёном — белый вполсилы, иначе серое пятно на зелёном.
    let iconIdle: NSColor
    let track: NSColor
    /// Полоса остатка. В макете она белая почти на всю длину, а у рабочего
    /// отсчёта последняя седьмая часть уходит в зелёный — это и есть «сессия
    /// вот-вот кончится», видное краем глаза, без чтения цифр.
    let fill: [NSColor]
    /// Где стоят цвета `fill` по длине полосы, 0…1. Позиции считаются от всей
    /// полосы, а не от закрашенной части, — поэтому зелёный хвост и появляется
    /// только тогда, когда прогресс до него дошёл.
    var fillStops: [NSNumber]? = nil
    /// Кнопки нарисованы так, будто на них навели, даже когда курсора нет.
    /// Так помечена пауза: остановленное время видно и по кнопкам.
    var controlLifted: Bool = false
    /// Тёплое свечение из-за левого верхнего угла. Есть только у идущей работы:
    /// в макете круг лежит лишь в кадрах `Session`, ни на паузе, ни на отдыхе его нет.
    var glow: NSColor? = nil
}

enum Palette {
    /// Зелёный хвост полосы: последняя седьмая часть рабочего отсчёта.
    /// Взят пипеткой из макета вместе с точкой, где белое начинает в него уходить.
    static let finishing = designColor(0x00EF80)
    /// Доля полосы, с которой начинается переход в зелёный: до неё полоса белая.
    static let finishingStop: CGFloat = 0.851

    /// Белое и зелёный хвост одним набором: цвета и их места по длине полосы.
    ///
    /// Переход разложен на промежуточные точки не для красоты. `CAGradientLayer`
    /// смешивает соседние цвета не в том пространстве, в каком считает макет:
    /// на двух точках (белая и зелёная) хвост выходил заметно бледнее — у самого
    /// конца в красном канале 79 против 8 в макете, и зелёный читался как мятный.
    /// Здесь промежуточные цвета считаются так же, как их считает макет, а слою
    /// остаётся смешивать уже почти соседние — и ошибка становится незаметной.
    static let finishingRamp: (colors: [NSColor], stops: [NSNumber]) = {
        let steps = 8
        var colors: [NSColor] = [.white]
        var stops: [NSNumber] = [0]
        let tail = 1 - finishingStop
        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            colors.append(NSColor(srgbRed: 1 + (0 - 1) * t,
                                  green: 1 + (239.0 / 255 - 1) * t,
                                  blue: 1 + (128.0 / 255 - 1) * t,
                                  alpha: 1))
            stops.append(NSNumber(value: Double(finishingStop + tail * t)))
        }
        return (colors, stops)
    }()

    /// Работа, отсчёт идёт: чёрное окно, белая полоса с зелёным хвостом к концу.
    static let focus = Look(backdrop: designColor(0x000000), text: designColor(0xEBEBEB),
                            control: designColor(0x1D1D1D), iconIdle: designColor(0x4C4C4C),
                            track: designColor(0x282828),
                            fill: finishingRamp.colors,
                            fillStops: finishingRamp.stops,
                            glow: designColor(0xF20900))
    /// Работа на паузе: серым становится всё окно, а не одна иконка, — что время
    /// не идёт, видно от края до края и без чтения кнопок.
    static let focusPaused = Look(backdrop: designColor(0x494949), text: designColor(0xEBEBEB),
                                  control: designColor(0x1D1D1D), iconIdle: designColor(0x4C4C4C),
                                  track: designColor(0x565656),
                                  fill: finishingRamp.colors,
                                  fillStops: finishingRamp.stops,
                                  controlLifted: true)
    /// Отдых: зелёное окно, белая полоса — на зелёном белое и есть самое заметное.
    static let rest = Look(backdrop: designColor(0x00BB61), text: .white,
                           control: designColor(0xFFFFFF, 0.3), iconIdle: designColor(0xFFFFFF, 0.5),
                           track: designColor(0xF5F5F5, 0.19),
                           fill: [.white, .white])
    /// Отдых на паузе: тот же зелёный, только тёмный.
    static let restPaused = Look(backdrop: designColor(0x006735), text: .white,
                                 control: designColor(0xFFFFFF, 0.3), iconIdle: designColor(0xFFFFFF, 0.5),
                                 track: designColor(0xF5F5F5, 0.19),
                                 fill: [.white, .white],
                                 controlLifted: true)

    /// Ряд черточек на экране выбора: закрашенное — белым, остальное — цветом трека.
    static let segmentDone = NSColor.white
    static let segmentTodo = designColor(0x282828)

    /// Осветление кнопки под курсором — и та же метка паузы.
    ///
    /// Белый непрозрачный, а не полупрозрачный: `blended(withFraction:of:)`
    /// смешивает и альфу, и с полупрозрачной подмешкой кнопка сама становилась
    /// полупрозрачной. Тогда её цвет зависел от фона под ней — на сером фоне
    /// паузы та же кнопка выходила светлее, чем на чёрном под курсором.
    static let hoverLift = NSColor.white
    /// Насколько кнопка светлеет. Подобрано так, чтобы на чёрном фоне выйти
    /// в тот же #555555, каким осветление читалось до перехода на непрозрачный белый.
    static let hoverLiftFraction: CGFloat = 0.25

    /// Цвета свечения, которые перебирает клик по табло. Красный — тот самый,
    /// что стоит в макете; остальные три взяты из палитры приложения (зелёный —
    /// цвет отдыха), в макете их кадров нет.
    static func glow(_ accent: Accent) -> NSColor {
        switch accent {
        case .red:    return designColor(0xF20900)
        case .green:  return designColor(0x00BB61)
        case .purple: return designColor(0x8B2FE8)
        case .blue:   return designColor(0x0A6CF2)
        }
    }

    static func look(kind: Kind, paused: Bool) -> Look {
        switch (kind, paused) {
        case (.focus, false): return focus
        case (.focus, true):  return focusPaused
        case (.rest, false):  return rest
        case (.rest, true):   return restPaused
        }
    }
}

// MARK: - Кнопка

/// Кнопка из макета: пилюля на своей заливке, без системной рамки.
/// Одна и та же и для цифр на экране выбора, и для круглых иконок на отсчёте —
/// отличаются только размером и содержимым.
final class PillButton: NSButton {

    /// Скругление кнопок из макета — одно на все: и на пилюли выбора,
    /// и на квадратные кнопки отсчёта.
    static let cornerRadius: CGFloat = 4

    /// Высота ряда кнопок на экране выбора из макета: и пилюли 25/55,
    /// и кнопка сброса, которая встаёт на их место.
    static let rowHeight: CGFloat = 40

    private var look: Look = Palette.focus
    private var hovered = false
    private var trackingAreaRef: NSTrackingArea?
    /// Что нарисовано на кнопке. Хранится отдельно от вида, потому что при
    /// перекраске окна кнопку надо собрать заново — в новых цветах.
    private enum Content {
        /// Число минут с подписью «min»: экран выбора.
        case minutes(Int)
        /// Иконка из SF Symbols: кнопки отсчёта.
        case symbol(String, label: String)
    }
    private var content: Content = .symbol("pause.fill", label: "Pause")

    private init(size: NSSize, target: AnyObject?, action: Selector?) {
        super.init(frame: .zero)
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        heightAnchor.constraint(equalToConstant: size.height).isActive = true
        if size.width > 0 {
            let width = widthAnchor.constraint(equalToConstant: size.width)
            width.isActive = true
            widthConstraint = width
        }
        title = ""
    }

    /// Ширина кнопки, если она задана. Меняется на ходу: «стоп» на отдыхе
    /// растягивается на место трёх кнопок работы.
    private var widthConstraint: NSLayoutConstraint?

    func setWidth(_ width: CGFloat) {
        widthConstraint?.constant = width
    }

    /// Кнопка выбора: 40 в высоту из макета, «25» крупно и «min» мелко сверху.
    convenience init(minutes: Int, target: AnyObject?, action: Selector?) {
        self.init(size: NSSize(width: 0, height: Self.rowHeight), target: target, action: action)
        content = .minutes(minutes)
        tag = minutes
        setAccessibilityLabel("\(minutes) min")
        redraw()
    }

    /// Кнопка отсчёта: круг 40×40 с иконкой 24. Подписи нет — место в окне
    /// дороже слова, но `label` остаётся именем для подсказки и голосового доступа.
    convenience init(symbol: String, label: String, target: AnyObject?, action: Selector?) {
        self.init(size: NSSize(width: 40, height: 40), target: target, action: action)
        imagePosition = .imageOnly
        setSymbol(symbol, label: label)
    }

    /// Кнопка сброса: та же иконка, но во всю ширину ряда — в макете она
    /// занимает всё место кнопок выбора, той же высоты 40.
    convenience init(wideSymbol symbol: String, label: String, target: AnyObject?, action: Selector?) {
        self.init(size: NSSize(width: 0, height: Self.rowHeight), target: target, action: action)
        imagePosition = .imageOnly
        setSymbol(symbol, label: label)
    }

    /// Меняет иконку на ходу — пауза и продолжение это одна и та же кнопка.
    func setSymbol(_ symbol: String, label: String) {
        content = .symbol(symbol, label: label)
        toolTip = label
        setAccessibilityLabel(label)
        redraw()
    }

    /// Перекрашивает кнопку под состояние окна.
    func apply(look: Look) {
        self.look = look
        redraw()
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Без обнуления кнопка занимает на пару точек больше рамки, чем задано
    /// констрейнтом: Auto Layout меряет прямоугольник выравнивания, а у кнопки
    /// он у́же собственной рамки. Круг 40×40 из-за этого выходил овалом 42×42.
    override var alignmentRectInsets: NSEdgeInsets { NSEdgeInsetsZero }

    override func layout() {
        super.layout()
        layer?.cornerRadius = Self.cornerRadius
    }

    private func redraw() {
        // На паузе кнопки стоят в том же осветлении, что и под курсором:
        // так `controlLifted` из палитры и задан.
        let background = hovered || look.controlLifted
            ? look.control.blended(withFraction: Palette.hoverLiftFraction,
                                   of: Palette.hoverLift) ?? look.control
            : look.control
        layer?.backgroundColor = background.cgColor

        switch content {
        case .minutes(let minutes):
            attributedTitle = Self.minutesTitle(minutes, color: look.text)
        case .symbol(let symbol, let label):
            // 24 — размер иконки в макете; вес подобран под залитые player-иконки.
            let configuration = NSImage.SymbolConfiguration(pointSize: 15, weight: .bold)
            image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
                .withSymbolConfiguration(configuration)
            // Иконка загорается ровно тогда, когда курсор на самой кнопке.
            contentTintColor = hovered ? look.text : look.iconIdle
        }
    }

    /// «25» и «min»: число 24-м кеглем, подпись 12-м и поднята к верху числа —
    /// в макете они выровнены по верху, а не по базовой линии.
    private static func minutesTitle(_ minutes: Int, color: NSColor) -> NSAttributedString {
        let title = NSMutableAttributedString(string: "\(minutes)", attributes: [
            .font: DisplayFont.of(size: 24),
            .foregroundColor: color,
            // Число опущено на 2 пункта: кнопка центрирует строку целиком, а в
            // макете число стоит ниже этой середины, «min» — выше.
            .baselineOffset: -3,
        ])
        // Отступ до «min» — своим прогоном с кернингом, а не пробелом на глаз:
        // в макете между числом и подписью ровно 8 пунктов, у одного пробела
        // этого шрифта выходило 6.
        title.append(NSAttributedString(string: " ", attributes: [
            .font: DisplayFont.of(size: 12),
            .kern: 2,
        ]))
        title.append(NSAttributedString(string: "min", attributes: [
            .font: DisplayFont.of(size: 12),
            .foregroundColor: color,
            .baselineOffset: 9,
        ]))
        return title
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingAreaRef { removeTrackingArea(trackingAreaRef) }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways], owner: self)
        addTrackingArea(area)
        trackingAreaRef = area
    }

    override func mouseEntered(with event: NSEvent) { hovered = true; redraw() }
    override func mouseExited(with event: NSEvent) { hovered = false; redraw() }

    /// Трекер таскают за любое место, и кнопки не исключение: увели мышь —
    /// это перенос окна, отпустили на месте — обычное нажатие.
    ///
    /// Обычный цикл нажатия у `NSButton` свой и события отпускания нам уже не
    /// оставляет, поэтому действие после клика шлём сами.
    override func mouseDown(with event: NSEvent) {
        guard let snapping = window as? SnappingWindow else { return super.mouseDown(with: event) }
        guard !snapping.dragIfMoved(after: event) else { return }
        performClick(nil)
    }
}

// MARK: - Полоса прогресса

/// Полоса прошедшего времени: трек и градиентная заливка.
///
/// Ширина заливки не перерисовывается по тику — она анимируется одним линейным
/// переходом до конца отсчёта. Поэтому движение плавное на любой частоте кадров,
/// а процессор при этом ничего не считает.
final class ProgressBar: NSView {

    private let track = CALayer()
    private let fill = CAGradientLayer()
    /// Маска заливки: её ширина и есть прогресс.
    private let reveal = CALayer()

    /// Имя анимации — по нему её же и снимаем на паузе.
    private static let animationKey = "progress"

    /// Цвета трека и заливки берутся из состояния окна целиком.
    private var look: Look = Palette.focus

    /// Где полоса стоит, когда никуда не едет.
    private var frozenFraction: CGFloat = 0
    /// Едущая полоса: откуда поехала, когда и сколько ехать. Анимация задана
    /// в точках, а ширина окна меняется на ходу — по этим трём числам полосу
    /// и пересобирают на новой ширине, не сбивая ход.
    private var run: (from: CGFloat, start: CFTimeInterval, duration: TimeInterval)?
    /// Ширина, под которую посчитана нынешняя анимация.
    private var laidOutWidth: CGFloat = 0

    /// Перекрашивает полосу под состояние окна, не сбивая ход анимации.
    func apply(look: Look) {
        self.look = look
        applyColors()
    }

    override var isFlipped: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.addSublayer(track)
        layer?.addSublayer(fill)
        fill.startPoint = CGPoint(x: 0, y: 0.5)
        fill.endPoint = CGPoint(x: 1, y: 0.5)
        fill.mask = reveal
        reveal.backgroundColor = NSColor.black.cgColor
        reveal.anchorPoint = CGPoint(x: 0, y: 0)
        applyColors()
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override func layout() {
        super.layout()
        // Без отключения неявных анимаций слои тянутся за новой шириной сами
        // и отстают от окна на каждом кадре свёртывания.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        let radius = bounds.height / 2
        track.frame = bounds
        track.cornerRadius = radius
        fill.frame = bounds
        fill.cornerRadius = radius
        reveal.cornerRadius = radius
        if bounds.width == laidOutWidth {
            reveal.frame = CGRect(x: 0, y: 0, width: currentWidth, height: bounds.height)
        } else {
            // Ширина сменилась — окно свернулось или развернулось. Анимация
            // задана в точках, и на новой ширине полоса ехала бы к старому
            // концу, мимо края окна: пересобираем её с той же доли.
            laidOutWidth = bounds.width
            if let run {
                let passed = CACurrentMediaTime() - run.start
                show(fraction: fractionNow, animatingFor: max(0, run.duration - passed))
            } else {
                freeze(fraction: frozenFraction)
            }
        }
        CATransaction.commit()
    }

    /// Какая доля залита прямо сейчас. Считается по часам, а не по слою:
    /// в момент смены ширины презентационный слой мерит уже от новой рамки.
    private var fractionNow: CGFloat {
        guard let run, run.duration > 0 else { return frozenFraction }
        let passed = min(1, max(0, (CACurrentMediaTime() - run.start) / run.duration))
        return run.from + (1 - run.from) * CGFloat(passed)
    }

    private func applyColors() {
        track.backgroundColor = look.track.cgColor
        fill.colors = look.fill.map(\.cgColor)
        fill.locations = look.fillStops
    }

    /// Ширина, которая видна прямо сейчас: во время анимации — кадр из
    /// презентационного слоя, иначе — то, что задано моделью.
    private var currentWidth: CGFloat {
        (reveal.presentation() ?? reveal).bounds.width
    }

    /// Ставит полосу в текущее положение и, если отсчёт идёт, запускает
    /// линейную анимацию до конца — ровно на оставшееся время.
    func show(fraction: CGFloat, animatingFor remaining: TimeInterval) {
        let clamped = max(0, min(1, fraction))
        reveal.removeAnimation(forKey: Self.animationKey)
        frozenFraction = clamped
        run = remaining > 0 ? (from: clamped, start: CACurrentMediaTime(), duration: remaining) : nil

        let from = CGRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
        reveal.frame = from

        guard remaining > 0 else { return }
        let animation = CABasicAnimation(keyPath: "bounds.size.width")
        animation.fromValue = from.width
        animation.toValue = bounds.width
        animation.duration = remaining
        // Линейное время: полоса обязана идти ровно так же, как идут цифры.
        animation.timingFunction = CAMediaTimingFunction(name: .linear)
        animation.fillMode = .forwards
        animation.isRemovedOnCompletion = false
        reveal.add(animation, forKey: Self.animationKey)
    }

    /// Замирает там, где полоса оказалась: пауза, сброс, конец отсчёта.
    func freeze(fraction: CGFloat) {
        reveal.removeAnimation(forKey: Self.animationKey)
        let clamped = max(0, min(1, fraction))
        run = nil
        frozenFraction = clamped
        reveal.frame = CGRect(x: 0, y: 0, width: bounds.width * clamped, height: bounds.height)
    }
}

// MARK: - Черточки

/// Ряд черточек под цифрами: четыре штуки, растянутые на всю ширину окна.
///
/// Считает не отрезки, а половинки: 25 минут закрашивают половину черточки,
/// 55 — целую. Клик по ряду переключает кнопку сброса на месте кнопок выбора:
/// ряд сам по себе ничего не сбрасывает, сброс — дело кнопки.
final class SegmentsView: NSView {
    /// Зазор между черточками из макета. Сама ширина черточки не задана —
    /// она равна остатку, поделённому на четыре.
    private let gap: CGFloat = 4
    private let thickness: CGFloat = 4

    /// Сколько половинок закрашено, 0…`Segments.capacity`.
    var filledHalves = 0 {
        didSet { needsDisplay = true }
    }

    /// Клик по ряду. Переключает кнопку сброса: показать её или убрать —
    /// решает окно, ряд только сообщает о нажатии.
    var onClick: (() -> Void)?

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: thickness)
    }

    /// Прямоугольник черточки с номером `index` в текущей ширине вида.
    private func rect(at index: Int) -> NSRect {
        let count = CGFloat(Presets.segments)
        let width = (bounds.width - gap * (count - 1)) / count
        return NSRect(x: CGFloat(index) * (width + gap), y: 0,
                      width: width, height: bounds.height)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = bounds.height / 2
        for index in 0..<Presets.segments {
            let slot = rect(at: index)
            let shape = NSBezierPath(roundedRect: slot, xRadius: radius, yRadius: radius)
            Palette.segmentTodo.setFill()
            shape.fill()

            let fraction = segmentFill(index: index, filledHalves: filledHalves)
            guard fraction > 0 else { continue }
            // Закрашенная часть — своя пилюля со скруглением на оба конца, как
            // в макете: у половины черточки правый край такой же круглый, как левый.
            let done = NSRect(x: slot.minX, y: slot.minY,
                              width: slot.width * fraction, height: slot.height)
            Palette.segmentDone.setFill()
            NSBezierPath(roundedRect: done, xRadius: radius, yRadius: radius).fill()
        }
    }

    // MARK: Клик

    /// Ряд высотой 4 точки — слишком тонкая цель для мыши, поэтому нажатия
    /// ловятся и рядом с черточками, а не строго на них.
    private static let clickSlop: CGFloat = 8

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Проверка на скрытость — своя: её делает стандартный `hitTest`, а он
        // здесь переопределён. Без неё спрятанный на отсчёте ряд всё равно
        // забирал нажатия, и клик по полосе остатка попадал в него: полоса
        // лежит ровно там же, в четырёх точках от низа окна.
        guard !isHidden else { return nil }
        let reachable = frame.insetBy(dx: 0, dy: -Self.clickSlop)
        return reachable.contains(point) ? self : nil
    }

    /// `super` не зовём: иначе нажатие уйдёт окну и вместо переключения
    /// сразу началось бы перетаскивание. Но и ряд черточек — часть трекера,
    /// за которую его можно утащить: перенос отделяется от клика тем же
    /// порогом, что и на кнопках.
    override func mouseDown(with event: NSEvent) {
        if let snapping = window as? SnappingWindow, snapping.dragIfMoved(after: event) { return }
        onClick?()
    }

    override func accessibilityLabel() -> String? { "Progress" }
    override func accessibilityRole() -> NSAccessibility.Role? { .button }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityPerformPress() -> Bool { onClick?(); return true }
}

// MARK: - Табло из цифр

/// Один разряд табло: окошко, в котором глиф съезжает снизу вверх.
///
/// Старый глиф уезжает вверх и наружу, новый в тот же миг въезжает снизу —
/// как створка на табло в аэропорту. Каждый разряд живёт сам по себе, поэтому
/// в `12:00 → 11:59` двигаются только те цифры, которые правда изменились.
final class DigitSlot: NSView {

    /// Длительность съезда. Дольше — и в конце минуты цифры не успевают
    /// доехать до следующей секунды.
    private static let duration: CFTimeInterval = 0.22

    private let font: NSFont
    private var color: NSColor
    private var glyph: CATextLayer
    private(set) var character: Character

    init(character: Character, font: NSFont, color: NSColor) {
        self.character = character
        self.font = font
        self.color = color
        self.glyph = CATextLayer()
        super.init(frame: .zero)
        wantsLayer = true
        // Окошко разряда: без обрезки уезжающий глиф был бы виден поверх соседей.
        layer?.masksToBounds = true
        configure(glyph, with: character)
        layer?.addSublayer(glyph)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override func layout() {
        super.layout()
        // Только текущий глиф: уезжающий живёт своей анимацией и уже стоит
        // в конечном положении над окошком — возвращать его сюда нельзя.
        glyph.frame = bounds
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let scale = window?.backingScaleFactor ?? 2
        for sublayer in layer?.sublayers ?? [] { sublayer.contentsScale = scale }
    }

    func setColor(_ new: NSColor) {
        color = new
        configure(glyph, with: character)
    }

    /// Ставит новый символ. Тот же символ игнорируется — иначе табло дёргалось
    /// бы каждую перерисовку.
    func show(_ next: Character, animated: Bool) {
        guard next != character else { return }
        character = next

        guard animated, bounds.height > 0 else {
            configure(glyph, with: next)
            return
        }

        let incoming = CATextLayer()
        configure(incoming, with: next)
        // Ниже окошка: система координат слоя не перевёрнута, вниз — это минус.
        incoming.frame = bounds.offsetBy(dx: 0, dy: -bounds.height)
        layer?.addSublayer(incoming)

        let outgoing = glyph
        glyph = incoming

        let shift = bounds.height
        CATransaction.begin()
        CATransaction.setCompletionBlock { outgoing.removeFromSuperlayer() }
        slide(incoming, by: shift)
        slide(outgoing, by: shift, fadingOut: true)
        CATransaction.commit()
    }

    /// Сдвигает слой вверх на `shift`, оставляя модель в конечном положении:
    /// анимация только показывает путь, итог задан кадром слоя.
    ///
    /// `fadingOut` — уходящий глиф вдобавок тает к краю окошка: обрезка по
    /// границе рубит цифру пополам, а растворение убирает этот срез и делает
    /// съезд плавным.
    /// Кривая съезда: быстрый разгон и мягкая остановка — так створка
    /// «падает» на место. Затухание идёт по ней же, иначе прозрачность
    /// отстаёт от движения (см. `slide`).
    private static let travel = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.2, 1)

    private func slide(_ layer: CATextLayer, by shift: CGFloat, fadingOut: Bool = false) {
        if fadingOut {
            // Как и со сдвигом: итог задаётся моделью, анимация только
            // показывает путь. С прозрачностью, оставленной в модели единицей,
            // затухание не появлялось совсем.
            layer.opacity = 0
            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = 1
            fade.toValue = 0
            fade.duration = Self.duration
            // Та же кривая, что и у сдвига. С линейной прозрачность отставала
            // от движения: цифра успевала улететь за край окошка за первые
            // 50 мс, оставаясь при этом почти непрозрачной, — всё затухание
            // происходило уже вне видимой части, а в окошке в этот миг обе
            // цифры, уходящая и приходящая, накладывались друг на друга.
            fade.timingFunction = Self.travel
            layer.add(fade, forKey: "fade")
        }
        let from = layer.position.y
        layer.frame = layer.frame.offsetBy(dx: 0, dy: shift)
        let move = CABasicAnimation(keyPath: "position.y")
        move.fromValue = from
        move.toValue = layer.position.y
        move.duration = Self.duration
        move.timingFunction = Self.travel
        layer.add(move, forKey: "slide")
    }

    private func configure(_ layer: CATextLayer, with character: Character) {
        layer.string = NSAttributedString(string: String(character), attributes: [
            .font: font,
            .foregroundColor: color,
        ])
        layer.alignmentMode = .center
        layer.contentsScale = window?.backingScaleFactor ?? 2
        layer.frame = bounds
    }
}

/// Табло времени: строка `MM:SS`, где каждый разряд — своё окошко со съездом.
///
/// Заменяет обычную надпись именно потому, что съезжать должны отдельные
/// цифры: у `NSTextField` меняется вся строка целиком, и анимировать разряды
/// по одному в нём нечем.
final class FlipClockView: NSView {

    private let font = DisplayFont.of(size: 36)
    private var slots: [DigitSlot] = []
    private var text = ""

    var textColor: NSColor = Palette.focus.text {
        didSet { for slot in slots { slot.setColor(textColor) } }
    }

    override var isFlipped: Bool { true }

    /// Ширина разряда: у моноширинных цифр она одна на все десять, у двоеточия
    /// своя — иначе между минутами и секундами зияет цифровая пустота.
    private func width(of character: Character) -> CGFloat {
        let string = character.isNumber ? "0" : String(character)
        return ceil(NSAttributedString(string: string, attributes: [.font: font]).size().width)
    }

    private var lineHeight: CGFloat { ceil(font.ascender - font.descender) }

    override var intrinsicContentSize: NSSize {
        NSSize(width: text.reduce(0) { $0 + width(of: $1) }, height: lineHeight)
    }

    override func layout() {
        super.layout()
        var x: CGFloat = 0
        for slot in slots {
            let slotWidth = width(of: slot.character)
            slot.frame = NSRect(x: x, y: 0, width: slotWidth, height: bounds.height)
            x += slotWidth
        }
    }

    /// Клик по табло. Ставится только на идущем отсчёте — на других экранах
    /// табло не показано вообще.
    var onClick: (() -> Void)?

    /// Клик по табло перебирает цвет свечения — но тащить окно за цифры
    /// по-прежнему можно: перенос отделяется от клика тем же порогом, что
    /// и на кнопках с рядом черточек.
    override func mouseDown(with event: NSEvent) {
        guard let onClick, let snapping = window as? SnappingWindow else {
            return super.mouseDown(with: event)
        }
        guard !snapping.dragIfMoved(after: event) else { return }
        onClick()
    }

    /// Показывает время. Пока длина строки не меняется, разряды те же самые и
    /// анимируются; на смене формата (`59:59 → 1:00:00`) табло собирается заново.
    func setText(_ new: String, animated: Bool) {
        guard new != text else { return }
        let sameShape = new.count == text.count
        text = new

        if !sameShape {
            for slot in slots { slot.removeFromSuperview() }
            slots = new.map { character in
                let slot = DigitSlot(character: character, font: font, color: textColor)
                addSubview(slot)
                return slot
            }
            invalidateIntrinsicContentSize()
            needsLayout = true
            return
        }

        for (slot, character) in zip(slots, new) { slot.show(character, animated: animated) }
    }
}

// MARK: - Корневой вид

/// Радиус скругления по каждому углу отдельно — у угла, приклеенного к углу
/// экрана, радиус обнуляется, чтобы окно ровно заполняло его, без зазора.
typealias CornerRadii = (topLeft: CGFloat, topRight: CGFloat, bottomRight: CGFloat, bottomLeft: CGFloat)

/// Прямоугольник с независимым радиусом на каждом углу. Точки углов — те же,
/// что и в `ScreenCorner`: (minX, minY) это верхний левый угол в системе
/// координат вида, перевёрнутого сверху вниз (`isFlipped`).
///
/// Общая для `RootView` (заливка) и тени окна (`shadowPath`) — форма обеих
/// обязана совпадать один в один, иначе тень будет выглядывать из-под угла,
/// когда он обнулён прилипанием к углу экрана.
///
/// `CGPath`, а не `NSBezierPath`: `CALayer.shadowPath` берёт только его, а
/// `NSBezierPath.cgPath` появился лишь в macOS 14 — раньше проекта не собрать.
func roundedPath(in rect: NSRect, radii: CornerRadii) -> CGPath {
    let topLeft = CGPoint(x: rect.minX, y: rect.minY)
    let topRight = CGPoint(x: rect.maxX, y: rect.minY)
    let bottomRight = CGPoint(x: rect.maxX, y: rect.maxY)
    let bottomLeft = CGPoint(x: rect.minX, y: rect.maxY)

    let path = CGMutablePath()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY + radii.topLeft))
    path.addArc(tangent1End: topLeft, tangent2End: topRight, radius: radii.topLeft)
    path.addArc(tangent1End: topRight, tangent2End: bottomRight, radius: radii.topRight)
    path.addArc(tangent1End: bottomRight, tangent2End: bottomLeft, radius: radii.bottomRight)
    path.addArc(tangent1End: bottomLeft, tangent2End: topLeft, radius: radii.bottomLeft)
    path.closeSubpath()
    return path
}

/// Подложка окна со скруглением. Цвет заливки меняется на ходу и с анимацией:
/// по окончании рабочего отрезка всё окно перекрашивается в зелёный.
///
/// Заливка живёт в `CAShapeLayer`, а не в `draw(_:)`: перекрасить нарисованное
/// вручную можно только скачком, а слой сам интерполирует цвет между кадрами.
final class RootView: NSView {

    private let backdrop = CAShapeLayer()
    /// Свечение из макета: круг радиусом 181 с центром выше левого верхнего
    /// угла пилюли — от красного в середине к прозрачному по краю. Лежит поверх
    /// заливки и обрезан её же формой, поэтому за скругление не выходит.
    private let glow = CAGradientLayer()
    /// Размер и место круга — прямо из макета: 362×362 в точке (−154, −233)
    /// от левого верхнего угла окна.
    private static let glowFrame = CGRect(x: -154, y: -233, width: 362, height: 362)
    /// Белая вспышка поверх заливки: короткий блик в момент смены фона, чтобы
    /// переход читался как событие, а не как медленное угасание цвета.
    private let flash = CALayer()

    override var isFlipped: Bool { true }

    var cornerRadii: CornerRadii = (pillCornerRadius, pillCornerRadius,
                                    pillCornerRadius, pillCornerRadius) {
        didSet { updatePath() }
    }

    /// Курсор вошёл на пилюлю или ушёл с неё. Само событие ничего не решает:
    /// окно по нему только пересчитывает, каким ему сейчас быть.
    var onHoverChange: (() -> Void)?
    private var hoverArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        // Обрезка по своим границам: в ёмком виде кнопки отсчёта остаются на
        // местах из макета и уезжают за правый край окна — без обрезки от них
        // торчала бы полоска рядом с пилюлей.
        layer?.masksToBounds = true
        backdrop.fillColor = Palette.focus.backdrop.cgColor
        glow.type = .radial
        // Круг, а не эллипс: конец градиента в углу квадратной рамки слоя.
        glow.startPoint = CGPoint(x: 0.5, y: 0.5)
        glow.endPoint = CGPoint(x: 1, y: 1)
        glow.opacity = 0
        flash.backgroundColor = NSColor.white.cgColor
        flash.opacity = 0
        layer?.addSublayer(backdrop)
        layer?.addSublayer(glow)
        layer?.addSublayer(flash)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override func layout() {
        super.layout()
        // Неявные анимации отключены: ширина окна меняется на ходу, и заливка
        // с маской обязаны идти с ним кадр в кадр, а не догонять его с задержкой.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        backdrop.frame = bounds
        glow.frame = Self.glowFrame
        // Своя копия маски: одну и ту же нельзя отдать двум слоям.
        glow.mask = maskLayer(offsetBy: CGPoint(x: -Self.glowFrame.minX, y: -Self.glowFrame.minY))
        flash.frame = bounds
        flash.mask = maskLayer()
        updatePath()
        CATransaction.commit()
    }

    /// Курсор на пилюле. Событие приходит и когда окно уезжает из-под курсора,
    /// поэтому решение принимает не оно, а `TimerWindowController`.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let hoverArea { removeTrackingArea(hoverArea) }
        // `.inVisibleRect` — область держится за границы вида сама: ширина окна
        // меняется на ходу, и пересчитывать прямоугольник вручную было бы нечем.
        let area = NSTrackingArea(rect: .zero,
                                  options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
                                  owner: self)
        addTrackingArea(area)
        hoverArea = area
    }

    override func mouseEntered(with event: NSEvent) { onHoverChange?() }
    override func mouseExited(with event: NSEvent) { onHoverChange?() }

    private func updatePath() {
        backdrop.path = roundedPath(in: bounds, radii: cornerRadii)
    }

    /// Копия формы подложки в роли маски для вспышки: без неё блик выходил бы
    /// за скруглённые углы прямоугольником.
    private func maskLayer(offsetBy shift: CGPoint = .zero) -> CAShapeLayer {
        let mask = CAShapeLayer()
        mask.frame = CGRect(origin: shift, size: bounds.size)
        mask.path = roundedPath(in: bounds, radii: cornerRadii)
        mask.fillColor = NSColor.black.cgColor
        return mask
    }

    /// Зажигает или гасит свечение в углу. Цвет ставится сразу, видимость —
    /// прозрачностью: так свечение появляется и уходит тем же плавным переходом,
    /// что и фон под ним.
    func setGlow(_ color: NSColor?, animated: Bool) {
        if let color {
            // Второй стоп — прозрачный чёрный, а не прозрачный цвет свечения:
            // в макете гаснет и цвет, и прозрачность, поэтому край круга вдвое
            // темнее, чем при затухании одной альфы.
            glow.colors = [color.cgColor, designColor(0x000000, 0).cgColor]
        }
        let target: Float = color == nil ? 0 : 1
        guard glow.opacity != target else { return }
        guard animated else {
            glow.removeAnimation(forKey: "glow")
            glow.opacity = target
            return
        }
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = glow.presentation()?.opacity ?? glow.opacity
        fade.toValue = target
        fade.duration = 0.55
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        glow.opacity = target
        glow.add(fade, forKey: "glow")
    }

    /// Перекрашивает фон. `animated` — плавный переход с бликом, иначе мгновенно
    /// (так фон встаёт на место при первом показе окна и при сбросе).
    func setBackdrop(_ color: NSColor, animated: Bool) {
        guard backdrop.fillColor != color.cgColor else { return }
        guard animated else {
            backdrop.removeAnimation(forKey: "fill")
            backdrop.fillColor = color.cgColor
            return
        }

        let fade = CABasicAnimation(keyPath: "fillColor")
        fade.fromValue = backdrop.presentation()?.fillColor ?? backdrop.fillColor
        fade.toValue = color.cgColor
        fade.duration = 0.55
        fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        backdrop.fillColor = color.cgColor
        backdrop.add(fade, forKey: "fill")

        let blink = CAKeyframeAnimation(keyPath: "opacity")
        blink.values = [0, 0.28, 0]
        blink.keyTimes = [0, 0.18, 1]
        blink.duration = 0.55
        flash.add(blink, forKey: "flash")
    }
}

// MARK: - Прилипание к углам экрана

/// Угол экрана, к которому сейчас приклеено окно — если приклеено.
enum ScreenCorner {
    case topLeft, topRight, bottomLeft, bottomRight
}

/// Стороны экрана, которых касается видимая пилюля. `top` и `bottom` названы
/// так, как их видит человек: `top` — верхняя кромка экрана.
struct ScreenEdges: OptionSet {
    let rawValue: Int

    static let left = ScreenEdges(rawValue: 1 << 0)
    static let right = ScreenEdges(rawValue: 1 << 1)
    static let top = ScreenEdges(rawValue: 1 << 2)
    static let bottom = ScreenEdges(rawValue: 1 << 3)
}

/// Скругление углов пилюли из макета — одно на все четыре, пока окно не
/// прижато к кромке экрана.
let pillCornerRadius: CGFloat = 8

/// Скругление углов пилюли по тому, каких сторон экрана она касается.
///
/// Скруглён только тот угол, обе стороны которого лежат внутри экрана. Угол,
/// сошедшийся на кромке, обязан быть прямым: скруглённый оставлял бы под собой
/// щель, и окно не заполняло бы край экрана вплотную. Прижали окно верхом —
/// прямыми становятся оба верхних угла, а не только тот, что в углу экрана.
func cornerRadii(touching edges: ScreenEdges, radius: CGFloat) -> CornerRadii {
    func corner(_ sides: ScreenEdges) -> CGFloat { edges.isDisjoint(with: sides) ? radius : 0 }
    return (topLeft: corner([.top, .left]), topRight: corner([.top, .right]),
            bottomRight: corner([.bottom, .right]), bottomLeft: corner([.bottom, .left]))
}

/// Окно, которое во время перетаскивания прилипает к углам экрана и никогда
/// не выходит за его границы.
///
/// Перетаскивание здесь своё, а не `isMovableByWindowBackground`. Системное
/// таскание за фон окна уходит в оконный сервер: тот двигает окно мимо AppKit,
/// `constrainFrameRect(_:to:)` при этом не вызывается ни разу, а сам сервер
/// не пускает рамку под меню-бар. Из-за этого пилюля упиралась в невидимую
/// преграду — полосу меню (33 пт) плюс своё поле под тень (20 пт) — и до
/// физического угла экрана не доходила, а прилипание с квадратным углом
/// срабатывали только при программных перестановках окна.
///
/// Свой цикл двигает окно через `setFrameOrigin`, который никаких ограничений
/// не накладывает: угол экрана достижим, и прилипание работает живьём.
final class SnappingWindow: NSWindow {
    /// Расстояние до края экрана, ближе которого окно прилипает к нему.
    static let snapDistance: CGFloat = 24

    /// Насколько нужно увести мышь, чтобы нажатие стало перетаскиванием.
    /// Без порога окно прыгало бы в угол от прилипания на обычном клике.
    private static let dragThreshold: CGFloat = 3

    /// Прозрачное поле вокруг видимой пилюли — место под мягкую тень.
    /// Прилипает и упирается в границы экрана именно видимая часть, а не эта
    /// рамка целиком, иначе пилюля будет останавливаться на расстоянии поля
    /// от настоящего угла экрана.
    var contentInset: CGFloat = 0

    /// Где курсор. Подменяется в живой проверке: настоящую мышь она не двигает,
    /// а перенос окна проверить надо.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    /// Вызывается с новым набором сторон всякий раз, когда рамка окна
    /// ограничивается — в том числе с пустым, когда окно отходит от края.
    var onEdgesChange: ((ScreenEdges) -> Void)?

    /// Последний сообщённый набор — чтобы не перерисовывать скругление и тень
    /// на каждом событии перетаскивания: стороны меняются несколько раз за
    /// перенос, а событий приходят сотни. `nil` — ещё ни разу не сообщали,
    /// и первый же расчёт уйдёт наружу, даже если окно ничего не касается.
    private var reportedEdges: ScreenEdges?

    // У `.borderless` окна оба по умолчанию `false` — тогда первый клик по
    // кнопке внутри только активирует окно, а не нажимает её.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Перетаскивание окна за фон. Нажатие доходит сюда по цепочке ответчиков
    /// от вида, который его не разобрал, и цикл крутится до отпускания кнопки —
    /// ровно тот уговор, на который опирается клик по табло: управление
    /// вернулось, а окно стоит на месте — значит, это был клик.
    override func mouseDown(with event: NSEvent) {
        let start = pointerLocation()
        // Захват считается один раз, от начала: если брать смещение от каждого
        // прошлого положения, окно уползает от курсора на каждом прилипании.
        let grab = NSPoint(x: frame.origin.x - start.x, y: frame.origin.y - start.y)
        var dragging = false

        while let next = NSApp.nextEvent(matching: [.leftMouseUp, .leftMouseDragged],
                                         until: .distantFuture,
                                         inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { break }

            let now = pointerLocation()
            if !dragging {
                guard abs(now.x - start.x) > Self.dragThreshold
                        || abs(now.y - start.y) > Self.dragThreshold else { continue }
                dragging = true
            }

            let moved = NSRect(origin: NSPoint(x: now.x + grab.x, y: now.y + grab.y),
                               size: frame.size)
            // Экран берётся по курсору, а не по окну: иначе на двух мониторах
            // окно липнет к углам того экрана, с которого его уже увели.
            let under = NSScreen.screens.first { $0.frame.contains(now) } ?? screen
            setFrameOrigin(settle(moved, on: under).origin)
        }
    }

    /// Перенос окна, начатый с вида, который сам разбирает нажатия, — с кнопки
    /// или с ряда черточек. Трекер берут за любое место, а не только за фон.
    ///
    /// `true` — это оказался перенос, и своё нажатие вид уже не выполняет.
    /// `false` — мышь отпустили на месте, значит это был обычный клик.
    func dragIfMoved(after event: NSEvent) -> Bool {
        let start = pointerLocation()
        while let next = NSApp.nextEvent(matching: [.leftMouseUp, .leftMouseDragged],
                                         until: .distantFuture,
                                         inMode: .eventTracking, dequeue: true) {
            if next.type == .leftMouseUp { return false }
            let now = pointerLocation()
            guard abs(now.x - start.x) > Self.dragThreshold
                    || abs(now.y - start.y) > Self.dragThreshold else { continue }
            // Дальше окно ведёт свой обычный цикл переноса — с прилипанием
            // к углам и упором в края экрана.
            mouseDown(with: next)
            return true
        }
        return false
    }

    /// Программные перестановки окна (`setFrame`, восстановление места) идут
    /// через ту же подгонку, что и живое перетаскивание.
    ///
    /// Не через `super`: он поджимает рамку под меню-бар и Док, и до
    /// физического угла экрана она уже не дотягивается.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        settle(frameRect, on: screen ?? self.screen)
    }

    /// Прилипание к углу, упор в границы экрана и пересчёт того, каким углом
    /// окно сейчас прижато.
    private func settle(_ frameRect: NSRect, on screen: NSScreen?) -> NSRect {
        // Именно `frame`, а не `visibleFrame`: последний обрезан под меню и Док,
        // и его край совпадает с краем обычного окна на весь экран — из-за этого
        // казалось, что окно липнет к чужому окну, а не к самому экрану.
        guard let target = screen?.frame else { return frameRect }

        var visible = frameRect.insetBy(dx: contentInset, dy: contentInset)

        // Прилипание — только когда рядом сразу два края, то есть угол целиком.
        // Поодиночке края не тянут: иначе окно магнитится к верху или к боку
        // экрана даже тогда, когда его просто тащат мимо, не целясь в угол.
        let nearMinX = abs(visible.minX - target.minX) < Self.snapDistance
        let nearMaxX = abs(visible.maxX - target.maxX) < Self.snapDistance
        let nearMinY = abs(visible.minY - target.minY) < Self.snapDistance
        let nearMaxY = abs(visible.maxY - target.maxY) < Self.snapDistance

        let snapCorner: ScreenCorner?
        switch (nearMinX, nearMaxX, nearMinY, nearMaxY) {
        case (true, _, _, true): snapCorner = .topLeft
        case (_, true, _, true): snapCorner = .topRight
        case (true, _, true, _): snapCorner = .bottomLeft
        case (_, true, true, _): snapCorner = .bottomRight
        default: snapCorner = nil
        }

        switch snapCorner {
        case .topLeft:     visible.origin = NSPoint(x: target.minX, y: target.maxY - visible.height)
        case .topRight:    visible.origin = NSPoint(x: target.maxX - visible.width, y: target.maxY - visible.height)
        case .bottomLeft:  visible.origin = NSPoint(x: target.minX, y: target.minY)
        case .bottomRight: visible.origin = NSPoint(x: target.maxX - visible.width, y: target.minY)
        case nil: break
        }

        // Что бы ни случилось выше — видимая часть не должна оказаться за пределами экрана.
        visible.origin.x = min(max(visible.origin.x, target.minX), target.maxX - visible.width)
        visible.origin.y = min(max(visible.origin.y, target.minY), target.maxY - visible.height)

        // Стороны считаются по факту положения, а не по порогу прилипания:
        // так углы остаются прямыми и тогда, когда окно просто утащили за
        // пределы экрана и упёрли в край ограничением, а не притяжением.
        // Каждая сторона — сама по себе: прижатым верхом окно бывает и без угла.
        var edges: ScreenEdges = []
        if visible.minX == target.minX { edges.insert(.left) }
        if visible.maxX == target.maxX { edges.insert(.right) }
        if visible.minY == target.minY { edges.insert(.bottom) }
        if visible.maxY == target.maxY { edges.insert(.top) }
        if reportedEdges != edges {
            reportedEdges = edges
            onEdgesChange?(edges)
        }

        return visible.insetBy(dx: -contentInset, dy: -contentInset)
    }
}

// MARK: - Контроллер окна

/// Прозрачная рамка вокруг пилюли: в её поле лежит своя тень. Форму тени
/// приходится пересчитывать на каждой раскладке — ширина окна меняется на ходу,
/// когда трекер сворачивается в ёмкий вид, и застывшая тень выглядывала бы
/// из-под свёрнутой пилюли.
final class ShadowFrameView: NSView {
    var onLayout: (() -> Void)?

    override func layout() {
        super.layout()
        onLayout?()
    }
}

/// Окно таймера: 294×86, без системной обвязки. Два экрана в одном окне —
/// выбор (три варианта) и отсчёт (табло, пауза, «дальше», стоп, полоса остатка).
final class TimerWindowController: NSWindowController {

    /// Размер видимой пилюли из макета.
    static let windowSize = NSSize(width: 294, height: 86)

    /// Ширина ёмкого вида из макета: остаются табло и полоса остатка, кнопки
    /// уезжают за правый край. Высота та же — сворачивается только ширина.
    static let compactWidth: CGFloat = 136
    /// Сколько длится свёртывание и развёртывание.
    static let foldDuration: TimeInterval = 0.26
    /// Сколько трекер ждёт, прежде чем свернуться. Разворачивается он сразу,
    /// а сворачивается с паузой: курсор проходит по окну мимоходом десятки раз
    /// за час, и окно, схлопывающееся ему вслед, дёргалось бы под рукой.
    static let foldDelay: TimeInterval = 5
    /// Кривая свёртывания: быстрый разгон и мягкая остановка — та же, по которой
    /// съезжают цифры на табло, чтобы движения в окне были одного почерка.
    static let foldCurve = CAMediaTimingFunction(controlPoints: 0.22, 0.9, 0.2, 1)

    /// Сторона круглой кнопки отсчёта из макета.
    static let controlSize: CGFloat = 40
    /// Ширина «стопа» на отдыхе: там он один на весь ряд.
    static let restStopWidth: CGFloat = 128

    /// Прозрачное поле вокруг пилюли внутри рамки окна — своя, едва заметная
    /// тень рисуется в нём, а не системной тенью окна: у той нет регулировки
    /// силы, и убрать её мягче обычной не получалось.
    ///
    /// Не `private`: живая проверка считает по нему ширину видимой пилюли —
    /// у окна она всегда шире на два таких поля.
    static let shadowMargin: CGFloat = 20

    private let engine = TimerEngine(duration: TimeInterval(Presets.focus[0] * 60))
    private var ticker: Timer?

    /// Зачем идёт текущий отсчёт: работа или отдых.
    private var kind: Kind = .focus
    /// Ряд черточек в половинках: 25 минут — половина, 55 — целая.
    /// Заполнился весь ряд — следующий отрезок начинает его заново.
    private var filledHalves = 0
    /// Всё отработанное за сеанс, тоже в половинках. В отличие от ряда,
    /// на четырёх штрихах не обнуляется: ряд показывает круг, а это — итог.
    private var totalHalves = 0

    /// Итог для пункта «Summary», в половинках штриха. Наружу отдаются именно
    /// половинки, а не часы: пересчёт в часы — дело подписи, а не отсчёта.
    var completedHalves: Int { totalHalves }
    /// Цвет свечения. Перебирается кликом по табло.
    private var accent: Accent = .default

    /// Как трекер держит ширину: `Adaptive` — сворачивается без курсора,
    /// `Always Full` — всегда полный. Переключается пунктами меню помидора.
    var viewMode: ViewMode = .default {
        didSet { syncWidth(animated: true) }
    }

    /// Ширина видимой пилюли прямо сейчас — полная из макета или ёмкая.
    private var pillWidth: CGFloat = TimerWindowController.windowSize.width

    /// Стороны экрана, которых окно сейчас касается. От них зависит и
    /// скругление углов, и свёртывание: у окна, прижатого правым краем,
    /// на месте остаётся правый край, а не левый.
    private var touchedEdges: ScreenEdges = []

    /// Где курсор. Подменяется в живой проверке: там мышь стоит там, где её
    /// оставил человек, и сверять по ней ширину окна нельзя.
    var pointerLocation: () -> NSPoint = { NSEvent.mouseLocation }

    /// Отсчёт паузы перед свёртыванием. Живёт, только пока трекер ждёт;
    /// вернулся курсор или сменилось состояние — снимается.
    private var foldTimer: Timer?
    /// Показана ли кнопка сброса вместо кнопок выбора. Переключается кликом
    /// по ряду черточек: клик показывает кнопку, повторный клик убирает её.
    private var resetShown = false

    /// Настоящий contentView окна: прозрачная рамка с полем под тень.
    /// Пилюля (`root`) лежит внутри неё, отступив на `shadowMargin`.
    private let frameView = ShadowFrameView()
    private let root = RootView(frame: .zero)

    // Экран выбора
    private var presetButtons: [PillButton] = []
    private let choiceStack = NSStackView()
    /// Тот же ряд засечек, что и на отсчёте: общий счёт отработанного за сеанс.
    private let choiceSegments = SegmentsView()
    /// Сброс прогресса. Лежит на месте кнопок выбора и показывается только
    /// под курсором — ровно как в макете.
    private let resetButton = PillButton(wideSymbol: "arrow.clockwise", label: "Reset progress",
                                         target: nil, action: nil)

    // Экран отсчёта
    private let clock = FlipClockView(frame: .zero)
    /// Пауза и продолжение — одна кнопка: иконка меняется по ходу отсчёта.
    private let pauseButton = PillButton(symbol: "pause.fill", label: "Pause",
                                         target: nil, action: nil)
    /// «Дальше»: закончить отрезок сейчас — и зачесть его как отработанный.
    private let skipButton = PillButton(symbol: "forward.fill", label: "Finish now",
                                        target: nil, action: nil)
    /// «Стоп»: бросить отсчёт и вернуться на главный экран.
    private let stopButton = PillButton(symbol: "stop.fill", label: "Stop",
                                        target: nil, action: nil)
    private let controlsStack = NSStackView()
    private let progress = ProgressBar()



    init() {
        let margin = Self.shadowMargin
        let outerSize = NSSize(width: TimerWindowController.windowSize.width + margin * 2,
                               height: TimerWindowController.windowSize.height + margin * 2)
        // `.borderless`, а не `.titled`: у titled-окна оконный сервер держит
        // полосу заголовка ниже меню-бара даже тогда, когда она не видна,
        // и своим циклом перетаскивания это уже не обойти.
        let window = SnappingWindow(
            contentRect: NSRect(origin: .zero, size: outerSize),
            styleMask: [.borderless],
            backing: .buffered, defer: false)
        window.title = "Pimer"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        window.contentInset = margin
        window.onEdgesChange = { [weak self] edges in self?.updateCornerRadii(touching: edges) }
        // Тень пересобирается на каждой раскладке рамки: ширина окна меняется
        // на ходу вместе с ёмким видом.
        frameView.onLayout = { [weak self] in self?.updateShadowPath() }
        root.onHoverChange = { [weak self] in self?.syncWidth(animated: true) }

        // Ключевая строка: окно живёт над обычными окнами и видно во всех пространствах.
        //
        // Уровень именно `.statusBar` (25), а не `.floating` (3): Док лежит на
        // уровне 20, меню-бар на 24, и «поверх всех окон» на третьем уровне
        // означало «поверх обычных окон, но под Доком и меню». Пилюля, задвинутая
        // в нижний угол, пряталась за Доком, а в верхнем её срезал меню-бар —
        // тот самый угол, до которого её и тащат. Выше 25 забираться незачем:
        // всплывающие меню (101) и системные окна должны оставаться сверху.
        window.level = .statusBar
        window.collectionBehavior.insert(.canJoinAllSpaces)

        // Не `isMovableByWindowBackground`: системное таскание за фон уходит в
        // оконный сервер и не пускает окно под меню-бар. Окно двигает `SnappingWindow`
        // своим циклом — см. комментарий у класса.

        // Иначе система восстанавливает прошлое место окна уже после запуска
        // и перетирает то, которое посчитал `placeWindow()`.
        window.isRestorable = false
        // Прозрачный фон нужен, чтобы своё скругление не подкладывалось на белый прямоугольник.
        window.isOpaque = false
        window.backgroundColor = .clear
        // Системную тень заменяет своя, на слое `frameView` — так её можно
        // сделать почти невидимой, чего с системной тенью не добиться.
        window.hasShadow = false
        window.appearance = NSAppearance(named: .darkAqua)

        buildInterface()
        setUpFrame(margin: margin)
        window.contentView = frameView
        setUpShadow(margin: margin)
        window.setContentSize(outerSize)
        // Имя для запоминания места выдаётся не здесь, а в `placeWindow()`:
        // AppKit начинает сохранять место сразу, как имя выдано, и центрирование
        // строкой ниже перетирало место, оставленное в прошлый раз, — читать
        // потом было уже нечего.
        Self.centerOnMainDisplay(window)

        engine.onFinish = { [weak self] overdue in self?.handleFinish(overdue: overdue) }
        applyScreen()
        applyState(animated: false)
        startTicker()
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    deinit {
        ticker?.invalidate()
        foldTimer?.invalidate()
    }

    /// Под каким именем окно запоминает своё место.
    private static let frameName = "PimerWindow"

    /// Ставит окно туда, где его оставили, — но только если это место всё ещё
    /// на экране. Иначе окно уходит в середину экрана. Здесь же окну выдаётся
    /// имя, под которым оно дальше запоминает своё место.
    ///
    /// Вызывается после показа окна, а не из `init`. И считает середину по
    /// `CGDisplayBounds`, а не по `NSScreen`: у приложения без иконки в доке
    /// список экранов на старте бывает пуст, и тогда `center()` молча ничего не
    /// делает — окно остаётся в левом нижнем углу, за доком.
    func placeWindow() {
        guard let window else { return }
        let restored = window.setFrameUsingName(Self.frameName)
        // Из запомненного берём только место. Ширину задаёт нынешний вид окна:
        // сохраниться она могла и ёмкой — тогда экран выбора открылся бы
        // в обрезанной пилюле шириной 136.
        window.setFrame(NSRect(origin: window.frame.origin,
                               size: NSSize(width: pillWidth + Self.shadowMargin * 2,
                                            height: Self.windowSize.height + Self.shadowMargin * 2)),
                        display: false)
        if !(restored && Self.isOnScreen(window)) {
            let area = Self.usableArea()
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2,
                                          y: area.midY - window.frame.height / 2))
        }
        // Запоминать место окно начинает только теперь — когда прошлое уже
        // прочитано и разобрано.
        window.setFrameAutosaveName(Self.frameName)

        // `setFrameOrigin` не проходит через `constrainFrameRect`, поэтому угол,
        // сохранённый с прошлого запуска, синхронизируется отдельно, вручную.
        if let snapping = window as? SnappingWindow {
            _ = snapping.constrainFrameRect(window.frame, to: window.screen)
        }
    }

    /// Лежит ли видимая пилюля целиком на каком-нибудь экране.
    ///
    /// Считается по `frame` экрана, а не по `visibleFrame`: окно доходит до
    /// физических углов, и место, оставленное в углу под меню-баром или Доком,
    /// по `visibleFrame` считалось бы потерянным — окно уезжало бы из угла
    /// в середину экрана при каждом запуске.
    private static func isOnScreen(_ window: NSWindow) -> Bool {
        let inset = (window as? SnappingWindow)?.contentInset ?? 0
        let pill = window.frame.insetBy(dx: inset, dy: inset)
        return NSScreen.screens.contains { $0.frame.insetBy(dx: -1, dy: -1).contains(pill) }
    }

    /// Ставит окно в середину главного дисплея. Считает по Core Graphics:
    /// `NSScreen` и `center()` на старте приложения без иконки в доке ненадёжны.
    static func centerOnMainDisplay(_ window: NSWindow) {
        let display = CGDisplayBounds(CGMainDisplayID())
        window.setFrameOrigin(NSPoint(x: (display.width - window.frame.width) / 2,
                                      y: (display.height - window.frame.height) / 2))
    }

    /// Область, в которой окну можно стоять, в координатах Cocoa.
    private static func usableArea() -> NSRect {
        if let visible = NSScreen.main?.visibleFrame ?? NSScreen.screens.first?.visibleFrame {
            return visible
        }
        // Запасной путь: главный дисплей по данным Core Graphics. У главного
        // дисплея начало координат общее для CG и Cocoa, поэтому пересчёт не нужен.
        let bounds = CGDisplayBounds(CGMainDisplayID())
        return NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height)
    }

    // MARK: - Тень и угол экрана

    /// Кладёт пилюлю (`root`) в прозрачную рамку окна с отступом `margin` —
    /// в этом отступе рисуется своя, едва заметная тень, которую не даёт
    /// системная тень окна (`window.hasShadow`): у неё нет ручки силы.
    private func setUpFrame(margin: CGFloat) {
        frameView.wantsLayer = true
        frameView.layer?.backgroundColor = NSColor.clear.cgColor

        root.translatesAutoresizingMaskIntoConstraints = false
        frameView.addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: frameView.leadingAnchor, constant: margin),
            root.trailingAnchor.constraint(equalTo: frameView.trailingAnchor, constant: -margin),
            root.topAnchor.constraint(equalTo: frameView.topAnchor, constant: margin),
            root.bottomAnchor.constraint(equalTo: frameView.bottomAnchor, constant: -margin),
        ])
    }

    /// Настраивает саму тень — отдельно и обязательно уже после того, как
    /// `frameView` стал `window.contentView`: сама эта установка обнуляет
    /// `layer.shadowOpacity`, если тень задать раньше, она молча пропадает.
    private func setUpShadow(margin: CGFloat) {
        frameView.layer?.shadowColor = NSColor.black.cgColor
        frameView.layer?.shadowOpacity = 0.18
        frameView.layer?.shadowRadius = 7
        frameView.layer?.shadowOffset = CGSize(width: 0, height: -2)
        updateShadowPath()
    }

    /// Обнуляет скругление у углов, сошедшихся на кромке экрана, — чтобы окно
    /// заполняло край вплотную, без зазора под скруглением. Форма тени
    /// обновляется вместе с ними, иначе она останется скруглённой под углом,
    /// который уже стал прямым.
    private func updateCornerRadii(touching edges: ScreenEdges) {
        touchedEdges = edges
        root.cornerRadii = cornerRadii(touching: edges, radius: pillCornerRadius)
        updateShadowPath()
    }

    /// Путь тени — тот же прямоугольник, что рисует `root`, но в координатах
    /// `frameView`, то есть сдвинутый на `shadowMargin`. Задан явно: у `frameView`
    /// нет своего непрозрачного содержимого, чтобы форму тени можно было
    /// вывести из него автоматически.
    ///
    /// Размер берётся из живой рамки, а не из макета: ширина окна меняется
    /// вместе с ёмким видом, и на каждом кадре свёртывания она своя.
    ///
    /// `frameView`, в отличие от `root`, не перевёрнут (`isFlipped == false`),
    /// поэтому в его координатах верх и низ у `roundedPath` меняются местами —
    /// иначе квадратный угол тени оказывался бы не под тем углом пилюли.
    private func updateShadowPath() {
        let radii = root.cornerRadii
        let visibleRect = frameView.bounds.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
        guard visibleRect.width > 0, visibleRect.height > 0 else { return }
        let flipped: CornerRadii = (topLeft: radii.bottomLeft, topRight: radii.bottomRight,
                                    bottomRight: radii.topRight, bottomLeft: radii.topLeft)
        // Без отключения неявной анимации тень тянется за окном с задержкой
        // и на свёртывании отстаёт от пилюли на добрую четверть секунды.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        frameView.layer?.shadowPath = roundedPath(in: visibleRect, radii: flipped)
        CATransaction.commit()
    }

    // MARK: - Сборка интерфейса

    private func buildInterface() {
        root.wantsLayer = true

        // Варианты — только рабочие: пятиминутка приходит сама после отрезка,
        // выбирать её руками незачем.
        presetButtons = Presets.minutes.map { minutes in
            PillButton(minutes: minutes, target: self, action: #selector(presetTapped(_:)))
        }
        // Кнопки выбора не держат ширину окна. Их ряд растянут от поля до поля,
        // и своей шириной «25 min» + «55 min» задавал окну нижнюю границу в 164
        // точки — ниже неё окно не сжималось, и ёмкий вид не доходил до 136.
        // На экране выбора ничего не меняется: там ширину кнопкам всё равно
        // раздаёт `fillEqually`, а не их содержимое.
        for button in presetButtons {
            button.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        }

        choiceStack.setViews(presetButtons, in: .center)
        choiceStack.orientation = .horizontal
        // Варианты делят ширину окна поровну: между ними не выбирают по размеру.
        choiceStack.distribution = .fillEqually
        choiceStack.spacing = 4

        resetButton.target = self
        resetButton.action = #selector(resetTapped)
        choiceSegments.onClick = { [weak self] in self?.toggleReset() }

        clock.onClick = { [weak self] in self?.clockTapped() }

        pauseButton.target = self
        pauseButton.action = #selector(pauseTapped)
        skipButton.target = self
        skipButton.action = #selector(skipTapped)
        stopButton.target = self
        stopButton.action = #selector(stopTapped)

        // Порядок: дальше (сделал), пауза (вернусь), стоп (хватит).
        controlsStack.setViews([skipButton, pauseButton, stopButton], in: .center)
        controlsStack.orientation = .horizontal
        controlsStack.distribution = .fill
        controlsStack.spacing = 4

        layout()
    }

    /// Раскладка под 294×86 из макета: отступ 16 по краям, слева табло,
    /// справа ряд круглых кнопок, снизу полоса остатка. На экране выбора те же
    /// 16 по краям: три пилюли и под ними ряд черточек.
    private func layout() {
        for view in [clock, choiceStack, resetButton, choiceSegments, controlsStack, progress] as [NSView] {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
        }

        let inset: CGFloat = 16
        NSLayoutConstraint.activate([
            // Экран отсчёта: табло, кнопки и полоса — все три на своих местах из макета.
            clock.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            clock.topAnchor.constraint(equalTo: root.topAnchor, constant: 18),

            // Ряд кнопок держится за левый край, а не за правый: в ёмком виде
            // окно сужается до 136, и кнопки должны уехать за правый край
            // целиком, а не сползти на табло. 150 — их место из макета:
            // 294 − 16 (поле справа) − 128 (ширина ряда).
            controlsStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 150),
            controlsStack.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),

            // Экран выбора: три пилюли сверху, под ними ряд засечек по левому краю.
            choiceStack.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            choiceStack.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            choiceStack.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),

            // Кнопка сброса встаёт ровно на место кнопок выбора: в макете она
            // и есть весь этот ряд, а не отдельная кнопка рядом с ними.
            resetButton.leadingAnchor.constraint(equalTo: choiceStack.leadingAnchor),
            resetButton.trailingAnchor.constraint(equalTo: choiceStack.trailingAnchor),
            resetButton.topAnchor.constraint(equalTo: choiceStack.topAnchor),

            // Черточки тянутся во всю ширину окна: четыре кнопки, а не короткий ряд засечек.
            // Снизу те же 16, что и у полосы отсчёта: обе стоят на одной линии,
            // и переключение экранов не дёргает её вверх-вниз.
            choiceSegments.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            choiceSegments.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            choiceSegments.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            choiceSegments.heightAnchor.constraint(equalToConstant: 4),

            progress.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: inset),
            progress.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            progress.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
            progress.heightAnchor.constraint(equalToConstant: 4),
        ])
    }

    // MARK: - Экраны

    /// Экран выбора: ровно те варианты, которые вернул `Screen`, и ничего больше.
    /// Подписей здесь нет — цифры на кнопках говорят сами за себя.
    private func renderChoice(options: [Int]) {
        for button in presetButtons { button.isHidden = !options.contains(button.tag) }
        choiceStack.isHidden = false
        choiceSegments.isHidden = false
        clock.isHidden = true
        controlsStack.isHidden = true
        progress.isHidden = true
        syncResetButton()
    }

    /// Экран отсчёта. На отдыхе из кнопок остаётся один «стоп»: перерыв короткий
    /// и идёт сам — ни ставить его на паузу, ни обрывать досрочно незачем.
    private func showCountdown() {
        pauseButton.isHidden = kind == .rest
        skipButton.isHidden = kind == .rest
        // На отдыхе «стоп» остаётся один и занимает всю ширину ряда кнопок:
        // 128 при отступе 16 справа, иконка по центру.
        stopButton.setWidth(kind == .rest ? Self.restStopWidth : Self.controlSize)
        // Отсчёт начался — кнопке сброса здесь не место, и в следующий раз
        // экран выбора открывается с кнопками 25/55, а не с ней.
        resetShown = false
        choiceStack.isHidden = true
        choiceSegments.isHidden = true
        resetButton.isHidden = true
        clock.isHidden = false
        controlsStack.isHidden = false
        progress.isHidden = false
        refresh()
    }

    // MARK: - Действия

    @objc private func presetTapped(_ sender: NSButton) {
        startTimer(minutes: sender.tag)
    }

    /// Единственный способ запустить отсчёт — и по кнопке, и автоматически после звонка.
    private func startTimer(minutes: Int) {
        let previous = kind
        kind = Kind.forMinutes(minutes)
        engine.start(seconds: TimeInterval(minutes * 60))
        applyScreen()
        applyState(animated: previous != kind)
        syncProgress()
        syncTicker()
    }

    /// Цвета, в которых окно должно быть прямо сейчас. Экран выбора всегда
    /// чёрный: отдых и пауза — свойства идущего отсчёта, а не выбора.
    private var currentLook: Look {
        guard Screen.forState(engine.state) == .countdown else {
            // Экран выбора — ровный чёрный: свечение в макете есть только
            // у идущего отсчёта, и менять фон под выбором нечем.
            var choice = Palette.focus
            choice.glow = nil
            return choice
        }
        var look = Palette.look(kind: kind, paused: engine.state == .paused)
        // Свечение есть только у идущей работы — там же и живёт выбранный цвет.
        if look.glow != nil { look.glow = Palette.glow(accent) }
        return look
    }

    /// Приводит окно в согласие с состоянием: и цвета, и ширину. Зовётся везде,
    /// где состояние поменялось, — тогда ёмкий вид и перекраска не разъезжаются.
    private func applyState(animated: Bool) {
        applyLook(animated: animated)
        syncWidth(animated: animated)
    }

    /// Каким окну быть прямо сейчас — ёмким или полным.
    private var wantsCompact: Bool {
        isCompact(mode: viewMode, state: engine.state, kind: kind, hovered: pointerInside)
    }

    /// Курсор на пилюле. Считается по факту, а не по последнему событию мыши:
    /// `mouseEntered` не приходит, если курсор уже стоял над окном к моменту,
    /// когда отсчёт начался, — а решать надо и в этот момент тоже.
    private var pointerInside: Bool {
        guard let window, window.isVisible else { return false }
        return window.frame.insetBy(dx: Self.shadowMargin, dy: Self.shadowMargin)
            .contains(pointerLocation())
    }

    /// Сворачивает и разворачивает трекер. Ширина — единственное, что меняется:
    /// табло и полоса стоят на своих местах из макета, кнопки уходят за правый
    /// край и возвращаются оттуда же.
    ///
    /// Полный вид возвращается сразу, ёмкий — через `foldDelay`: рука с мышью
    /// проходит над окном чаще, чем уходит от него насовсем.
    func syncWidth(animated: Bool) {
        guard wantsCompact else {
            cancelFold()
            setPillWidth(Self.windowSize.width, animated: animated)
            return
        }
        // Без анимации сворачиваем сразу: так окно встаёт на место при первом
        // показе, и так же его ставит живая проверка, которой ждать нечего.
        guard animated else { return setPillWidth(Self.compactWidth, animated: false) }
        scheduleFold()
    }

    /// Заводит паузу перед свёртыванием. Пока она идёт, второй раз не заводит:
    /// `syncWidth` дёргается и тикером, четыре раза в секунду.
    private func scheduleFold() {
        guard pillWidth != Self.compactWidth, foldTimer == nil else { return }
        let timer = Timer.scheduledTimer(withTimeInterval: Self.foldDelay, repeats: false) {
            [weak self] _ in
            guard let self else { return }
            self.foldTimer = nil
            // За пять секунд всё могло перемениться: курсор вернулся, отсчёт
            // встал на паузу, человек выбрал `Always Full`.
            guard self.wantsCompact else { return }
            self.setPillWidth(Self.compactWidth, animated: true)
        }
        // Иначе пауза замирает, пока пользователь тащит окно или держит меню.
        RunLoop.main.add(timer, forMode: .common)
        foldTimer = timer
    }

    private func cancelFold() {
        foldTimer?.invalidate()
        foldTimer = nil
    }

    /// Меняет ширину видимой пилюли — с анимацией или сразу.
    private func setPillWidth(_ target: CGFloat, animated: Bool) {
        guard let window, target != pillWidth else { return }
        pillWidth = target

        var frame = window.frame
        frame.size.width = target + Self.shadowMargin * 2
        // У окна, прижатого к правому углу экрана, на месте остаётся правый
        // край — иначе пилюля отлипала бы от угла и уезжала к середине.
        // В остальных случаях стоит левый: по нему выровнено содержимое.
        if touchedEdges.contains(.right) {
            frame.origin.x = window.frame.maxX - frame.width
        }

        guard animated else {
            window.setFrame(frame, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = Self.foldDuration
            context.timingFunction = Self.foldCurve
            window.animator().setFrame(frame, display: true)
        }
    }

    /// Перекрашивает окно целиком: фон, табло, кнопки, трек и полосу.
    /// Единственное место, где цвет попадает в интерфейс, — поэтому пауза,
    /// отдых и возврат к выбору не расходятся между собой.
    private func applyLook(animated: Bool) {
        let look = currentLook
        root.setBackdrop(look.backdrop, animated: animated)
        root.setGlow(look.glow, animated: animated)
        clock.textColor = look.text
        progress.apply(look: look)
        for button in presetButtons { button.apply(look: look) }
        for button in [resetButton, pauseButton, skipButton, stopButton] { button.apply(look: look) }
    }

    /// Кнопка сброса и кнопки выбора делят одно и то же место, поэтому видно
    /// всегда ровно одно из двух. На пустом ряду сбрасывать нечего — кнопка
    /// не показывается, даже если её просили.
    private func syncResetButton() {
        // Кнопками выбора распоряжается только экран выбора. Иначе сюда можно
        // было прийти во время отсчёта и показать 25/55 поверх табло.
        let onChoice = Screen.forState(engine.state) != .countdown
        let visible = resetShown && filledHalves > 0 && onChoice
        resetButton.isHidden = !visible
        guard onChoice else { return }
        choiceStack.isHidden = visible
    }

    /// Клик по ряду черточек: первый показывает кнопку сброса вместо 25/55,
    /// второй возвращает 25/55, ничего не сбрасывая.
    private func toggleReset() {
        resetShown.toggle()
        syncResetButton()
    }

    /// Сброс всего прогресса: и ряда, и итога за сеанс. Один на оба пути —
    /// кнопку в окне и пункт «Reset» в меню помидора, — чтобы «сбросить»
    /// значило одно и то же, откуда бы его ни позвали.
    func resetProgress() {
        filledHalves = 0
        totalHalves = 0
        resetShown = false
        refresh()
        syncResetButton()
    }

    /// Сброс по кнопке. Прогресса больше нет, поэтому кнопке нечего предлагать
    /// и на её место сразу возвращаются 25/55.
    @objc private func resetTapped() {
        resetProgress()
    }

    /// Клик по табло перебирает цвет свечения: красный, зелёный, фиолетовый,
    /// синий и снова красный. Только на идущем отсчёте — на паузе и на отдыхе
    /// свечения в макете нет, и менять было бы нечего.
    private func clockTapped() {
        guard engine.isRunning, kind == .focus else { return }
        accent = accent.next
        applyState(animated: true)
    }

    /// Пауза и продолжение. На паузе окно уходит в серый (на отдыхе — в тёмно-зелёный):
    /// остановленное время видно по всему окну, а не по одной иконке.
    @objc private func pauseTapped() {
        engine.isRunning ? engine.pause() : engine.resume()
        refresh()
        applyState(animated: true)
        syncProgress()
        syncTicker()
    }

    /// «Дальше» — это «отрезок сделан» досрочно: тот же звонок, та же засечка,
    /// тот же переход к отдыху, что и по достижению нуля.
    @objc private func skipTapped() {
        engine.finishNow()
    }

    /// «Стоп» — отмена: отсчёт бросается, окно возвращается на главный экран.
    /// Засечку не ставим — отрезок не отработан.
    @objc private func stopTapped() {
        engine.reset()
        applyScreen()
        applyState(animated: true)
        syncProgress()
        syncTicker()
    }

    /// По звонку: отработанный отрезок добавляет засечку и сам сменяется отдыхом,
    /// после отдыха приложение возвращается к выбору.
    private func handleFinish(overdue: TimeInterval) {
        let minutes = Int(engine.duration / 60)
        Notifier.fire(minutes: minutes, kind: kind, overdue: overdue)
        filledHalves = Segments.advance(filledHalves, minutes: minutes)
        totalHalves += Segments.credit(minutes: minutes)

        if let next = nextAfterFinish(minutes: minutes) {
            startTimer(minutes: next)
        } else {
            // Отдых кончился — окно возвращается к чёрному вместе с выбором.
            applyScreen()
            applyState(animated: true)
        }
        syncTicker()
        window?.orderFrontRegardless()
    }

    /// Единственное место, где решается, что видно на экране.
    /// Решение берётся из `Screen.forState`, который покрыт тестом Ф2.2.
    private func applyScreen() {
        switch Screen.forState(engine.state) {
        case .choice(let options):
            renderChoice(options: options)
        case .countdown:
            showCountdown()
        }
    }

    // MARK: - Тик

    /// Тикер живёт только пока идёт отсчёт. В состояниях выбора и завершения
    /// считать нечего, а окно поверх всех окон никогда не бывает скрыто, поэтому
    /// App Nap приложение не усыпит и просыпаться четыре раза в секунду впустую
    /// оно будет ровно столько, сколько мы разрешим.
    private func startTicker() {
        guard ticker == nil else { return }
        let ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.engine.tick()
            if self.engine.state == .running { self.refresh() }
            // Заодно страховка ёмкого вида: `mouseExited` до окна доходит не
            // всегда — курсор мог уйти, пока сверху был Mission Control или
            // чужое полноэкранное окно. Ширина уже нужная — вызов пустой.
            self.syncWidth(animated: true)
        }
        // Иначе отсчёт замирает, пока пользователь тащит окно или держит меню открытым.
        RunLoop.main.add(ticker, forMode: .common)
        self.ticker = ticker
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }

    /// Держит тикер в согласии с состоянием: идёт отсчёт — тикаем, иначе спим.
    private func syncTicker() {
        engine.isRunning ? startTicker() : stopTicker()
    }

    /// Отдаёт полосе прогресс — но не каждый тик, а на смене хода отсчёта:
    /// дальше она едет сама одной линейной анимацией и потому не дёргается.
    private func syncProgress() {
        root.layoutSubtreeIfNeeded()
        let fraction = elapsedFraction(remaining: engine.remaining, duration: engine.duration)
        if engine.isRunning {
            progress.show(fraction: fraction, animatingFor: engine.remaining)
        } else {
            progress.freeze(fraction: fraction)
        }
    }

    private func refresh() {
        // Съезд цифр — только на ходу: на паузе и при сбросе табло встаёт молча.
        clock.setText(formatRemaining(engine.remaining), animated: engine.isRunning)
        engine.isRunning
            ? pauseButton.setSymbol("pause.fill", label: "Pause")
            : pauseButton.setSymbol("play.fill", label: "Resume")
        choiceSegments.filledHalves = filledHalves
    }
}
