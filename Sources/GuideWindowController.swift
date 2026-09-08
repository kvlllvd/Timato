import AppKit

/// Окно «Гайд»: короткое объяснение того, как устроен Timato, — отдельный
/// пункт меню поверх уже идущего таймера. Крестик закрывает только его,
/// сам отсчёт в другом окне продолжает идти (см. `applicationShouldTerminateAfterLastWindowClosed`).
///
/// Ширина фиксирована макетом — 500; высота нет, подписи по контенту могут
/// стать длиннее, обрезать их нельзя. Поэтому высота окна не задаётся, а
/// считается снизу вверх из содержимого при неизменной ширине (`fitWindow`).
final class GuideWindowController: NSWindowController {

    private static let contentWidth: CGFloat = 500
    private static let sidePadding: CGFloat = 28
    private static let topPadding: CGFloat = 24
    private static let bottomPadding: CGFloat = 26
    /// Ширина, в которую переносятся подписи, — вся ширина окна за вычетом полей.
    private static let textWidth = contentWidth - sidePadding * 2

    /// Цвета гайда одной темы сразу. Своих состояний у окна нет — есть только
    /// светлое и тёмное, — поэтому набор один на всё окно, в отличие от `Look`
    /// у трекера, где на каждое состояние отсчёта свой.
    private struct GuideLook {
        let backdrop: NSColor
        let text: NSColor
        /// Подписи под заголовками: приглушённые, но читаемые.
        let muted: NSColor
        /// Кружок под иконкой пункта.
        let iconBackground: NSColor
        /// Иконка в кружке. Заметнее, чем `iconIdle` у кнопок трекера: там
        /// приглушённый цвет — подсказка, что кнопку ещё не навели, здесь
        /// иконки не интерактивны и должны читаться сразу.
        let iconTint: NSColor
        /// Заметка про отдых: своя подложка с рамкой.
        let noteBackground: NSColor
        /// Рамка заметки — и та же черта, что делит список на две части.
        let noteBorder: NSColor

        static let night = GuideLook(backdrop: Palette.focus.backdrop,
                                     text: Palette.focus.text,
                                     muted: designColor(0x9a9a9a),
                                     iconBackground: Palette.focus.control,
                                     iconTint: designColor(0xcfcfcf),
                                     noteBackground: designColor(0x171717),
                                     noteBorder: NSColor.white.withAlphaComponent(0.14))
        /// Светлый гайд собран из тех же цветов, что и светлый трекер: фон,
        /// табло и заливка кнопок — оттуда же. Заметка на нём не темнее фона,
        /// а светлее: на светлом подложка читается как приподнятая карточка.
        static let day = GuideLook(backdrop: Palette.day.backdrop,
                                   text: Palette.day.text,
                                   muted: designColor(0x6e6e6e),
                                   iconBackground: Palette.day.control,
                                   iconTint: designColor(0x8e8e8e),
                                   noteBackground: designColor(0xffffff),
                                   noteBorder: NSColor.black.withAlphaComponent(0.10))

        static func of(_ skin: Skin) -> GuideLook { skin == .light ? day : night }
    }

    /// Цвета нынешней темы. Вычисляются при каждом обращении: тему меняют на
    /// ходу, и содержимое окна после этого собирается заново (`applyTheme`).
    private static var look: GuideLook { GuideLook.of(Theme.skin) }

