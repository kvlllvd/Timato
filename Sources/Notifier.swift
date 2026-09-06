import AppKit
import AVFoundation
import UserNotifications

/// Звонок и уведомление по окончании отсчёта.
///
/// Уведомление требует, чтобы приложение было бандлом с идентификатором — поэтому
/// сборка обязательно подписывается ad-hoc. Если разрешения нет, звонок всё равно
/// звучит: узнать об окончании пользователь должен в любом случае.
enum Notifier {

    private static let presenter = BannerPresenter()

    /// Выключён ли звонок. Переключается пунктом «Mute» в меню помидора.
    /// Живёт только в памяти, как и итог за сеанс: после `Quit` звук снова включён.
    /// Баннер уведомления при этом остаётся — молчит именно звонок.
    ///
    /// Стартовое положение можно приглушить переменной окружения `PIMER_MUTE=1`:
    /// при разработке приложение запускают десятками раз подряд, и звонок из
    /// фона бьёт по ушам. Обычный запуск переменной не видит — там звук включён.
    static var isMuted = ProcessInfo.processInfo.environment["PIMER_MUTE"] == "1"

    /// Готовит звонок заранее, ещё до первого отсчёта.
    ///
    /// Без этого первый же звонок поднимал звуковой движок прямо на главном
    /// потоке — а звонит он ровно в момент перехода «работа → отдых», и переход
    /// на нём подвисал. Один раз за запуск, дальше движок уже поднят.
    static func prewarm() {
        Chime.prewarm()
    }

    static func requestPermissionIfPossible() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        let center = UNUserNotificationCenter.current()
        // Без делегата macOS прячет баннер, пока приложение впереди, — а окно
        // висит поверх всех окон, то есть впереди оно почти всегда.
        center.delegate = presenter
        center.requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    /// Звонит и показывает баннер. Вызывается ровно один раз на завершённый таймер.
    /// `overdue` — на сколько секунд звонок опоздал, если машина спала.
    static func fire(minutes: Int, kind: Kind, overdue: TimeInterval) {
        if !isMuted { Chime.play(kind: kind) }
        // .criticalRequest прыгал бы в доке бесконечно; одного прыжка достаточно.
        NSApp.requestUserAttention(.informationalRequest)

        guard Bundle.main.bundleIdentifier != nil else { return }
        let content = UNMutableNotificationContent()
        content.title = kind == .focus ? "Time for a break" : "Break is over"
        var body = kind == .focus
            ? "\(minutes) min done — \(Presets.rest) min break started"
            : "\(minutes) min break finished"
        // Честно говорим, что звонок задним числом: таймер дошёл до нуля во сне.
        if let late = lateSuffix(overdue) { body += " · \(late)" }
        content.body = body
        // Свой звонок уже прозвучал; системное «дзынь» баннера только смазало бы его.
        content.sound = nil
        let request = UNNotificationRequest(
            identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }

    /// Опоздание меньше полутора минут — обычная работа, о нём молчим.
    static func lateSuffix(_ overdue: TimeInterval) -> String? {
        guard overdue >= 90 else { return nil }
        let minutes = Int((overdue / 60).rounded())
        if minutes < 60 { return "finished \(minutes) min ago" }
        let hours = Double(minutes) / 60
        return String(format: "finished %.1f h ago", hours)
    }
}

/// Показывает баннер, даже когда приложение активно.
final class BannerPresenter: NSObject, UNUserNotificationCenterDelegate {
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}

// MARK: - Звонок

/// Звонок окончания: не системное «дзынь», а синтезированный аккорд-арпеджио —
/// его слышно из другой комнаты и он звучит как «сделано», а не как ошибка.
///
/// Звук считается сэмплами и играется через AVAudioEngine, потому что у
/// системных звуков нет ни высоты, ни громкости: сделать «ярче и позитивнее»
/// из готового файла нельзя, только сыграть его громче или чаще.
enum Chime {

    /// Мажорное арпеджио вверх — C6 · E6 · G6 · C7. Восходящий мажор и есть
    /// то самое «позитивно»: слух читает его как завершение, а не как сигнал.
    private static let focusNotes: [Double] = [1046.50, 1318.51, 1567.98, 2093.00]
    /// Конец отдыха — короче и ниже: это приглашение вернуться, а не награда.
    private static let restNotes: [Double] = [783.99, 1046.50]

