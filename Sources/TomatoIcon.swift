import AppKit

/// Иконка приложения — помидор из макета. Рисунок лежит одним файлом
/// `Resources/Tomato.png`: чернила рисунка непрозрачны, фон прозрачен.
/// Из него делаются обе иконки — и в доке, и в строке меню.
enum TomatoIcon {

    private static let resource = "Tomato"

    /// Где взять рисунок. В приложении — из бандла; при сборке иконки
    /// (`MakeIcon`) бандла нет, поэтому путь передаётся снаружи.
    static var artworkURL: URL? = Bundle.main.url(forResource: resource, withExtension: "png")

    private static var artwork: NSImage? {
        guard let artworkURL else { return nil }
        return NSImage(contentsOf: artworkURL)
    }

    /// Иконка приложения в квадрате `size`×`size`: помидор на белой плашке.
    /// Плашка нужна, потому что рисунок чёрный: без неё иконка пропадала бы
    /// на тёмном фоне дока и в тёмном окне образа.
    static func draw(size: CGFloat) {
        let plate = NSRect(x: 0, y: 0, width: size, height: size)
        NSColor.white.setFill()
        // Скругление как у приложений macOS — примерно пятая часть стороны.
        NSBezierPath(roundedRect: plate, xRadius: size * 0.22, yRadius: size * 0.22).fill()

        guard let artwork, artwork.size.height > 0 else { return }
        let scale = min(size * 0.68 / artwork.size.width, size * 0.68 / artwork.size.height)
        let box = NSRect(x: (size - artwork.size.width * scale) / 2,
                         y: (size - artwork.size.height * scale) / 2,
                         width: artwork.size.width * scale,
                         height: artwork.size.height * scale)

        // Без сглаживания: рисунок пиксельный, и мягкие края превращают его в кляксу.
        // Тонировать нечем и незачем — чернила в файле уже чёрные.
        NSGraphicsContext.current?.imageInterpolation = .none
        artwork.draw(in: box)
    }

    /// Тот же рисунок произвольного роста, помеченный шаблонным — система сама
    /// подбирает ему цвет под фон: белым в тёмной строке меню, чёрным в светлой.
    static func templateImage(height: CGFloat) -> NSImage {
        guard let image = artwork, image.size.height > 0 else {
            // Пустая картинка лучше, чем пропавший пункт: по нему открывается окно.
            let blank = NSImage(size: NSSize(width: height, height: height))
            blank.isTemplate = true
            return blank
        }
        image.size = NSSize(width: (image.size.width / image.size.height * height).rounded(),
                            height: height)
        image.isTemplate = true
        return image
    }

    /// Готовая картинка для строки меню.
    static func statusBarImage() -> NSImage { templateImage(height: 18) }
}
