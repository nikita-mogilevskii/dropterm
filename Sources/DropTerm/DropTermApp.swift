import SwiftUI

@main
struct DropTermApp: App {
    @NSApplicationDelegateAdaptor(StatusController.self) private var controller

    var body: some Scene {
        // No windows: everything lives in the status item + panel.
        Settings { EmptyView() }
    }
}
