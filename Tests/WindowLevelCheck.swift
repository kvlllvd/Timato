import Foundation
import CoreGraphics

/// Проверка Ф1.4 / крит. 7: окно приложения лежит выше обычных окон и выше Дока.
///
/// Окно ищется по pid запущенного процесса, а не по имени: имя делало проверку
/// зелёной от любого чужого «Timer» — забытого процесса прошлого прогона, копии
/// в /Applications или второго чекаута.
///
/// Сравнение с Доком тут не для полноты: проверка «слой > 0» была зелёной на
/// уровне `.floating` (3), а Док лежит на 20 — окно, задвинутое в нижний угол,
/// пряталось за Доком, и тест этого не видел.
@main
enum WindowLevelCheck {
    static func main() {
        guard CommandLine.arguments.count > 1, let pid = Int(CommandLine.arguments[1]) else {
            print("✗ Ф1.4 не передан pid проверяемого процесса")
            exit(2)
        }

        guard let raw = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else {
            print("✗ Ф1.4 не удалось получить список окон")
            exit(2)
        }

        let windows = raw.compactMap { info -> (pid: Int, owner: String, layer: Int)? in
            guard let owner = info[kCGWindowOwnerPID as String] as? Int,
                  let layer = info[kCGWindowLayer as String] as? Int else { return nil }
            let name = info[kCGWindowOwnerName as String] as? String ?? "?"
            return (owner, name, layer)
        }

        guard let target = windows.filter({ $0.pid == pid }).max(by: { $0.layer < $1.layer }) else {
            print("✗ Ф1.4 у процесса \(pid) нет окон на экране (всего окон: \(windows.count))")
            exit(1)
        }

        let ordinary = windows.first { $0.pid != pid && $0.layer == 0 }
        let dock = windows.filter { $0.owner == "Dock" }.max(by: { $0.layer < $1.layer })
        print("   слой окна «\(target.owner)» (pid \(pid)): \(target.layer)")
        if let ordinary { print("   слой обычного окна «\(ordinary.owner)»: \(ordinary.layer)") }
        if let dock { print("   слой Дока: \(dock.layer)") }

        guard ordinary != nil else {
            print("✗ Ф1.4 на экране нет ни одного обычного окна — сравнивать не с чем")
            exit(1)
        }

        guard target.layer > 0 else {
            print("✗ Ф1.4 окно на обычном слое \(target.layer) — «поверх всех окон» не работает")
            exit(1)
        }

        // Док может быть спрятан — тогда его окна нет в списке и сравнивать не с чем.
        if let dock, target.layer <= dock.layer {
            print("✗ Ф1.4 окно на слое \(target.layer), Док на \(dock.layer) — пилюля прячется за Доком")
            exit(1)
        }

        print("✓ Ф1.4 окно лежит выше обычных окон и Дока (слой \(target.layer))")
        exit(0)
    }
}
