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
        panel = KeyablePanel(contentRect: NSRect(origin: .zero, size: sizeStore.size),
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
        // keep the top-right corner anchored.
        sizeObservation = sizeStore.$size.sink { [weak self] newSize in
            self?.applyPanelSize(newSize)
        }
    }

    private func applyPanelSize(_ size: CGSize) {
        guard let panel else { return }
        let old = panel.frame
        let newFrame = NSRect(x: old.maxX - size.width,
                              y: old.maxY - size.height,
                              width: size.width, height: size.height)
        panel.setFrame(newFrame, display: true)
    }

    private func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    private func showPanel() {
        positionUnderStatusItem()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        session.startIfNeeded()
        installClickOutsideMonitor()
    }

    private func hidePanel() {
        panel.orderOut(nil)
        removeClickOutsideMonitor()
    }

    private func positionUnderStatusItem() {
        let size = sizeStore.size
        if let buttonWindow = statusItem.button?.window {
            let anchor = buttonWindow.frame
            let x = anchor.maxX - size.width
            let y = anchor.minY - size.height - 4
            panel.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height),
                           display: true)
        } else {
            // Hotkey with no resolvable item position: center-top of main screen.
            guard let screen = NSScreen.main else { return }
            let f = screen.visibleFrame
            panel.setFrame(NSRect(x: f.midX - size.width / 2,
                                  y: f.maxY - size.height - 8,
                                  width: size.width, height: size.height),
                           display: true)
        }
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
