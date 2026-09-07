import AppKit

/// Во что тема разрешается на самом деле: раскраска окна бывает ровно двух
/// видов, а тем в меню три — «System» сама по себе цвета не задаёт.
enum Skin {
    case light, dark

    /// Какая раскраска у системы прямо сейчас.
    ///
    /// Спрашиваем `NSApp.effectiveAppearance`, а не `AppleInterfaceStyle` из
    /// настроек: приложение не переопределяет свою тему целиком (свою тему
    /// каждое окно получает от `Skin.appearance`), поэтому у самого приложения
    /// эффективная тема так и остаётся системной — и заодно учитывает ночной
    /// автоматический переход, которого в настройках не видно.
    static var system: Skin {
        NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
    }

    /// Системная тема для окон этой раскраски. Нужна не цветам — их окно
    /// красит само, — а системной обвязке: полосе заголовка «Гайда» и
    /// всплывающим меню.
    var appearance: NSAppearance? {
        NSAppearance(named: self == .dark ? .darkAqua : .aqua)
    }
}

/// Тема оформления: пункт меню помидора, всегда выбран ровно один.
///
/// Порядок случаев — порядок пунктов в меню.
enum Theme: String, CaseIterable {
    case light, dark, system

    /// Тема при первом запуске: как у системы. Приложение живёт поверх всех
    /// окон и должно быть светлым или тёмным вместе с ними, а не наперекор.
    static let `default` = Theme.system

    /// Ключ в настройках. Тема — выбор надолго, и переживает перезапуск,
    /// в отличие от вида трекера и цвета свечения.
    private static let key = "TimatoTheme"

    /// Выбранная тема. Запись сохраняет её и оповещает окна — единственный
    /// путь смены темы, поэтому окно, гайд и галочки в меню не расходятся.
    static var current: Theme = read() {
        didSet {
            guard current != oldValue else { return }
            UserDefaults.standard.set(current.rawValue, forKey: key)
            NotificationCenter.default.post(name: .themeDidChange, object: nil)
        }
    }

    private static func read() -> Theme {
        UserDefaults.standard.string(forKey: key).flatMap(Theme.init(rawValue:)) ?? `default`
    }

    /// Раскраска, в которой рисуется интерфейс прямо сейчас.
    static var skin: Skin { current.skin }

    var skin: Skin {
        switch self {
        case .light:  return .light
        case .dark:   return .dark
        case .system: return Skin.system
        }
    }

    /// Заголовок пункта меню.
    var title: String {
        switch self {
        case .light:  return "Light"
        case .dark:   return "Dark"
        case .system: return "System"
        }
    }
}

extension Notification.Name {
    /// Тему сменили — окнам пора перекраситься. Приходит и когда переключили
    /// пункт меню, и когда при теме «System» переключилась сама система.
    static let themeDidChange = Notification.Name("TimatoThemeDidChange")
}
