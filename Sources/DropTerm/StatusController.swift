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
    private var sizeObservation: AnyCancellable?

    private let session = TerminalSession(factory: SwiftTermSurfaceFactory())
    private let sizeStore = PanelSizeStore()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal",
                                           accessibilityDescription: "DropTerm")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusItemClicked)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])

        buildPanel()
        hotKey = HotKey { [weak self] in self?.togglePanel() }
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

    // MARK: Panel

    private func buildPanel() {
        let initialFrame = ResizeMath.spotlightFrame(width: sizeStore.width,
                                                      screenFrame: NSScreen.main?.visibleFrame ?? .init(x: 0, y: 0, width: 1440, height: 900))
        panel = KeyablePanel(contentRect: initialFrame,
                             styleMask: [.borderless, .nonactivatingPanel],
                             backing: .buffered, defer: true)
        panel.level = .statusBar
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
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removeClickOutsideMonitor()
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
}
