import SwiftUI
import DropTermKit

/// Re-hosts the session's long-lived terminal NSView. The view (and its pty)
/// belong to TerminalSession; this representable only parents it, so the
/// session survives MenuBarExtra tearing the SwiftUI hierarchy down on close.
struct TerminalHostView: NSViewRepresentable {
    @EnvironmentObject private var session: TerminalSession

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
        guard terminal.superview !== container else { return }
        container.subviews.forEach { $0.removeFromSuperview() }
        terminal.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(terminal)
        NSLayoutConstraint.activate([
            terminal.topAnchor.constraint(equalTo: container.topAnchor),
            terminal.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            terminal.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            terminal.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        // The hosted root (`terminal`) may just be a layout container when
        // the surface sits a background image behind the real SwiftTerm
        // view (see SwiftTermSurface.focusView) — key focus must go to the
        // actual interactive view, not whatever wraps it.
        let focusTarget = session.currentFocusView ?? terminal
        DispatchQueue.main.async {
            focusTarget.window?.makeFirstResponder(focusTarget)
        }
    }
}