    private static let sampleRate: Double = 44_100
    /// Пауза между вступлениями нот арпеджио.
    private static let noteStep: Double = 0.085
    /// Сколько звучит одна нота с учётом затухания.
    private static let noteTail: Double = 1.1

    /// Своя очередь на всё, что делает звонок. Подъём звукового движка стоит
    /// около двухсот миллисекунд — он открывает устройство вывода, — а синтез
    /// буфера ещё десяток. На главном потоке это была видимая задержка ровно
    /// там, где её замечаешь: звонок звучит в момент перехода «работа → отдых»,
    /// и первый переход подвисал, а все следующие шли быстро.
    ///
    /// Очередь заодно и защищает состояние ниже: трогают его только отсюда.
    private static let queue = DispatchQueue(label: "com.dkovalev.pimer.chime",
                                             qos: .userInitiated)

    /// Движок и узел живут статически: локальные умолкают вместе с уходом
    /// из функции — буфер обрывается на первой же ноте.
    private static var engine: AVAudioEngine?
    private static var player: AVAudioPlayerNode?
    /// Готовые буферы обоих звонков. Синтез не зависит ни от чего, кроме вида
    /// отсчёта, — считать его заново на каждый звонок незачем.
    private static var buffers: [Kind: AVAudioPCMBuffer] = [:]

    private static let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate,
                                              channels: 1)

    /// Поднимает движок и считает оба буфера заранее, в стороне от главного потока.
    static func prewarm() {
        queue.async {
            _ = readyPlayer()
            for kind in [Kind.focus, .rest] { _ = readyBuffer(kind: kind) }
        }
    }

    static func play(kind: Kind) {
        queue.async {
            guard let buffer = readyBuffer(kind: kind), let player = readyPlayer() else {
                NSSound.beep()
                return
            }
            player.stop()
            player.play()
            player.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
        }
    }

    #if LIVE_CHECK
    /// Звучит ли звонок прямо сейчас. Только для живой проверки: звонок теперь
    /// уходит на свою очередь, и что он вообще звучит, иначе ничем не видно.
    static var isSounding: Bool { queue.sync { player?.isPlaying ?? false } }
    #endif

    /// Поднимает движок один раз и возвращает готовый к работе узел.
    private static func readyPlayer() -> AVAudioPlayerNode? {
        dispatchPrecondition(condition: .onQueue(queue))
        if let engine, let player, engine.isRunning { return player }
        guard let format else { return nil }
        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        engine.connect(player, to: engine.mainMixerNode, format: format)
        do { try engine.start() } catch { return nil }
        Self.engine = engine
        Self.player = player
        return player
    }

    /// Синтезирует буфер один раз на вид отсчёта и держит его дальше.
    private static func readyBuffer(kind: Kind) -> AVAudioPCMBuffer? {
        dispatchPrecondition(condition: .onQueue(queue))
        if let ready = buffers[kind] { return ready }
        guard let format,
              let made = makeBuffer(notes: kind == .focus ? focusNotes : restNotes,
                                    format: format) else { return nil }
        buffers[kind] = made
        return made
    }

    /// Синтезирует арпеджио. Каждая нота — основной тон плюс тихая октава
    /// сверху и экспоненциальное затухание: так получается колокольчик, а не
    /// писк генератора. Атака смягчена, иначе на старте ноты слышен щелчок.
    private static func makeBuffer(notes: [Double], format: AVAudioFormat) -> AVAudioPCMBuffer? {
        let seconds = Double(notes.count - 1) * noteStep + noteTail
        let frames = AVAudioFrameCount(seconds * sampleRate)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames),
              let samples = buffer.floatChannelData?[0] else { return nil }
        buffer.frameLength = frames

        for index in 0..<Int(frames) { samples[index] = 0 }

        for (order, frequency) in notes.enumerated() {
            let offset = Int(Double(order) * noteStep * sampleRate)
            let length = min(Int(noteTail * sampleRate), Int(frames) - offset)
            guard length > 0 else { continue }
            for frame in 0..<length {
                let t = Double(frame) / sampleRate
                let decay = exp(-t / 0.42)
                let attack = min(1, t / 0.004)
                let tone = sin(2 * .pi * frequency * t)
                    + 0.28 * sin(4 * .pi * frequency * t)
                samples[offset + frame] += Float(tone * decay * attack * 0.22)
            }
        }

        // Мягкий предел вместо обрезки: сложенные ноты местами вылезают за 1.0.
        for index in 0..<Int(frames) { samples[index] = tanhf(samples[index]) }
        return buffer
    }
}
