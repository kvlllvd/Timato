import Foundation
import CoreGraphics

/// Состояние отсчёта.
enum TimerState: Equatable {
    case idle       // не запущен, показывает исходную длительность
    case running
    case paused
    case finished
}

/// Монотонные часы: секунды от произвольной точки, которые не зависят от
/// системного времени и продолжают идти, пока машина спит.
///
/// Настенное время (`Date`) для отсчёта не годится: шаговая коррекция по NTP,
/// ручная правка даты или dual-boot сдвигают дедлайн, и таймер звонит не вовремя.
func monotonicSeconds() -> TimeInterval {
    var info = mach_timebase_info_data_t()
    mach_timebase_info(&info)
    return TimeInterval(mach_continuous_time()) * TimeInterval(info.numer)
        / TimeInterval(info.denom) / 1_000_000_000
}

/// Ядро таймера.
///
/// Считает не тики, а разницу до дедлайна: ошибка не накапливается и засыпание
/// машины не сбивает отсчёт. `now` подменяется в тестах, чтобы не ждать реального времени.
final class TimerEngine {

    private(set) var duration: TimeInterval
    private(set) var state: TimerState = .idle

    /// Момент по монотонным часам, когда таймер должен зазвонить.
    /// Есть только в состоянии `.running`.
    private var deadline: TimeInterval?
    /// Остаток, замороженный паузой. Есть только в состоянии `.paused`.
    private var frozenRemaining: TimeInterval?

    /// Источник времени в монотонных секундах. В тестах подменяется.
    var now: () -> TimeInterval

    /// Вызывается ровно один раз при достижении нуля.
    /// Аргумент — на сколько секунд звонок опоздал: ноль при обычной работе и
    /// заметная величина, если машина всё это время спала.
    var onFinish: ((TimeInterval) -> Void)?

    init(duration: TimeInterval = 25 * 60,
         now: @escaping () -> TimeInterval = monotonicSeconds) {
        self.duration = duration
        self.now = now
    }

    /// Сколько осталось прямо сейчас, в секундах. Никогда не отрицательное.
    var remaining: TimeInterval {
        max(0, rawRemaining)
    }

    /// Остаток без обрезки снизу: отрицательный, если дедлайн уже прошёл.
    /// Нужен, чтобы отличить «звонок вовремя» от «проспали три часа».
    private var rawRemaining: TimeInterval {
        switch state {
        case .idle:     return duration
        case .running:  return (deadline ?? now()) - now()
        case .paused:   return frozenRemaining ?? duration
        case .finished: return 0
        }
    }

    var isRunning: Bool { state == .running }

    /// Запускает отсчёт на указанное число секунд с нуля.
    func start(seconds: TimeInterval) {
        guard seconds > 0 else { return }
        duration = seconds
        deadline = now() + seconds
        frozenRemaining = nil
        state = .running
    }

    /// Перезапускает текущую длительность с начала.
    func restart() {
        start(seconds: duration)
    }

    /// Замораживает остаток. Из любого другого состояния — ничего не делает.
    ///
    /// Пауза ровно на нуле игнорируется: иначе таймер застревал бы в состоянии,
    /// из которого нельзя ни продолжить, ни дозвонить.
    func pause() {
        guard state == .running, rawRemaining > 0 else { return }
        frozenRemaining = remaining
        deadline = nil
        state = .paused
    }

    /// Возобновляет с замороженного остатка, отсчитывая его от текущего момента.
    func resume() {
        guard state == .paused else { return }
        deadline = now() + max(0, frozenRemaining ?? duration)
        frozenRemaining = nil
        state = .running
    }

    /// Возвращает в исходное состояние с той же длительностью, отсчёт не идёт.
    func reset() {
        deadline = nil
        frozenRemaining = nil
        state = .idle
    }

    /// Завершает отсчёт прямо сейчас, как будто он дошёл до нуля: тот же звонок,
    /// та же засечка, тот же переход к отдыху. Кнопка «стоп» — это именно
    /// «отрезок сделан досрочно», а не отмена: для отмены есть `reset()`.
    func finishNow() {
        guard state == .running || state == .paused else { return }
        deadline = nil
        frozenRemaining = nil
        state = .finished
        onFinish?(0)
    }

