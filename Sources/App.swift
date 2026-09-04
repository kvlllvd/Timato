import AppKit

// Живая проверка интерфейса (`Tests/LiveInterfaceCheck.swift`) собирает те же
// исходники со своим `@main`, поэтому боевая точка входа из сборки убирается
// флагом `-DLIVE_CHECK`. Копировать и править исходники для этого не нужно.
#if !LIVE_CHECK
@main
enum TimerApp {
    /// Делегат держим статически: NSApplication хранит его слабой ссылкой.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        // .accessory — иконки в доке нет, приложение живёт в строке меню.
        app.setActivationPolicy(.accessory)
        app.delegate = delegate
        app.run()
    }
}
#endif

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var controller: TimerWindowController?
    private var statusItem: NSStatusItem?
    private var guideController: GuideWindowController?
    /// Меню помидора. Наружу — только для живой проверки: сам `NSStatusItem`
    /// из дерева видов не достаётся, а проверить состав пунктов надо.
    var statusMenu: NSMenu? { statusItem?.menu }

    /// Пункт с итогом: его заголовок пересобирается каждый раз перед показом меню.
    private var summaryItem: NSMenuItem?
    /// Пункт звука: один пункт на два состояния, заголовок переключается.
    private var muteItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Шрифт — до создания окна: интерфейс собирается уже с ним.
        DisplayFont.register()
        Notifier.requestPermissionIfPossible()

        let controller = TimerWindowController()
        controller.showWindow(nil)
        self.controller = controller

        buildMainMenu()
        buildStatusItem()
        NSApp.activate(ignoringOtherApps: true)
        // Место окна считается уже при живом экране — см. `placeWindow()`.
        controller.placeWindow()
    }

    /// Главное меню приложению с политикой `.accessory` не показывают, но без него
    /// AppKit не разбирает сочетания клавиш: Cmd+Q, Cmd+W и Cmd+H не работали бы
    /// вообще, а выйти можно было бы только мышью через помидор.
    private func buildMainMenu() {
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Hide Pimer", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        // Свой обработчик, а не `performClose:`: у окна `.borderless` нет
        // `.closable`, поэтому системный путь закрытия отключает сам пункт
        // (`validateMenuItem` → false) и Cmd+W до окна не доходит вовсе.
        appMenu.addItem(withTitle: "Close Window", action: #selector(closeWindow),
                        keyEquivalent: "w").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Pimer", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu

        let main = NSMenu()
        main.addItem(appItem)
        NSApp.mainMenu = main
    }

    /// Единственная точка входа в приложение, когда окно закрыто:
    /// помидор в строке меню.
    private func buildStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = TomatoIcon.statusBarImage()
        item.button?.toolTip = "Pimer"

        let menu = NSMenu()
        // Итог за сеанс — и он же путь назад к окну: отдельного «Show Timer»
        // в меню нет, а после Cmd+W вернуть окно чем-то надо.
        let summary = menu.addItem(withTitle: Self.summaryTitle(halves: 0),
                                   action: #selector(showTimer), keyEquivalent: "")
        summary.target = self
        summaryItem = summary

        // Звук — вторым пунктом, сразу под итогом: это состояние приложения,
        // а не действие вроде сброса или выхода.
        let mute = menu.addItem(withTitle: Self.muteTitle(isMuted: Notifier.isMuted),
                                action: #selector(toggleMute), keyEquivalent: "")
        mute.target = self
        muteItem = mute

        menu.addItem(.separator())
        menu.addItem(withTitle: "Reset", action: #selector(resetProgress), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Guide", action: #selector(openGuide), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Quit", action: #selector(quit), keyEquivalent: "q").target = self

        // Итог считается не при сборке меню, а перед каждым показом: за время
        // между показами отрезки успевают закончиться.
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    /// Заголовок пункта итога: штрих читается как час, половина штриха — как
    /// полчаса. Верхней границы нет — за долгий сеанс набегает и «20 h».
    ///
    /// Считается из половинок целыми числами, без дробей с плавающей точкой:
    /// половина здесь ровно одна, и приписать «,5» надёжнее, чем округлять.
    /// Разделитель — запятая, как в макете подписи.
    static func summaryTitle(halves: Int) -> String {
        let hours = halves / Segments.halvesPerSegment
        let half = halves % Segments.halvesPerSegment != 0
        return "Summary — \(hours)\(half ? ",5" : "") h"
    }

    /// Заголовок пункта звука: он называет действие, а не состояние. Когда звук
    /// включён — «Mute» (клик выключит), когда выключен — «Unmute».
    static func muteTitle(isMuted: Bool) -> String { isMuted ? "Unmute" : "Mute" }

    /// «Mute» / «Unmute» — глушит звонок окончания. Баннер уведомления при этом
    /// остаётся: узнать об окончании пользователь должен в любом случае.
    @objc private func toggleMute() {
        Notifier.isMuted.toggle()
        muteItem?.title = Self.muteTitle(isMuted: Notifier.isMuted)
    }

    /// Закрыть окно. Приложение остаётся в строке меню, отсчёт продолжает идти,
    /// вернуть окно — пункт с итогом в меню помидора.
    @objc private func closeWindow() {
        controller?.window?.close()
    }

    @objc private func showTimer() {
        controller?.showWindow(nil)
        controller?.placeWindow()
        controller?.window?.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// «Guide»: короткое окно-подсказка поверх уже идущего таймера. Держим
    /// один контроллер и переиспользуем — повторный клик просто выводит то же
    /// окно вперёд, а не плодит второе.
    @objc private func openGuide() {
        let guide = guideController ?? GuideWindowController()
        guideController = guide
        guide.window?.center()
        guide.showWindow(nil)
        guide.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// «Reset» — тот же сброс, что и кнопкой в окне: обнуляет и ряд штрихов,
    /// и итог за сеанс.
    @objc private func resetProgress() {
        controller?.resetProgress()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    /// Закрытое окно приложение не завершает: оно остаётся в строке меню,
    /// отсчёт продолжает идти, выход — через пункт «Quit».
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

extension AppDelegate: NSMenuDelegate {
    func menuNeedsUpdate(_ menu: NSMenu) {
        summaryItem?.title = Self.summaryTitle(halves: controller?.completedHalves ?? 0)
        muteItem?.title = Self.muteTitle(isMuted: Notifier.isMuted)
    }
}
