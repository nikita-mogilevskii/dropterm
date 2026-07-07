import SwiftUI
import DropTermKit

struct PanelView: View {
    @EnvironmentObject private var session: TerminalSession
    @EnvironmentObject private var sizeStore: PanelSizeStore
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        terminalCard
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottomTrailing) { ResizeHandle() }
            .onAppear { session.startIfNeeded() }
    }

    /// Rounded terminal card. The inner 8pt padding keeps glyphs clear of
    /// the corner radius (they clipped in v1). Crossfade keyed on
    /// generation: old terminal fades out, fresh one fades in on respawn.
    /// Backdrop (color/image/opacity) styles the whole card as one visual
    /// surface (spec amendment 15) — the terminal view itself is always
    /// fully transparent, so at <100% opacity the desktop shows through the
    /// entire card while glyphs stay crisp.
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
        .background(backdrop)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    /// Image (aspect-fill, clipped so it never distorts the card's layout)
    /// when set, else the flat color; opacity applies to this whole layer
    /// so it reads as one composited surface with the terminal on top.
    @ViewBuilder
    private var backdrop: some View {
        Group {
            if let path = settingsStore.settings.backgroundImagePath,
               let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            } else {
                Color(hex: settingsStore.settings.backgroundColorHex) ?? Color.black
            }
        }
        .opacity(settingsStore.settings.backgroundOpacity)
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
/// is flipped. The panel's horizontal center is pinned (Spotlight-style
/// positioning), so width tracks 2x the horizontal mouse delta.
struct ResizeHandle: View {
    @EnvironmentObject private var sizeStore: PanelSizeStore
    @State private var dragStart: (mouseX: CGFloat, width: CGFloat)?

    var body: some View {
        Color.clear
            .frame(width: 18, height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        let mouseX = NSEvent.mouseLocation.x
                        let start = dragStart ?? (mouseX, sizeStore.width)
                        if dragStart == nil { dragStart = start }
                        sizeStore.set(width: ResizeMath.widthResized(startWidth: start.width, mouseStartX: start.mouseX, mouseNowX: NSEvent.mouseLocation.x))
                    }
                    .onEnded { _ in dragStart = nil }
            )
    }
}
