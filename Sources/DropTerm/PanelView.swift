import SwiftUI
import DropTermKit

struct PanelView: View {
    @EnvironmentObject private var session: TerminalSession
    @EnvironmentObject private var sizeStore: PanelSizeStore

    var body: some View {
        VStack(spacing: 8) {
            terminalCard
            FooterView()
        }
        .padding(10)
        .frame(width: sizeStore.size.width, height: sizeStore.size.height)
        .overlay(alignment: .bottomTrailing) { ResizeHandle() }
        .onAppear { session.startIfNeeded() }
    }

    /// Black rounded terminal card on the system material chrome.
    /// Crossfade: content keyed by generation; each respawn fades old out,
    /// new in.
    private var terminalCard: some View {
        ZStack {
            TerminalHostView()
                .id(session.generation)
                .transition(.opacity)

            if case .failed(let message) = session.state {
                FailedOverlay(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.generation)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

struct FailedOverlay: View {
    @EnvironmentObject private var session: TerminalSession
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Text("Couldn't start shell")
                .font(.headline)
            Text(message)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Button("Retry") { session.retry() }
                .buttonStyle(.glassProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.black.opacity(0.65))
    }
}

struct FooterView: View {
    @EnvironmentObject private var session: TerminalSession
    @State private var launchAtLogin = LoginItem.isEnabled
    @State private var jumpError: String?

    var body: some View {
        HStack(spacing: 12) {
            Toggle("Launch at login", isOn: $launchAtLogin)
                .toggleStyle(.checkbox)
                .font(.caption)
                .onChange(of: launchAtLogin) { _, wanted in
                    LoginItem.set(wanted)
                    launchAtLogin = LoginItem.isEnabled  // reverts if registration failed
                }
                .onAppear { launchAtLogin = LoginItem.isEnabled }

            if let jumpError {
                Text(jumpError)
                    .font(.caption2)
                    .foregroundStyle(.red)
                    .lineLimit(1)
            }

            Spacer()

            if ITermJump.isITermInstalled {
                Button("Jump to iTerm2") {
                    jumpError = ITermJump.jump(session: session)
                }
                .buttonStyle(.glass)
                .font(.caption)
            }

            Button("Restart") { session.restart() }
                .buttonStyle(.glass)
                .font(.caption)

            Button("Quit") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// Bottom-right drag handle: live-resizes the panel via PanelSizeStore
/// (which clamps and persists).
struct ResizeHandle: View {
    @EnvironmentObject private var sizeStore: PanelSizeStore
    @State private var dragOrigin: CGSize?

    var body: some View {
        Image(systemName: "arrow.up.left.and.arrow.down.right")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.tertiary)
            .padding(6)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(coordinateSpace: .global)
                    .onChanged { value in
                        let origin = dragOrigin ?? sizeStore.size
                        if dragOrigin == nil { dragOrigin = origin }
                        sizeStore.set(CGSize(width: origin.width + value.translation.width,
                                             height: origin.height + value.translation.height))
                    }
                    .onEnded { _ in dragOrigin = nil }
            )
    }
}
