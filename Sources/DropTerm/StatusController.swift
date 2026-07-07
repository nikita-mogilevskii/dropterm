import AppKit
import Combine
import SwiftUI
import DropTermKit

/// Borderless panels refuse key status by default; the terminal needs it.
final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class StatusController: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var panel: KeyablePanel!
    private var hotKey: HotKey?
    private var clickOutsideMonitor: Any?
    private var keyMonitor: Any?
    private var sizeObservation: AnyCancellable?
    private var settingsObservation: AnyCancellable?
    private var settingsWindow: NSWindow?

    private let settingsStore: SettingsStore
    private let session: TerminalSession
    private let sizeStore = PanelSizeStore()

    override init() {
        // Session and factory hang off the same store: the factory reads
        // appearance at surface creation, the session re-resolves the
        // shell command from it on every respawn.
        let store = SettingsStore()
        settingsStore = store
        session = TerminalSession(factory: SwiftTermSurfaceFactory(settingsStore: store),
                                  settingsStore: store)
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal",
                                           accessibilityDescription: "DropTerm")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        reregisterCustomFontIfNeeded()
        buildPanel()
        hotKey = HotKey { [weak self] in self?.togglePanel() }

        // Live-apply font/background edits to the running surface. Shell
        // mode is deliberately NOT applied live — it takes effect on the
        // next respawn (the session re-resolves via its commandProvider).
        settingsObservation = settingsStore.$settings
            .removeDuplicates()
            .sink { [weak self] in self?.session.applySettings($0) }
    }

    // MARK: Clicks

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            togglePanel()
        }
    }

    /// Transient menu trick: attach, click, detach — keeps left-click custom.
    private func showMenu() {
        let menu = NSMenu()
        let settings = NSMenuItem(title: "Settings…",
                                  action: #selector(openSettingsWindow), keyEquivalent: "")
        settings.target = self
        menu.addItem(settings)
        let login = NSMenuItem(title: "Launch at login",
                               action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.target = self
        login.state = LoginItem.isEnabled ? .on : .off
        menu.addItem(login)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit DropTerm",
                                action: #selector(NSApplication.terminate(_:)),
                                keyEquivalent: "q"))
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
    }

    @objc private func toggleLaunchAtLogin() {
        LoginItem.set(!LoginItem.isEnabled)
    }

    // MARK: Settings window

    /// Single reusable titled window; closing only orders it out
    /// (isReleasedWhenClosed = false), reopening brings the same one back.
    @objc private func openSettingsWindow() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 380),
                                  styleMask: [.titled, .closable],
                                  backing: .buffered, defer: false)
            window.title = "DropTerm Settings"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView:
                SettingsView().environmentObject(settingsStore))
            settingsWindow = window
        }
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// CTFontManagerRegisterFontsForURL registration is process-scoped —
    /// a font loaded via "Load Font File…" in a prior launch is gone until
    /// re-registered here. Runs before buildPanel()/session start so the
    /// terminal surface picks up the resolved font on its very first
    /// `applyAppearance` call, not on a later live-settings update. Errors
    /// are ignored (worst case: SwiftTermSurface falls back to the system
    /// monospaced font, same as any other unresolvable fontName).
    private func reregisterCustomFontIfNeeded() {
        guard let path = settingsStore.settings.fontFilePath else { return }
        guard FileManager.default.fileExists(atPath: path) else {
            settingsStore.settings.fontFilePath = nil
            settingsStore.settings.fontName = nil
            return
        }
        CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: path) as CFURL, .process, nil)
    }

    // MARK: Panel

    private func buildPanel() {
        let initialFrame = ResizeMath.spotlightFrame(width: sizeStore.width,
                                                      screenFrame: NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900))
        panel = KeyablePanel(contentRect: initialFrame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.level = .statusBar
        // Lets the panel float above fullscreen apps' own Spaces, matching
        // the README's "even fullscreen apps" claim for the global toggle.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.contentView = NSHostingView(rootView:
            PanelView()
                .environmentObject(session)
                .environmentObject(sizeStore))

        // Panel frame follows the size store (resize handle writes there);
        // re-derive the Spotlight-style frame so resizing stays centered.
        sizeObservation = sizeStore.$width.sink { [weak self] newWidth in
            self?.applyPanelWidth(newWidth)
        }
    }

    private func applyPanelWidth(_ width: CGFloat) {
        guard let panel else { return }
        let screen = panel.screen ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(ResizeMath.spotlightFrame(width: width, screenFrame: screen.visibleFrame), display: true)
    }

    private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        positionSpotlightStyle()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        session.startIfNeeded()
        installClickOutsideMonitor()
        installKeyMonitor()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removeClickOutsideMonitor()
        removeKeyMonitor()
    }

    /// Spotlight-style positioning (v1.1 amendment 9, supersedes the old
    /// under-status-item anchor): always horizontally centered on the
    /// screen hosting the status item (fallback main screen), top edge at
    /// 75% of the visible height. Click-open and hotkey-open share this
    /// single path.
    private func positionSpotlightStyle() {
        let screen = statusItem.button?.window?.screen ?? NSScreen.main
        guard let screen else { return }
        panel.setFrame(ResizeMath.spotlightFrame(width: sizeStore.width, screenFrame: screen.visibleFrame),
                       display: true)
    }

    private func installClickOutsideMonitor() {
        removeClickOutsideMonitor()
        clickOutsideMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.hidePanel()
        }
    }

    private func removeClickOutsideMonitor() {
        if let clickOutsideMonitor {
            NSEvent.removeMonitor(clickOutsideMonitor)
            self.clickOutsideMonitor = nil
        }
    }

    // MARK: In-panel key commands

    /// Local monitor lives only while the panel is visible (installed on
    /// show, removed on hide, mirroring the outside-click monitor). Local
    /// monitors see every keyDown in OUR app though, so events are also
    /// gated to the panel itself — Ctrl+W typed into the Settings window
    /// must not quit the app.
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handlePanelKeyDown(event)
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    /// Ctrl+W quit, Ctrl+= / Ctrl++ / Ctrl+- font size. Swallowed events
    /// return nil so the terminal never sees them; everything else passes
    /// through untouched (the shell owns all other Ctrl chords).
    ///
    /// Modifiers are matched EXACTLY (not just "contains .control") so a
    /// chord like Ctrl+Cmd+W — which still `.contains(.control)` — passes
    /// through instead of quitting the app. Shift is allowed in addition
    /// to Control only for the "+" case, since Ctrl+Shift+= is how a US
    /// keyboard actually types Ctrl++ (Shift is what turns "=" into "+").
    private func handlePanelKeyDown(_ event: NSEvent) -> NSEvent? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let isPlainControl = flags == .control
        let isControlShift = flags == [.control, .shift]
        guard isPlainControl || isControlShift else {
            return event
        }
        switch event.charactersIgnoringModifiers {
        case "w" where isPlainControl:
            NSApp.terminate(nil)
            return nil
        case "=", "+":
            settingsStore.bumpFontSize(1)
            return nil
        case "-" where isPlainControl:
            settingsStore.bumpFontSize(-1)
            return nil
        default:
            return event
        }
    }
}
