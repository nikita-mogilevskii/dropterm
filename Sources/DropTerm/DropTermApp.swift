import SwiftUI
import DropTermKit

@main
struct DropTermApp: App {
    @StateObject private var session = TerminalSession(factory: SwiftTermSurfaceFactory())
    @StateObject private var sizeStore = PanelSizeStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environmentObject(session)
                .environmentObject(sizeStore)
        } label: {
            Image(systemName: "terminal")
        }
        .menuBarExtraStyle(.window)
    }
}
