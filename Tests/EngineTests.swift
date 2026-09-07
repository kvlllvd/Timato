import Foundation

// Мини-раннер: без XCTest, потому что полного Xcode на машине нет.
// Каждая проверка названа номером acceptance criteria, из которого выведена.

private var failures: [String] = []
private var passed = 0

private func check(_ id: String, _ what: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
    if ok {
        passed += 1
        print("  ✓ \(id) \(what)")
    } else {
        let d = detail()
        failures.append("\(id) \(what)\(d.isEmpty ? "" : " — \(d)")")
        print("  ✗ \(id) \(what)\(d.isEmpty ? "" : " — \(d)")")
    }
}

/// Подменяемые часы: тест двигает время вручную, ничего не ждёт.
/// Секунды, а не `Date`: ядро считает по монотонным часам, у которых нет даты.
private final class FakeClock {
    var now: TimeInterval = 10_000
    func advance(_ seconds: TimeInterval) { now += seconds }
}

@main
enum EngineTests {
    static func main() {
        print("\nФаза 1 — ядро отсчёта")

        // --- Ф1.1 --- старт и убывание остатка
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            e.start(seconds: 300)
            check("Ф1.1", "сразу после старта остаток равен длительности",
                  e.remaining == 300, "получено \(e.remaining)")
            clock.advance(30)
            check("Ф1.1", "через 30 с остаток ровно N−30",
                  e.remaining == 270, "получено \(e.remaining)")
            check("Ф1.1", "состояние running", e.state == .running, "получено \(e.state)")
        }