    /// Дёргается интерфейсом. Единственное место, где таймер может завершиться.
    func tick() {
        guard state == .running else { return }
        let rest = rawRemaining
        guard rest <= 0 else { return }
        deadline = nil
        frozenRemaining = nil
        state = .finished
        onFinish?(-rest)
    }
}

/// Форматирует остаток в `MM:SS`, а от часа и больше — в `H:MM:SS`.
/// Округляет вверх, чтобы на старте 25-минутного таймера показывалось `25:00`, а не `24:59`.
func formatRemaining(_ seconds: TimeInterval) -> String {
    let total = Int(ceil(max(0, seconds)))
    let h = total / 3600
    let m = (total % 3600) / 60
    let s = total % 60
    return h > 0
        ? String(format: "%d:%02d:%02d", h, m, s)
        : String(format: "%02d:%02d", m, s)
}

/// Единственный источник правды о вариантах, которые видит пользователь.
/// Показываются при открытии приложения и сразу после звонка.
enum Presets {
    /// Варианты на экране выбора. Отдыха здесь нет: он включается сам.
    static let minutes = [25, 50]
    /// Отдых, который включается сам после отработанного отрезка.
    /// Длина зависит от отрезка: после 25 минут — 5, после 50 — 10.
    static let rests = [5, 10]
    /// Главные варианты — то, ради чего приложение и открывают.
    static let focus = [25, 50]

    /// Сколько минут отдыха следует за отработанным отрезком.
    /// Длинный отрезок — длинный отдых; короткий довольствуется пятиминуткой.
    static func restAfter(minutes: Int) -> Int {
        minutes >= 50 ? 10 : 5
    }
    /// Черточек в ряду поначалу четыре — они растянуты на всю ширину окна,
    /// как две кнопки выбора над ними. Заполнились все четыре — ряд делится
    /// вдвое мельче, и справа появляются ещё четыре: см. `Segments.shown`.
    static let segments = 4
}

/// Ряд черточек считается не в отрезках, а в половинках: 25 минут закрашивают
/// половину черточки, 50 — целую. Целые числа вместо дробей выбраны нарочно —
/// на них весь счёт (и перенос ряда) остаётся точным.
enum Segments {
    /// Половинок в одной черточке.
    static let halvesPerSegment = 2
    /// Ёмкость первого ряда в половинках: четыре черточки по две.
    static let rowCapacity = Presets.segments * halvesPerSegment
    /// Сколько черточек в разросшемся ряду: те же четыре и ещё четыре справа.
    static let expandedCount = Presets.segments * 2
    /// Вся ёмкость ряда в половинках: восемь черточек по две, то есть восемь часов.
    static let capacity = expandedCount * halvesPerSegment

    /// Сколько черточек показывать при таком закрашивании.
    ///
    /// Пока закрашено не больше четырёх черточек — их и видно, во всю ширину.
    /// Стоит перевалить за четвёртую — ряд перестраивается на восемь, той же
    /// общей ширины: старые четыре сжимаются, справа встают ещё четыре. Новые
    /// могут появиться уже начатыми: было 3,5 черточки, отработали целую —
    /// получилось 4,5, и пятая стоит наполовину.
    static func shown(filledHalves: Int) -> Int {
        filledHalves > rowCapacity ? expandedCount : Presets.segments
    }

    /// Сколько половинок закрашивает отработанный отрезок.
    /// Отдых не закрашивает ничего: засечка ставится за работу.
    static func credit(minutes: Int) -> Int {
        guard Kind.forMinutes(minutes) == .focus else { return 0 }
        // 50 минут — целая черточка, всё остальное рабочее (в том числе 25) — половина.
        return minutes >= 50 ? halvesPerSegment : 1
    }

    /// Ряд после ещё одного отработанного отрезка.
    ///
    /// Заполненный ряд не обнуляется в тот же миг, когда закрасилась последняя
    /// черточка, — иначе все восемь не увидеть ни секунды. Он стоит полным до
    /// конца следующего отрезка, и уже тот начинает ряд заново, снова с четырёх.
    static func advance(_ filled: Int, minutes: Int) -> Int {
        let credit = credit(minutes: minutes)
        guard credit > 0 else { return filled }
        guard filled < capacity else { return credit }
        return min(capacity, filled + credit)
    }
}

