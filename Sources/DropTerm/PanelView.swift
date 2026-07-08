import SwiftUI
import DropTermKit

struct PanelView: View {
    @EnvironmentObject private var grid: TerminalGrid
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        TileGridView()
            .padding(10)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(backdrop)
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .onAppear { grid.startAll() }
    }

    /// Whole-card backdrop (spec amendments 15/20): color/image style the
    /// card as a flat composited surface at the chosen opacity; glass is
    /// macOS 26 Liquid Glass — a real blur of whatever sits behind the
    /// panel, so it manages its own translucency and ignores the opacity
    /// slider entirely.
    @ViewBuilder
    private var backdrop: some View {
        switch settingsStore.settings.backdropStyle {
        case .glass:
            Rectangle().fill(.clear).glassEffect(in: .rect(cornerRadius: 14))
        case .image, .color:
            imageOrColorBackdrop
        }
    }

    /// Image (aspect-fill, clipped so it never distorts the card's layout)
    /// when in .image style and a path is set and readable, else the flat
    /// color; opacity applies to this whole layer so it reads as one
    /// composited surface with the terminals on top.
    @ViewBuilder
    private var imageOrColorBackdrop: some View {
        Group {
            if settingsStore.settings.backdropStyle == .image,
               let path = settingsStore.settings.backgroundImagePath,
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

/// Lays out `grid.tiles` in the even split (spec amendment 17): 1 tile
/// fills the card, 2/3 split into equal columns, 4 form a 2x2 grid.
/// Animates tile insert/remove and focus changes; dims inactive tiles
/// when the setting is on (amendment 19).
struct TileGridView: View {
    @EnvironmentObject private var grid: TerminalGrid
    @EnvironmentObject private var settingsStore: SettingsStore

    var body: some View {
        layout
            .animation(.easeInOut(duration: 0.3), value: grid.tiles.count)
            .animation(.easeInOut(duration: 0.2), value: grid.focusIndex)
    }

    @ViewBuilder
    private var layout: some View {
        let tiles = grid.tiles
        switch tiles.count {
        case 1:
            tileCell(tiles[0], index: 0)
        case 2:
            HStack(spacing: 8) {
                tileCell(tiles[0], index: 0)
                tileCell(tiles[1], index: 1)
            }
        case 3:
            HStack(spacing: 8) {
                tileCell(tiles[0], index: 0)
                tileCell(tiles[1], index: 1)
                tileCell(tiles[2], index: 2)
            }
        default:
            VStack(spacing: 8) {
                HStack(spacing: 8) {
                    tileCell(tiles[0], index: 0)
                    tileCell(tiles[1], index: 1)
                }
                HStack(spacing: 8) {
                    tileCell(tiles[2], index: 2)
                    tileCell(tiles[3], index: 3)
                }
            }
        }
    }

    private func tileCell(_ tile: TerminalGrid.Tile, index: Int) -> some View {
        let isFocused = index == grid.focusIndex
        let dim = settingsStore.settings.dimInactive && !isFocused
        return TileView(session: tile.session, isFocused: isFocused)
            .opacity(dim ? 0.55 : 1.0)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(isFocused ? Color.white.opacity(0.25) : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.scale(scale: 0.85).combined(with: .opacity))
            .id(tile.id)          // STABLE slot id -> correct enter/leave animation
            .onTapGesture { grid.focus(slot: tile.id) }
    }
}

/// Hosts one tile's terminal (the old terminalCard inner content, per-tile
/// now): the crossfade on respawn plus that session's `.failed` overlay.
struct TileView: View {
    @ObservedObject var session: TerminalSession
    let isFocused: Bool

    var body: some View {
        ZStack {
            TerminalHostView(session: session, isFocused: isFocused)
                .id(session.generation)
                .transition(.opacity)
                .padding(6)
            if case .failed(let message) = session.state {
                TileFailedOverlay(session: session, message: message)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: session.generation)
        .background(Color.black.opacity(0.001))  // hit area for tap-to-focus
    }
}

struct TileFailedOverlay: View {
    let session: TerminalSession
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
