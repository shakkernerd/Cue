import AppKit
import ApplicationServices
import CueCore
import os
import ServiceManagement

private let log = Logger(subsystem: "com.shakkernerd.cue", category: "app")
/// Every observed pointer event at debug level, for diagnosing edge behavior:
/// `log stream --level debug --predicate 'subsystem == "com.shakkernerd.cue"'`.
private let timeline = Logger(subsystem: "com.shakkernerd.cue", category: "timeline")

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let configURL = ConfigFile.defaultURL
    private var config = ConfigState()
    private var layout = Displays.currentLayout()
    private var statusItem: NSStatusItem?
    private var trustPoll: Timer?
    private var tapFailed = false
    private var loginItemError: String?

    private lazy var watcher = EdgeWatcher(
        rules: [],
        environment: EdgeWatcher.Environment(
            layout: { [unowned self] in layout },
            currentInput: {
                (CGEvent(source: nil)?.location ?? .zero,
                 Modifiers(flags: CGEventSource.flagsState(.combinedSessionState)))
            }
        ),
        fire: { [unowned self] rule in perform(rule) }
    )

    private lazy var tap = EventTap(onMove: { [unowned self] event in pointerMoved(event) })

    private lazy var configWatcher = ConfigWatcher(url: configURL, queue: .main) { [weak self] in
        MainActor.assumeIsolated { self?.reloadConfig(force: false) }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Watch first, so a save during the launch read is not missed; a change the read already saw is a no-op.
        configWatcher.start()
        loadConfig()
        NotificationCenter.default.addObserver(
            self, selector: #selector(screensChanged), name: NSApplication.didChangeScreenParametersNotification,
            object: nil)
        setUpStatusItem()
        if !AXIsProcessTrusted() {
            requestAccessibility(openSettings: false)
        }
        checkAccessibility()
        if !tap.isRunning {
            waitForAccessibility()
        }
    }

    @objc private func screensChanged() {
        layout = Displays.currentLayout()
        log.info("displays changed: \(self.layout.frames.map { NSStringFromRect($0) }, privacy: .public)")
    }

    // MARK: Config

    /// At launch: creates the config when it is missing, then reads it.
    private func loadConfig() {
        apply(ConfigFile.load(from: configURL), force: true)
    }

    /// After the file changed, or from the menu (`force`). A missing or invalid file keeps the rules in force.
    private func reloadConfig(force: Bool) {
        apply(ConfigFile.read(from: configURL), force: force)
    }

    @objc private func reloadConfigFromMenu() {
        reloadConfig(force: true)
    }

    /// Applies a load result. Without `force`, a result that changes neither the rules nor the error is not logged.
    private func apply(_ result: Result<Config, ConfigError>, force: Bool) {
        let before = config
        config.apply(result)
        guard force || config != before else { return }
        if let error = config.error {
            log.error("config error: \(error.description, privacy: .public)")
        } else {
            log.info("loaded \(self.config.rules.count) rule(s) from \(self.configURL.path(percentEncoded: false), privacy: .public)")
        }
        // Setting rules cancels a rule waiting out its dwell; an unchanged rule set must not.
        if config.rules != before.rules {
            watcher.setRules(config.rules)
        }
    }

    @objc private func openConfig() {
        do {
            try ConfigFile.createIfMissing(at: configURL)
        } catch {
            log.error("\(error.description, privacy: .public)")
        }
        if !NSWorkspace.shared.open(configURL) {
            NSWorkspace.shared.open(
                [configURL], withApplicationAt: URL(filePath: "/System/Applications/TextEdit.app"),
                configuration: NSWorkspace.OpenConfiguration())
        }
    }

    // MARK: Accessibility and watching

    /// Shows the macOS prompt that leads to System Settings; Cue never changes the setting itself.
    private func requestAccessibility(openSettings: Bool) {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options), openSettings,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    private func waitForAccessibility() {
        guard trustPoll == nil else { return }
        trustPoll = Timer.scheduledTimer(
            timeInterval: 1, target: self, selector: #selector(checkAccessibility), userInfo: nil, repeats: true)
    }

    /// Starts watching once the permission is on; the poll keeps calling this until the event tap runs.
    @objc private func checkAccessibility() {
        guard AXIsProcessTrusted() else { return }
        startWatching()
        if tap.isRunning {
            trustPoll?.invalidate()
            trustPoll = nil
        }
    }

    private func startWatching() {
        let wasFailing = tapFailed
        tapFailed = !tap.start()
        if tapFailed {
            if !wasFailing { log.error("event tap could not start") }
        } else {
            log.info("watching \(self.layout.frames.map { NSStringFromRect($0) }, privacy: .public)")
        }
        updateIcon()
    }

    private func stopWatching() {
        tap.stop()
        updateIcon()
    }

    private func pointerMoved(_ event: CGEvent) {
        let location = event.location
        let delta = CGVector(
            dx: event.getDoubleValueField(.mouseEventDeltaX), dy: event.getDoubleValueField(.mouseEventDeltaY))
        let modifiers = Modifiers(flags: event.flags)
        let before = watcher.pending
        watcher.pointerMoved(to: location, delta: delta, modifiers: modifiers)
        timeline.debug(
            "move t=\(EdgeWatcher.uptime(), format: .fixed(precision: 4)) x=\(location.x) y=\(location.y) dx=\(delta.dx) dy=\(delta.dy) flags=0x\(String(event.flags.rawValue, radix: 16), privacy: .public) mods=\(modifiers.description, privacy: .public)")
        logTransition(from: before)
    }

    private func logTransition(from before: EdgeTriggerEngine.Pending?) {
        let after = watcher.pending
        guard after != before else { return }
        if let after {
            timeline.debug("armed \(Self.describe(after.rule.trigger), privacy: .public) until t=\(after.deadline, format: .fixed(precision: 4))")
        } else {
            timeline.debug("cancelled")
        }
    }

    private func perform(_ rule: Rule) {
        switch rule.action {
        case .keys(let spec):
            // macOS drops posted events without the permission, which can be turned off while Cue runs.
            guard AXIsProcessTrusted() else {
                log.error("not fired \(Self.describe(rule.trigger), privacy: .public): Accessibility is off")
                return
            }
            Keystroke.post(spec)
            log.notice("fired \(Self.describe(rule.trigger), privacy: .public): keys \(spec.description, privacy: .public)")
        case .shell(let command):
            // The command text can hold secrets, so it is not logged; the trigger names the rule.
            let trigger = Self.describe(rule.trigger)
            do {
                let pid = try ShellCommand.run(command) { pid, exit in
                    if exit.succeeded {
                        log.info("shell pid \(pid) for \(trigger, privacy: .public) ended: \(exit.description, privacy: .public)")
                    } else {
                        log.error("shell pid \(pid) for \(trigger, privacy: .public) failed: \(exit.description, privacy: .public)")
                    }
                }
                log.notice("fired \(trigger, privacy: .public): shell pid \(pid)")
            } catch {
                log.error("not fired \(trigger, privacy: .public): cannot start the shell: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    private static func describe(_ trigger: Trigger) -> String {
        "\(trigger.modifiers) + \(trigger.edge.rawValue) edge"
    }

    // MARK: Menu

    private func setUpStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        updateIcon()
    }

    private func updateIcon() {
        let active = tap.isRunning
        let image = NSImage(
            systemSymbolName: active ? "cursorarrow.rays" : "cursorarrow.slash",
            accessibilityDescription: active ? "Cue" : "Cue (inactive)")
        image?.isTemplate = true
        statusItem?.button?.image = image
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let trusted = AXIsProcessTrusted()
        if !trusted, tap.isRunning {
            stopWatching()
            waitForAccessibility()
        }
        menu.removeAllItems()

        if trusted {
            menu.addItem(Self.info(tapFailed ? "Accessibility allowed, but watching failed to start" : "Accessibility: allowed"))
        } else {
            menu.addItem(Self.info("Accessibility: not allowed, Cue is inactive"))
            menu.addItem(Self.action("Allow in System Settings…", #selector(allowAccessibility), target: self))
        }

        let count = config.rules.count
        menu.addItem(Self.info(count == 0 ? "No rules" : count == 1 ? "1 rule" : "\(count) rules"))
        if let error = config.error {
            let item = Self.info("Config error: \(error.description)")
            item.toolTip = error.description
            menu.addItem(item)
        }

        menu.addItem(.separator())
        menu.addItem(Self.action("Open Config", #selector(openConfig), key: ",", target: self))
        menu.addItem(Self.action("Reload Config", #selector(reloadConfigFromMenu), key: "r", target: self))
        menu.addItem(.separator())

        let loginItem = LoginItemStatus(SMAppService.mainApp.status)
        let toggle = Self.action("Launch at Login", #selector(toggleLaunchAtLogin), target: self)
        toggle.state = switch loginItem.mark {
        case .on: .on
        case .mixed: .mixed
        case .off: .off
        }
        menu.addItem(toggle)
        if loginItem.needsApproval {
            menu.addItem(Self.info("Launch at Login needs approval in System Settings"))
            menu.addItem(Self.action("Open Login Items Settings…", #selector(openLoginItemsSettings), target: self))
        }
        if let loginItemError {
            let item = Self.info("Launch at Login failed: \(loginItemError)")
            item.toolTip = loginItemError
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(Self.action("Quit Cue", #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
    }

    @objc private func allowAccessibility() {
        requestAccessibility(openSettings: true)
        waitForAccessibility()
    }

    /// Registers or removes Cue as a login item, whichever the real status calls for; the menu reads the
    /// status again the next time it opens.
    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        let register = LoginItemStatus(service.status).registersOnToggle
        do {
            if register {
                try service.register()
            } else {
                try service.unregister()
            }
            loginItemError = nil
            log.notice("launch at login \(register ? "registered" : "removed", privacy: .public): status \(String(describing: service.status), privacy: .public)")
        } catch {
            loginItemError = error.localizedDescription
            log.error("launch at login \(register ? "register" : "unregister", privacy: .public) failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Opens the Login Items pane so the user can allow Cue; Cue never changes the setting itself.
    @objc private func openLoginItemsSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func info(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private static func action(_ title: String, _ selector: Selector, key: String = "", target: AnyObject?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: selector, keyEquivalent: key)
        item.target = target
        return item
    }
}