    private static var backdropColor: NSColor { look.backdrop }
    private static var textColor: NSColor { look.text }
    private static var mutedColor: NSColor { look.muted }
    private static var iconBackground: NSColor { look.iconBackground }
    private static var iconTint: NSColor { look.iconTint }
    private static var noteBackground: NSColor { look.noteBackground }
    private static var noteBorder: NSColor { look.noteBorder }

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 100),
            // Только .closable, без .miniaturizable и .resizable: у окна ровно
            // один системный крестик — свернуть или растянуть его нельзя.
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Guide"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        applyTheme()
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    /// Пересобирает окно в цветах нынешней темы. Содержимое собирается заново,
    /// а не перекрашивается по частям: цвет здесь попадает в слои и в атрибуты
    /// подписей при сборке, и обойти потом каждое место было бы нечем.
    ///
    /// Тему меняют редко, а гайд всё это время открыт — контроллер живёт один
    /// на всё приложение (см. `openGuide`), и перекрасить его надо на месте.
    func applyTheme() {
        guard let window else { return }
        window.appearance = Theme.skin.appearance
        window.backgroundColor = Self.backdropColor
        let root = Self.buildContent()
        window.contentView = root
        Self.fitWindow(window, to: root)
    }

    /// Подгоняет высоту окна под контент при зафиксированной ширине 500:
    /// ширина стоит явным констрейнтом, высота выводится из остального макета.
    private static func fitWindow(_ window: NSWindow, to root: NSView) {
        root.translatesAutoresizingMaskIntoConstraints = false
        root.widthAnchor.constraint(equalToConstant: contentWidth).isActive = true
        root.layoutSubtreeIfNeeded()
        window.setContentSize(NSSize(width: contentWidth, height: root.fittingSize.height))
    }

    // MARK: - Сборка содержимого

    private static func buildContent() -> NSView {
        let root = NSView()
        root.wantsLayer = true
        root.layer?.backgroundColor = backdropColor.cgColor

        let brand = brandRow()
        let intro = wrappingLabel(
            "25 or 50-minute sessions.\nRest kicks in on its own after each one.",
            font: .systemFont(ofSize: 12.5), color: mutedColor, alignment: .center)

        // Пункты про само окно. Свечение в углу есть только в тёмной теме,
        // но пункт про него стоит в гайде всегда: в светлой теме к нему
        // приписана оговорка — иначе выходит, что приложение умеет меньше,
        // чем умеет, и про клик по табло человек не узнаёт вовсе.
        let glowBody = "Cycles the corner glow — green, purple, blue, red. Just for looks."
        var windowRows: [NSView] = [
            row(symbol: "clock", title: "Tap the time",
                body: Theme.skin == .dark ? glowBody : glowBody + " (Dark theme only.)"),
        ]
        windowRows.append(row(dashesTitle: "Tap the dashes",
            body: "Shows a reset button in place of 25 / 50 — clears the count so far."))
        windowRows.append(row(symbol: "hand.draw", title: "Drag it anywhere",
            body: "Grab any part of the window and move it. Near a screen corner, or the " +
                  "middle of an edge, it snaps flush — under the menu bar or the Dock too."))

        // Пункты про идущий отсчёт. Про паузу текст один на обе темы: серый
        // фон паузы от темы не зависит — как и зелёный фон отдыха.
        let sessionRows = [
            row(symbol: "forward.fill", title: "Finish now",
                body: "Ends the session early — still counts as done."),
            row(symbol: "pause.fill", title: "Pause",
                body: "Stops time, window turns grey. Same button resumes."),
            row(symbol: "stop.fill", title: "Stop",
                body: "Cancels the session, no credit — back to picking a time."),
        ]

        let note = noteBox(
            title: "Break after each session",
            body: "Starts on its own — 5 minutes after 25, 10 minutes after 50. " +
                  "Only Stop works during it.")

        // Черта между «Drag it anywhere» и «Finish now»: выше — про само окно,
        // ниже — про управление отсчётом. По ширине совпадает с пунктами,
        // потому что живёт в той же полноширинной раскладке.
        //
        // Список сверху вниз: пункты с чертой на своём месте. Дальше раскладка
        // работает с этой цепочкой и не знает, где в ней пункт, а где черта, —
        // поэтому пункт, которого в светлой теме нет, ничего в ней не сдвигает.
        let divider = hairline()
        let listBlocks: [NSView] = windowRows + [divider] + sessionRows

        // Полноширинные блоки — подпись, пункты, черта, заметка — все от поля до поля.
        let fullWidth = [intro] + listBlocks + [note]
        for view in fullWidth {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: sidePadding),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -sidePadding),
            ])
        }

        // Лого с «Timato» — единственная строка не во всю ширину, стоит по центру.
        brand.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(brand)

        NSLayoutConstraint.activate([
            brand.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            brand.topAnchor.constraint(equalTo: root.topAnchor, constant: topPadding),

            intro.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 14),
            // Подпись под логотипом отделена от списка сильнее, чем пункты друг
            // от друга: она про приложение целиком, а не про очередную кнопку.
            listBlocks[0].topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 32),
            // Заметка про отдых отбита от списка тем же увеличенным
            // отступом: она не пункт списка, а отдельный блок под ним.
            note.topAnchor.constraint(equalTo: listBlocks[listBlocks.count - 1].bottomAnchor, constant: 34),
            // Последний констрейнт до низа корня — им и определяется итоговая
            // высота окна в `fitWindow`, всё остальное выводится из него вверх по цепочке.
            note.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -bottomPadding),
        ])

        // Пункты списка идут друг за другом с одинаковым шагом — цепочкой,
        // а не перечислением по номерам: пункт добавляют и убирают, и раскладка
        // не должна знать, сколько их сейчас.
        //
        // Черта из этого шага выбивается: вокруг неё по 8 точек сверх обычного
        // отступа. С общим шагом она стоит от соседних пунктов ровно так же,
        // как они друг от друга, и читается очередной строкой списка, а не
        // границей между его частями.
        for (previous, next) in zip(listBlocks, listBlocks.dropFirst()) {
            let touchesDivider = previous === divider || next === divider
            next.topAnchor.constraint(equalTo: previous.bottomAnchor,
                                      constant: touchesDivider ? 24 : 16).isActive = true
        }

        return root
    }

    /// Лого и название в один ряд, по центру, — как в макете.
    private static func brandRow() -> NSView {
        let logo = NSImageView(image: TomatoIcon.templateImage(height: 38))
        logo.contentTintColor = textColor

        let wordmark = NSTextField(labelWithString: "Timato")
        wordmark.font = DisplayFont.of(size: 26)
        wordmark.textColor = textColor

        // Слот высотой в лого держит выравнивание по центру, а надпись внутри
        // него опущена на 4pt: у пиксельного шрифта оптический центр строки
        // чуть выше геометрического, и без этой поправки слово «висит».
        let wordmarkSlot = NSView()
        wordmarkSlot.translatesAutoresizingMaskIntoConstraints = false
        wordmark.translatesAutoresizingMaskIntoConstraints = false
        wordmarkSlot.addSubview(wordmark)
        NSLayoutConstraint.activate([
            wordmark.leadingAnchor.constraint(equalTo: wordmarkSlot.leadingAnchor),
            wordmark.trailingAnchor.constraint(equalTo: wordmarkSlot.trailingAnchor),
            wordmark.centerYAnchor.constraint(equalTo: wordmarkSlot.centerYAnchor, constant: 4),
        ])

        let stack = NSStackView(views: [logo, wordmarkSlot])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10

        // Высоту связываем только теперь: до попадания в стек у view нет общего
        // предка, и AppKit роняет раскладку с «no common ancestor».
        wordmarkSlot.heightAnchor.constraint(equalTo: logo.heightAnchor).isActive = true
        return stack
    }

    /// Разделительная черта в одну точку: разбивает список на смысловые части,
    /// не занимая места, — отступы вокруг задаёт сама раскладка списка.
    private static func hairline() -> NSView {
        let line = NSView()
        line.wantsLayer = true
        line.layer?.backgroundColor = noteBorder.cgColor
        line.translatesAutoresizingMaskIntoConstraints = false
        line.heightAnchor.constraint(equalToConstant: 1).isActive = true
        return line
    }

    /// Подпись, которая переносится по словам в заданную ширину, — вместо
    /// системной однострочной подписи по умолчанию.
    private static func wrappingLabel(_ text: String, font: NSFont, color: NSColor,
                                       alignment: NSTextAlignment = .left,
                                       maxWidth: CGFloat = textWidth) -> NSTextField {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = font
        label.textColor = color
        label.alignment = alignment
        label.preferredMaxLayoutWidth = maxWidth
        return label
    }

    // MARK: - Пункт списка

    private static func row(symbol: String, title: String, body: String) -> NSView {
        let configuration = NSImage.SymbolConfiguration(pointSize: 12.5, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
        let imageView = NSImageView(image: image ?? NSImage())
        imageView.contentTintColor = iconTint
        return row(icon: imageView, title: title, body: body)
    }

    /// Пункт про черточки рисует свою иконку: подходящего значка в SF Symbols нет.
    private static func row(dashesTitle title: String, body: String) -> NSView {
        row(icon: DashesGlyphView(color: iconTint), title: title, body: body)
    }

    private static func row(icon: NSView, title: String, body: String) -> NSView {
        let bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.backgroundColor = iconBackground.cgColor
        bubble.layer?.cornerRadius = 14
        bubble.translatesAutoresizingMaskIntoConstraints = false
        icon.translatesAutoresizingMaskIntoConstraints = false
        bubble.addSubview(icon)
        NSLayoutConstraint.activate([
            bubble.widthAnchor.constraint(equalToConstant: 28),
            bubble.heightAnchor.constraint(equalToConstant: 28),
            icon.centerXAnchor.constraint(equalTo: bubble.centerXAnchor),
            icon.centerYAnchor.constraint(equalTo: bubble.centerYAnchor),
        ])

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        titleLabel.textColor = textColor

        // 28 — кружок иконки, 12 — зазор до текста: столько же занято слева
        // от текстового блока, во столько и сузить перенос его подписи.
        let bodyLabel = wrappingLabel(body, font: .systemFont(ofSize: 12), color: mutedColor,
                                       maxWidth: textWidth - 28 - 12)

        let textStack = NSStackView(views: [titleLabel, bodyLabel])
        textStack.orientation = .vertical
        textStack.alignment = .leading
        textStack.spacing = 3
        textStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView()
        container.addSubview(bubble)
        container.addSubview(textStack)
        NSLayoutConstraint.activate([
            bubble.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            // Кружок на пункт ниже текста — оптически центрует его на первой строке подписи.
            bubble.topAnchor.constraint(equalTo: container.topAnchor, constant: 1),
            textStack.leadingAnchor.constraint(equalTo: bubble.trailingAnchor, constant: 12),
            textStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            textStack.topAnchor.constraint(equalTo: container.topAnchor),
            textStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            container.bottomAnchor.constraint(greaterThanOrEqualTo: bubble.bottomAnchor),
        ])
        return container
    }

    // MARK: - Заметка про отдых

    private static func noteBox(title: String, body: String) -> NSView {
        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = noteBackground.cgColor
        box.layer?.borderColor = noteBorder.cgColor
        box.layer?.borderWidth = 1
        box.layer?.cornerRadius = 8

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12.5, weight: .semibold)
        titleLabel.textColor = textColor

        let bodyLabel = wrappingLabel(body, font: .systemFont(ofSize: 12), color: mutedColor,
                                       maxWidth: textWidth - 14 * 2)

        for label in [titleLabel, bodyLabel] {
            label.translatesAutoresizingMaskIntoConstraints = false
            box.addSubview(label)
        }
        NSLayoutConstraint.activate([
            titleLabel.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 14),
            titleLabel.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -14),
            titleLabel.topAnchor.constraint(equalTo: box.topAnchor, constant: 12),
            bodyLabel.leadingAnchor.constraint(equalTo: titleLabel.leadingAnchor),
            bodyLabel.trailingAnchor.constraint(equalTo: titleLabel.trailingAnchor),
            bodyLabel.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 4),
            bodyLabel.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -12),
        ])
        return box
    }
}

/// Три черточки — та же метафора, что и ряд прогресса на самом отсчёте
/// (`SegmentsView`), но статичная иконка: подходящего значка в SF Symbols нет.
private final class DashesGlyphView: NSView {
    private let color: NSColor

    init(color: NSColor) {
        self.color = color
        super.init(frame: NSRect(x: 0, y: 0, width: 16, height: 12))
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

    override var intrinsicContentSize: NSSize { NSSize(width: 16, height: 12) }

    override func draw(_ dirtyRect: NSRect) {
        color.setFill()
        let width: CGFloat = 4, gap: CGFloat = 2, height: CGFloat = 2
        let y = bounds.midY - height / 2
        for index in 0..<3 {
            let x = CGFloat(index) * (width + gap)
            let dash = NSRect(x: x, y: y, width: width, height: height)
            NSBezierPath(roundedRect: dash, xRadius: height / 2, yRadius: height / 2).fill()
        }
    }
}