        // --- Ф1.1 --- отсчёт не накапливает ошибку на длинной дистанции
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            e.start(seconds: 55 * 60)
            for _ in 0..<3300 { clock.advance(1); e.tick() }   // 50 минут по секунде
            check("Ф1.1", "после 3300 тиков по секунде остаток ровно 0",
                  e.remaining == 0, "получено \(e.remaining)")
        }

        // --- Ф1.2 --- пауза и продолжение
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            e.start(seconds: 1500)
            clock.advance(200)                    // осталось 1300
            e.pause()
            check("Ф1.2", "пауза переводит в состояние paused", e.state == .paused)
            check("Ф1.2", "пауза фиксирует остаток", e.remaining == 1300, "получено \(e.remaining)")
            clock.advance(60)                     // минута реального времени на паузе
            check("Ф1.2", "спустя 60 с на паузе остаток не изменился",
                  e.remaining == 1300, "получено \(e.remaining)")
            e.resume()
            check("Ф1.2", "продолжение возобновляет с той же точки",
                  e.remaining == 1300, "получено \(e.remaining)")
            clock.advance(300)
            check("Ф1.2", "после продолжения отсчёт идёт дальше",
                  e.remaining == 1000, "получено \(e.remaining)")
        }

        // --- Ф1.2 --- сон машины не ломает отсчёт
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            e.start(seconds: 1500)
            clock.advance(3600)                   // крышку закрыли на час, тиков не было
            check("Ф1.2", "после часового простоя остаток 0, а не отрицательный",
                  e.remaining == 0, "получено \(e.remaining)")
        }

        // --- Ф1.3 --- сброс
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            e.start(seconds: 1500)
            clock.advance(400)
            e.reset()
            check("Ф1.3", "сброс переводит в состояние idle", e.state == .idle, "получено \(e.state)")
            check("Ф1.3", "сброс возвращает исходную длительность",
                  e.remaining == 1500, "получено \(e.remaining)")
            clock.advance(100)
            check("Ф1.3", "после сброса время не убывает",
                  e.remaining == 1500, "получено \(e.remaining)")
        }

        // --- формат ---
        do {
            check("Ф1.1", "формат 25:00 на старте 1500 с", formatRemaining(1500) == "25:00",
                  formatRemaining(1500))
            check("Ф1.1", "формат 05:00", formatRemaining(300) == "05:00", formatRemaining(300))
            check("Ф1.1", "формат 55:00", formatRemaining(3300) == "55:00", formatRemaining(3300))
            check("Ф1.1", "формат 00:00 на нуле", formatRemaining(0) == "00:00", formatRemaining(0))
            check("Ф1.1", "дробный остаток округляется вверх",
                  formatRemaining(59.4) == "01:00", formatRemaining(59.4))
        }

        print("\nФаза 2 — интерфейс и завершение")

        // --- Ф2.1 --- три пресета
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            for minutes in Presets.minutes {
                e.reset()
                e.start(seconds: TimeInterval(minutes * 60))
                check("Ф2.1", "пресет \(minutes) стартует с \(minutes):00",
                      e.isRunning && e.remaining == TimeInterval(minutes * 60),
                      "получено \(e.remaining) состояние \(e.state)")
            }
        }

        // --- Ф2.2 --- какой экран показан: при открытии и после звонка ровно два варианта
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })

            check("Ф2.2", "при открытии показан экран выбора",
                  Screen.forState(e.state) == .choice(options: [25, 50]),
                  "получено \(Screen.forState(e.state))")
            check("Ф2.2", "при открытии вариантов ровно два",
                  Screen.forState(e.state).options.count == 2,
                  "получено \(Screen.forState(e.state).options)")

            e.start(seconds: 5)
            check("Ф2.2", "во время отсчёта экран выбора скрыт",
                  Screen.forState(e.state) == .countdown, "получено \(Screen.forState(e.state))")
            e.pause()
            check("Ф2.2", "на паузе экран выбора тоже скрыт",
                  Screen.forState(e.state) == .countdown, "получено \(Screen.forState(e.state))")
            e.resume()

            clock.advance(10); e.tick()
            check("Ф2.2", "сразу после звонка снова показан экран выбора",
                  Screen.forState(e.state) == .choice(options: [25, 50]),
                  "получено \(Screen.forState(e.state))")
            check("Ф2.2", "после звонка вариантов ровно два, те же самые",
                  Screen.forState(e.state).options == [25, 50],
                  "получено \(Screen.forState(e.state).options)")

            e.reset()
            check("Ф2.2", "после сброса показан экран выбора",
                  Screen.forState(e.state) == .choice(options: [25, 50]),
                  "получено \(Screen.forState(e.state))")
        }

        // --- Ф2.3 --- завершение ровно один раз
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            var finishCount = 0
            e.onFinish = { _ in finishCount += 1 }
            e.start(seconds: 5)
            for _ in 0..<4 { clock.advance(1); e.tick() }
            check("Ф2.3", "до нуля обработчик не вызывается", finishCount == 0, "вызван \(finishCount) раз")
            clock.advance(1); e.tick()
            check("Ф2.3", "на нуле обработчик вызван один раз", finishCount == 1, "вызван \(finishCount) раз")
            check("Ф2.3", "состояние finished", e.state == .finished, "получено \(e.state)")
            for _ in 0..<20 { clock.advance(1); e.tick() }
            check("Ф2.3", "дальнейшие тики обработчик не вызывают", finishCount == 1, "вызван \(finishCount) раз")
        }

        // --- Ф2.3 --- защита от бессмысленного запуска
        do {
            let e = TimerEngine()
            e.start(seconds: 0)
            check("Ф2.3", "нулевая длительность отсчёт не запускает", !e.isRunning, "\(e.state)")
            e.start(seconds: -10)
            check("Ф2.3", "отрицательная длительность отсчёт не запускает", !e.isRunning, "\(e.state)")
        }

        // --- пауза и продолжение вне своих состояний ничего не ломают ---
        do {
            let e = TimerEngine(duration: 300)
            e.pause()
            check("Ф1.2", "пауза в idle ничего не меняет", e.state == .idle, "\(e.state)")
            e.resume()
            check("Ф1.2", "продолжение в idle ничего не меняет", e.state == .idle, "\(e.state)")
        }

        // --- полоса прогресса: залито прошедшее время ---
        do {
            check("Д3", "на старте полоса пустая", elapsedFraction(remaining: 300, duration: 300) == 0)
            check("Д3", "половина прошла — половина полосы", elapsedFraction(remaining: 150, duration: 300) == 0.5)
            check("Д3", "остаток ноль — полоса заполнена", elapsedFraction(remaining: 0, duration: 300) == 1)
            check("Д3", "остаток больше длительности не уходит ниже 0", elapsedFraction(remaining: 400, duration: 300) == 0)
            check("Д3", "нулевая длительность не делит на ноль", elapsedFraction(remaining: 10, duration: 0) == 0)
        }

        // --- работа и отдых ---
        do {
            check("Д1", "25 минут — работа", Kind.forMinutes(25) == .focus)
            check("Д1", "50 минут — работа", Kind.forMinutes(50) == .focus)
            check("Д1", "5 минут — отдых", Kind.forMinutes(5) == .rest)
            check("Д1", "10 минут — отдых", Kind.forMinutes(10) == .rest)
            check("Д1", "после 25 минут сам включается отдых", nextAfterFinish(minutes: 25) == 5)
            check("Д1", "после 50 минут сам включается отдых на 10", nextAfterFinish(minutes: 50) == 10)
            check("Д1", "после отдыха ничего не запускается", nextAfterFinish(minutes: 5) == nil)
            check("Д1", "после десятиминутки ничего не запускается", nextAfterFinish(minutes: 10) == nil)
        }

        // --- черточки: всегда четыре, счёт в половинках ---
        do {
            check("Д2", "черточек всегда четыре", Presets.segments == 4)
            check("Д2", "ёмкость ряда — восемь половинок", Segments.capacity == 8)

            check("Д2", "25 минут закрашивают половину", Segments.credit(minutes: 25) == 1)
            check("Д2", "50 минут закрашивают целую", Segments.credit(minutes: 50) == 2)
            check("Д2", "отдых не закрашивает ничего", Segments.credit(minutes: 5) == 0)

            check("Д2", "две сессии по 25 — одна целая черточка",
                  Segments.advance(Segments.advance(0, minutes: 25), minutes: 25) == 2)
            check("Д2", "отдых ряд не двигает", Segments.advance(3, minutes: 5) == 3)

            // Полный ряд стоит на экране до конца следующего отрезка, и уже тот
            // начинает его заново — иначе четыре закрашенные черточки не увидеть.
            check("Д2", "четыре по 50 заполняют ряд целиком",
                  (0..<4).reduce(0) { row, _ in Segments.advance(row, minutes: 50) } == 8)
            check("Д2", "после полного ряда следующие 50 начинают ряд заново",
                  Segments.advance(8, minutes: 50) == 2)
            check("Д2", "после полного ряда следующие 25 дают половину",
                  Segments.advance(8, minutes: 25) == 1)
            check("Д2", "ряд не переполняется", Segments.advance(7, minutes: 50) == 8)

            check("Д2", "на пустом ряду первая черточка пуста",
                  segmentFill(index: 0, filledHalves: 0) == 0)
            check("Д2", "одна сессия 25 — первая черточка наполовину",
                  segmentFill(index: 0, filledHalves: 1) == 0.5)
            check("Д2", "одна сессия 50 — первая черточка целиком",
                  segmentFill(index: 0, filledHalves: 2) == 1)
            check("Д2", "вторая черточка ждёт своей очереди",
                  segmentFill(index: 1, filledHalves: 2) == 0)
            check("Д2", "полный ряд закрашен весь",
                  (0..<4).allSatisfy { segmentFill(index: $0, filledHalves: 8) == 1 })
        }

        // --- цвет свечения: клик по табло перебирает четыре по кругу ---
        do {
            check("Д7", "по умолчанию красный", Accent.red.next == .green)
            check("Д7", "зелёный → фиолетовый", Accent.green.next == .purple)
            check("Д7", "фиолетовый → синий", Accent.purple.next == .blue)
            check("Д7", "синий → снова красный", Accent.blue.next == .red)
        }

        print("\nПравки после злого разбора")

        // --- находка 2 --- монотонные часы: скачок системного времени не при чём
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            e.start(seconds: 1500)
            clock.advance(120)
            let before = e.remaining
            // Монотонный источник по определению не знает о переводе часов:
            // проверяем, что ядро вообще не обращается ни к какой дате.
            check("Р2", "остаток зависит только от монотонного источника",
                  before == 1380, "получено \(before)")
            for _ in 0..<10 { e.tick() }
            check("Р2", "тики без движения времени остаток не меняют",
                  e.remaining == before, "получено \(e.remaining)")
            check("Р2", "боевой источник времени монотонный и растёт",
                  monotonicSeconds() > 0 && monotonicSeconds() <= monotonicSeconds())
        }

        // --- находка 9 --- пауза ровно на нуле не вешает таймер
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            var finished = 0
            e.onFinish = { _ in finished += 1 }
            e.start(seconds: 5)
            clock.advance(5)                       // остаток ровно 0, тика ещё не было
            e.pause()
            check("Р9", "пауза ровно на нуле игнорируется",
                  e.state == .running, "получено \(e.state)")
            e.tick()
            check("Р9", "таймер всё-таки дозванивает", finished == 1, "вызван \(finished) раз")
        }

        // --- находка 9 --- продолжение с нулевого остатка тоже дозванивает
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            var finished = 0
            e.onFinish = { _ in finished += 1 }
            e.start(seconds: 60)
            clock.advance(59.9)
            e.pause()
            check("Р9", "пауза почти на нуле проходит", e.state == .paused, "получено \(e.state)")
            e.resume()
            clock.advance(1)
            e.tick()
            check("Р9", "после продолжения таймер дозванивает", finished == 1, "вызван \(finished) раз")
        }

        // --- находка 11 --- звонок задним числом сообщает о просрочке
        do {
            let clock = FakeClock()
            let e = TimerEngine(now: { clock.now })
            var overdue: TimeInterval = -1
            e.onFinish = { overdue = $0 }
            e.start(seconds: 1500)
            clock.advance(1500)
            e.tick()
            check("Р11", "звонок вовремя — просрочки нет", overdue == 0, "получено \(overdue)")

            let clock2 = FakeClock()
            let e2 = TimerEngine(now: { clock2.now })
            var overdue2: TimeInterval = -1
            e2.onFinish = { overdue2 = $0 }
            e2.start(seconds: 1500)
            clock2.advance(1500 + 3 * 3600)        // крышку закрыли на три часа
            e2.tick()
            check("Р11", "после сна просрочка равна проспанному времени",
                  overdue2 == 3 * 3600, "получено \(overdue2)")
            check("Р11", "короткая задержка о просрочке молчит",
                  Notifier.lateSuffix(30) == nil, "получено \(String(describing: Notifier.lateSuffix(30)))")
            check("Р11", "часы просрочки попадают в текст уведомления",
                  Notifier.lateSuffix(3 * 3600) == "finished 3.0 h ago",
                  "получено \(String(describing: Notifier.lateSuffix(3 * 3600)))")
            check("Р11", "минуты просрочки попадают в текст уведомления",
                  Notifier.lateSuffix(600) == "finished 10 min ago",
                  "получено \(String(describing: Notifier.lateSuffix(600)))")
        }

        // --- В --- когда трекер показывает ёмкий вид
        do {
            check("В", "Adaptive: идущий рабочий отсчёт без курсора сворачивается",
                  isCompact(mode: .adaptive, state: .running, kind: .focus, hovered: false))
            check("В", "Adaptive: под курсором вид всегда полный",
                  !isCompact(mode: .adaptive, state: .running, kind: .focus, hovered: true))
            check("В", "Adaptive: на паузе вид полный",
                  !isCompact(mode: .adaptive, state: .paused, kind: .focus, hovered: false))
            check("В", "Adaptive: на пятиминутке вид полный",
                  !isCompact(mode: .adaptive, state: .running, kind: .rest, hovered: false))
            check("В", "Adaptive: на экране выбора вид полный",
                  !isCompact(mode: .adaptive, state: .idle, kind: .focus, hovered: false)
                  && !isCompact(mode: .adaptive, state: .finished, kind: .focus, hovered: false))
            check("В", "Always Full не сворачивается ни в одном состоянии",
                  [TimerState.idle, .running, .paused, .finished].allSatisfy { state in
                      [Kind.focus, .rest].allSatisfy { kind in
                          [true, false].allSatisfy { hovered in
                              !isCompact(mode: .alwaysFull, state: state, kind: kind, hovered: hovered)
                          }
                      }
                  })
            check("В", "в меню два вида, адаптивный первым",
                  ViewMode.allCases.count == 2
                  && ViewMode.allCases.map(\.title) == ["Adaptive", "Always Full"],
                  "\(ViewMode.allCases.map(\.title))")
            check("В", "по умолчанию выбран полный вид", ViewMode.default == .alwaysFull,
                  "\(ViewMode.default)")
        }

        print("\n" + String(repeating: "─", count: 52))
        if failures.isEmpty {
            print("ЗЕЛЁНО · \(passed) проверок")
            exit(0)
        } else {
            print("КРАСНО · \(passed) прошло, \(failures.count) упало:")
            failures.forEach { print("   • \($0)") }
            exit(1)
        }
    }
}
