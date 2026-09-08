import AppKit

/// Что за сборка сейчас запущена, куда идти за новой и куда писать о том, что
/// не так.
///
/// Обе дороги наружу — ссылки в браузер, а не сетевые запросы из приложения.
/// У Timato в обещании стоит «без сети», и проверка обновлений внутри ради
/// одной строки «доступна 1.1» это обещание отменяла бы: страницу релизов
/// человек и так прочтёт лучше, чем окно с одной строкой. Поэтому пункт меню
/// не «проверить», а «открыть», и версию он называет сам — сравнить её с той,
/// что на странице, дешевле, чем ходить в сеть за тем же ответом.
enum Release {
    /// Репозиторий проекта: и дом обновлений, и место, куда приходят отзывы.
    private static let repo = "https://github.com/kvlllvd/Timato"

    /// Страница последнего релиза. Именно `latest`, а не конкретный тег: она
    /// остаётся верной и через год, когда версий станет десяток.
    static var latest: String { repo + "/releases/latest" }

    /// Версия сборки — та, что стояла в файле `VERSION`, когда её собирали.
    /// Вне бандла (запуск исполняемого файла руками) ключа нет, и версия
    /// честно называет себя несобранной, а не притворяется единицей.
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Номер сборки и коммит. В номере версии их нет, а для разбора отзыва они
    /// и есть главное: между двумя сборками «1.0» лежит сколько угодно правок,
    /// и без коммита непонятно, в какой из них смотреть.
    private static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    private static var commit: String {
        Bundle.main.object(forInfoDictionaryKey: "TimatoCommit") as? String ?? "unknown"
    }

    /// «1.0 (42, a1b2c3d)» — то, что уходит в форму отзыва одной строкой.
    static var stamp: String { "\(version) (\(build), \(commit))" }

    /// Система и срез, на котором приложение сейчас работает. Срез берётся из
    /// самой сборки, а не из машины: бандл universal, и вопрос в отзыве всегда
    /// про то, какой из двух срезов запустился, — на Apple Silicon может
    /// работать и x86_64 под Rosetta.
    static var system: String {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var number = "\(os.majorVersion).\(os.minorVersion)"
        if os.patchVersion != 0 { number += ".\(os.patchVersion)" }
        #if arch(arm64)
        let slice = "Apple Silicon"
        #else
        let slice = "Intel"
        #endif
        return "macOS \(number), \(slice)"
    }

    /// Форма отзыва с уже подставленными версией и системой. Подставляет их
    /// приложение, а не человек: он их не знает наизусть, а без них отзыв
    /// «у меня не так» не привязать ни к сборке, ни к машине.
    ///
    /// Имена параметров — это `id` полей формы
    /// (`.github/ISSUE_TEMPLATE/feedback.yml`): GitHub заполняет поля по ним.
    /// Переименуете поле там — подстановка тихо перестанет работать, форма
    /// при этом откроется как ни в чём не бывало.
    static var feedback: String {
        var components = URLComponents(string: repo + "/issues/new")
        components?.queryItems = [
            URLQueryItem(name: "template", value: "feedback.yml"),
            URLQueryItem(name: "version", value: stamp),
            URLQueryItem(name: "system", value: system),
        ]
        return components?.url?.absoluteString ?? repo + "/issues/new"
    }

    /// Открывает адрес в браузере. Единственное место, где строка становится
    /// `URL`, — чтобы разбор адреса не расползался по вызовам.
    static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }
}
