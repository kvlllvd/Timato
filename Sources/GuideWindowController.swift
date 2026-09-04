import AppKit

/// Окно «Гайд»: короткое объяснение того, как устроен Pimer, — отдельный
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

    private static let textColor = Palette.focus.text
    private static let mutedColor = designColor(0x9a9a9a)
    private static let iconBackground = Palette.focus.control
    /// Светлее, чем `Palette.focus.iconIdle`: там приглушённый цвет — подсказка,
    /// что кнопку ещё не навели, здесь иконки не интерактивны и должны читаться сразу.
    private static let iconTint = designColor(0xcfcfcf)
    private static let noteBackground = designColor(0x171717)
    private static let noteBorder = NSColor.white.withAlphaComponent(0.14)

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: Self.contentWidth, height: 100),
            // Только .closable, без .miniaturizable и .resizable: у окна ровно
            // один системный крестик — свернуть или растянуть его нельзя.
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Guide"
        window.appearance = NSAppearance(named: .darkAqua)
        window.backgroundColor = .black
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let root = Self.buildContent()
        window.contentView = root
        Self.fitWindow(window, to: root)
    }

    required init?(coder: NSCoder) { fatalError("не используется") }

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
        root.layer?.backgroundColor = Palette.focus.backdrop.cgColor

        let brand = brandRow()
        let intro = wrappingLabel(
            "25 or 55-minute sessions.\nRest kicks in on its own after each one.",
            font: .systemFont(ofSize: 12.5), color: mutedColor, alignment: .center)

        let rows = [
            row(symbol: "clock", title: "Tap the time",
                body: "Cycles the corner glow — red, green, purple, blue. Just for looks."),
            row(dashesTitle: "Tap the dashes",
                body: "Shows a reset button in place of 25 / 55 — clears the count so far."),
            row(symbol: "forward.fill", title: "Finish now",
                body: "Ends the session early — still counts as done."),
            row(symbol: "pause.fill", title: "Pause",
                body: "Stops time, window turns grey. Same button resumes."),
            row(symbol: "stop.fill", title: "Stop",
                body: "Cancels the session, no credit — back to picking a time."),
        ]

        let note = noteBox(
            title: "5-minute break",
            body: "Starts on its own after each session — enough to reset before " +
                  "the next one. Only Stop works during it.")

        // Полноширинные блоки — подпись, пункты, заметка — все от поля до поля.
        let fullWidth = [intro] + rows + [note]
        for view in fullWidth {
            view.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(view)
            NSLayoutConstraint.activate([
                view.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: sidePadding),
                view.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -sidePadding),
            ])
        }

        // Лого с «Pimer» — единственная строка не во всю ширину, стоит по центру.
        brand.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(brand)

        NSLayoutConstraint.activate([
            brand.centerXAnchor.constraint(equalTo: root.centerXAnchor),
            brand.topAnchor.constraint(equalTo: root.topAnchor, constant: topPadding),

            intro.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 14),
            rows[0].topAnchor.constraint(equalTo: intro.bottomAnchor, constant: 16),
            rows[1].topAnchor.constraint(equalTo: rows[0].bottomAnchor, constant: 16),
            rows[2].topAnchor.constraint(equalTo: rows[1].bottomAnchor, constant: 16),
            rows[3].topAnchor.constraint(equalTo: rows[2].bottomAnchor, constant: 16),
            rows[4].topAnchor.constraint(equalTo: rows[3].bottomAnchor, constant: 16),
            note.topAnchor.constraint(equalTo: rows[4].bottomAnchor, constant: 18),
            // Последний констрейнт до низа корня — им и определяется итоговая
            // высота окна в `fitWindow`, всё остальное выводится из него вверх по цепочке.
            note.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -bottomPadding),
        ])

        return root
    }

    /// Лого и название в один ряд, по центру, — как в макете.
    private static func brandRow() -> NSView {
        let logo = NSImageView(image: TomatoIcon.templateImage(height: 38))
        logo.contentTintColor = textColor

        let wordmark = NSTextField(labelWithString: "Pimer")
        wordmark.font = DisplayFont.of(size: 26)
        wordmark.textColor = textColor

        let stack = NSStackView(views: [logo, wordmark])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 10
        return stack
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

    // MARK: - Заметка про пятиминутку

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