/// Цвет свечения за левым верхним углом. Перебирается кликом по табло:
/// зелёный по умолчанию, дальше фиолетовый, синий, красный и снова зелёный.
enum Accent: CaseIterable {
    case red, green, purple, blue

    /// С чего начинается перебор — и каким окно светится, пока по табло не кликали.
    static let `default` = Accent.green

    var next: Accent {
        let all = Accent.allCases
        let index = all.firstIndex(of: self) ?? 0
        return all[(index + 1) % all.count]
    }
}

/// Как трекер держит ширину. Пункт меню, всегда выбран ровно один.
///
/// Порядок случаев — это порядок пунктов во вложенном меню «Size»: сначала
/// адаптивный вид, под ним полный.
enum ViewMode: CaseIterable {
    /// Без курсора идущий рабочий отсчёт сжимается до табло и полосы,
    /// под курсором разворачивается обратно.
    case adaptive
    /// Полный вид всегда, в любом состоянии.
    case alwaysFull

    /// Вид при запуске: полный. Свернувшийся сам по себе трекер — сюрприз,
    /// на который надо согласиться, а не то, что человек видит первым делом.
    static let `default` = ViewMode.alwaysFull

    /// Заголовок пункта меню.
    var title: String {
        switch self {
        case .adaptive:   return "Adaptive"
        case .alwaysFull: return "Full"
        }
    }
}

/// Свёрнут ли трекер прямо сейчас.
///
/// Ёмкий вид бывает ровно в одном случае: режим `Adaptive`, идёт рабочий
/// отсчёт (25 или 50) и курсора на окне нет. Отдых, пауза, экран выбора
/// и режим `Full` — всегда полный вид: там кнопки нужны сразу.
func isCompact(mode: ViewMode, state: TimerState, kind: Kind, hovered: Bool) -> Bool {
    guard mode == .adaptive, !hovered, kind == .focus else { return false }
    return state == .running
}

/// Зачем запущен отсчёт. От этого зависит и цвет полосы, и что будет по звонку.
enum Kind: Hashable {
    case focus
    case rest

    /// Пятиминутка и десятиминутка — отдых, всё остальное — работа.
    static func forMinutes(_ minutes: Int) -> Kind {
        Presets.rests.contains(minutes) ? .rest : .focus
    }
}

/// Что запускается само, когда отсчёт дозвонил.
/// После отработанного отрезка — отдых; после отдыха — ничего, снова выбор.
func nextAfterFinish(minutes: Int) -> Int? {
    Kind.forMinutes(minutes) == .focus ? Presets.restAfter(minutes: minutes) : nil
}

/// Насколько закрашена черточка с номером `index`, от 0 до 1.
/// Ряд закрашивается слева направо: до текущей — целиком, после — пусто,
/// а сама текущая может стоять наполовину. Номер считается одинаково и в ряду
/// из четырёх, и в разросшемся из восьми: черточки везде по две половинки.
func segmentFill(index: Int, filledHalves: Int) -> CGFloat {
    let halves = max(0, min(Segments.capacity, filledHalves)) - index * Segments.halvesPerSegment
    let clamped = max(0, min(Segments.halvesPerSegment, halves))
    return CGFloat(clamped) / CGFloat(Segments.halvesPerSegment)
}

/// Какой экран показан в окне. Выводится только из состояния таймера,
/// поэтому проверяется тестом без запуска интерфейса.
enum Screen: Equatable {
    /// Выбор варианта. `options` — то, что видно на экране, и больше ничего.
    case choice(options: [Int])
    case countdown

    static func forState(_ state: TimerState) -> Screen {
        switch state {
        case .idle, .finished: return .choice(options: Presets.minutes)
        case .running, .paused: return .countdown
        }
    }

    var options: [Int] {
        if case .choice(let options) = self { return options }
        return []
    }
}

/// Доля прошедшего времени от полной длительности, 0…1. Полоса прогресса рисует
/// именно её: заполняется то, что уже прошло, а не то, что осталось.
func elapsedFraction(remaining: TimeInterval, duration: TimeInterval) -> CGFloat {
    guard duration > 0 else { return 0 }
    let elapsed = duration - max(0, min(duration, remaining))
    return CGFloat(max(0, min(1, elapsed / duration)))
}

