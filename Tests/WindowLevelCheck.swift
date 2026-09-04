import Foundation
import CoreGraphics

/// Проверка Ф1.4 / крит. 7: окно приложения лежит на слое выше обычных окон.
///
/// Окно ищется по pid запущенного процесса, а не по имени: имя делало проверку
/// зелёной от любого чужого «Timer» — забытого процесса прошлого прогона, копии
/// в /Applications или второго чекаута.
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
        print("   слой окна «\(target.owner)» (pid \(pid)): \(target.layer)")
        if let ordinary { print("   слой обычного окна «\(ordinary.owner)»: \(ordinary.layer)") }

        guard ordinary != nil else {
            print("✗ Ф1.4 на экране нет ни одного обычного окна — сравнивать не с чем")
            exit(1)
        }

        if target.layer > 0 {
            print("✓ Ф1.4 окно лежит выше обычных окон (слой \(target.layer) > 0)")
            exit(0)
        } else {
            print("✗ Ф1.4 окно на обычном слое \(target.layer) — «поверх всех окон» не работает")
            exit(1)
        }
    }
}
