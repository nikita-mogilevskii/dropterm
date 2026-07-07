import SwiftUI
import DropTermKit

struct PanelView: View {
    @EnvironmentObject private var session: TerminalSession
    @EnvironmentObject private var sizeStore: PanelSizeStore

    var body: some View {
        terminalCard
            .padding(10)
            .frame(width: sizeStore.size.width, height: sizeStore.size.height)
            .overlay(alignment: .bottomTrailing) { ResizeHandle() }
            .onAppear { session.startIfNeeded() }
    }

    /// Black rounded terminal card. The inner 8pt padding keeps glyphs clear
    /// of the corner radius (they clipped in v1). Crossfade keyed on
    /// generation: old terminal fades out, fresh one fades in on respawn.
    private var terminalCard: some View {
        ZStack {
            TerminalHostView()
                .id(session.generation)
                .transition(.opacity)
                .padding(8)

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

/// Invisible bottom-right drag region (18pt). Resize deltas come from
/// NSEvent.mouseLocation (SCREEN coordinates) captured at drag start —
/// SwiftUI gesture translation breaks when macOS shifts the panel away
/// from a screen edge mid-drag (v1 bug: size inverted/exploded at the
/// right screen edge). AppKit y-origin is bottom-left, so height delta
/// is flipped.
struct ResizeHandle: View {
    @EnvironmentObject private var sizeStore: PanelSizeStore
    @State private var dragStart: (mouse: NSPoint, size: CGSize)?

    var body: some View {
        Color.clear
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        let mouse = NSEvent.mouseLocation
                        let start = dragStart ?? (mouse, sizeStore.size)
                        if dragStart == nil { dragStart = start }
                        sizeStore.set(CGSize(
                            width: start.size.width + (mouse.x - start.mouse.x),
                            height: start.size.height + (start.mouse.y - mouse.y)))
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
