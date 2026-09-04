import AppKit

/// Шрифт табло и кнопок — точечный `Nothing Font (5x7)` из макета.
///
/// Лежит в бандле и регистрируется на старте: полагаться на то, что шрифт
/// установлен в системе, нельзя — на чужой машине приложение осталось бы
/// без него, и цифры молча поехали бы системным шрифтом.
enum DisplayFont {

    /// PostScript-имя внутри файла — именно по нему шрифт ищется после регистрации.
    private static let postScriptName = "NothingFont5x7"
    private static let resource = "NothingFont5x7"

    /// Ставит шрифт в текущий процесс. Вызывать до сборки интерфейса.
    /// Второй вызов системе безвреден: она вернёт ошибку «уже зарегистрирован».
    static func register() {
        guard let url = Bundle.main.url(forResource: resource, withExtension: "otf") else { return }
        CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
    }

    /// Шрифт нужного кегля. Если файла в бандле нет, отдаём системный с
    /// моноширинными цифрами: табло не должно дёргаться на смене разряда.
    static func of(size: CGFloat) -> NSFont {
        NSFont(name: postScriptName, size: size)
            ?? .monospacedDigitSystemFont(ofSize: size, weight: .medium)
    }
}
