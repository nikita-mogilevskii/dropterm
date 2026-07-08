import SwiftUI
import DropTermKit

/// Re-hosts the session's long-lived terminal NSView. The view (and its pty)
/// belong to TerminalSession; this representable only parents it, so the
/// session survives MenuBarExtra tearing the SwiftUI hierarchy down on close.
///
/// The session is passed explicitly (not read from the environment) — the
/// grid hosts up to 4 tiles simultaneously, each bound to a different
/// session, so a single environment object can't serve all of them.
struct TerminalHostView: NSViewRepresentable {
    let session: TerminalSession
    /// Only the FOCUSED tile should grab first responder: making every tile
    /// call makeFirstResponder on every update would fight over key focus
    /// and the caret could never move between tiles by clicking.
    let isFocused: Bool

    func makeNSView(context: Context) -> NSView {
        let container = NSView()
        attachIfNeeded(to: container)
        return container
    }

    func updateNSView(_ container: NSView, context: Context) {
        attachIfNeeded(to: container)
    }

    private func attachIfNeeded(to container: NSView) {
        guard let terminal = session.currentView else { return }
        if terminal.superview !== container {
            container.subviews.forEach { $0.removeFromSuperview() }
            terminal.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(terminal)
            NSLayoutConstraint.activate([
                terminal.topAnchor.constraint(equalTo: container.topAnchor),
                terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
                terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            ])
        }
        guard isFocused else { return }
        // The hosted root (`terminal`) may just be a layout container —
        // key focus must go to the surface's actual interactive view
        // (focusView), not whatever wraps it.
        let focusTarget = session.currentFocusView ?? terminal
        DispatchQueue.main.async {
            focusTarget.window?.makeFirstResponder(focusTarget)
        }
    }
}
