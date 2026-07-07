import SwiftUI
import AppKit
import UniformTypeIdentifiers
import DropTermKit

/// Settings window content. Every control writes straight through
/// `store.settings` — the struct's didSet persists, and StatusController's
/// Combine subscription live-applies font/background to the running surface.
struct SettingsView: View {
    @EnvironmentObject private var store: SettingsStore

    /// Fixed-pitch families, refreshed after a font file loads so the new
    /// family shows up in the picker without an app restart.
    @State private var monospacedFamilies: [String] = SettingsView.fixedPitchFamilies()
    @State private var fontLoadError: String?

    var body: some View {
        Form {
            fontSection
            shellSection
            backgroundSection
        }
        .formStyle(.grouped)
        .frame(width: 420, height: 380)
    }

    // MARK: Font

    private var fontSection: some View {
        Section("Font") {
            Picker("Family", selection: $store.settings.fontName) {
                Text("System Default").tag(String?.none)
                ForEach(fontOptions, id: \.self) { name in
                    Text(name).tag(String?.some(name))
                }
            }
            Stepper(value: $store.settings.fontSize,
                    in: TerminalSettings.minFontSize...TerminalSettings.maxFontSize,
                    step: 1) {
                Text("Size: \(Int(store.settings.fontSize)) pt")
            }
            HStack {
                Button("Load Font File…") { loadFontFile() }
                if let fontLoadError {
                    Text(fontLoadError)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .lineLimit(2)
                }
            }
        }
    }

    /// A font loaded from a file is stored by PostScript name, which is not
    /// a family — surface it in the picker anyway so the selection isn't
    /// silently blank.
    private var fontOptions: [String] {
        var options = monospacedFamilies
        if let current = store.settings.fontName, !options.contains(current) {
            options.insert(current, at: 0)
        }
        return options
    }

    private static func fixedPitchFamilies() -> [String] {
        NSFontManager.shared.availableFontFamilies
            .filter { NSFont(name: $0, size: 13)?.isFixedPitch == true }
            .sorted()
    }

    private func loadFontFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "ttf"),
                                     UTType(filenameExtension: "otf")].compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var registerError: Unmanaged<CFError>?
        let registered = CTFontManagerRegisterFontsForURL(url as CFURL, .process, &registerError)

        guard let name = Self.postScriptName(of: url) else {
            fontLoadError = "Couldn't read a font name from that file."
            return
        }
        // Registration failing is fine when the font is already available
        // (e.g. re-loading the same file, or a font also installed
        // system-wide) — only report when the font truly can't be used.
        guard registered || NSFont(name: name, size: 13) != nil else {
            let reason = registerError?.takeRetainedValue().localizedDescription ?? "unknown error"
            fontLoadError = "Couldn't load font: \(reason)"
            return
        }
        fontLoadError = nil
        store.settings.fontName = name
        monospacedFamilies = Self.fixedPitchFamilies()
    }

    private static func postScriptName(of url: URL) -> String? {
        guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL)
                as? [CTFontDescriptor],
              let first = descriptors.first else { return nil }
        return CTFontDescriptorCopyAttribute(first, kCTFontNameAttribute) as? String
    }

    // MARK: Shell

    private var shellSection: some View {
        Section("Shell") {
            Picker("Mode", selection: shellIsCustom) {
                Text("Automatic (tmux or login shell)").tag(false)
                Text("Custom command").tag(true)
            }
            .pickerStyle(.radioGroup)
            if isCustomShell {
                TextField("Full path", text: customShellPath, prompt: Text("/opt/homebrew/bin/fish"))
            }
            Text("Shell changes apply to the next session (Ctrl+D to restart).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var isCustomShell: Bool {
        if case .custom = store.settings.shellMode { return true }
        return false
    }

    private var shellIsCustom: Binding<Bool> {
        Binding(
            get: { isCustomShell },
            set: { custom in
                if custom {
                    // Seed with the login shell rather than "" so flipping the
                    // radio alone never persists an unrunnable empty exec.
                    let seed = ProcessInfo.processInfo.environment["SHELL"] ?? "/bin/zsh"
                    store.settings.shellMode = .custom(path: seed)
                } else {
                    store.settings.shellMode = .automatic
                }
            })
    }

    private var customShellPath: Binding<String> {
        Binding(
            get: {
                if case .custom(let path) = store.settings.shellMode { return path }
                return ""
            },
            set: { store.settings.shellMode = .custom(path: $0) })
    }

    // MARK: Background

    private var backgroundSection: some View {
        Section("Background") {
            ColorPicker("Color", selection: backgroundColor, supportsOpacity: false)
            HStack {
                Text("Opacity")
                Slider(value: $store.settings.backgroundOpacity, in: 0.1...1.0)
                Text("\(Int((store.settings.backgroundOpacity * 100).rounded()))%")
                    .monospacedDigit()
                    .frame(width: 44, alignment: .trailing)
            }
            HStack {
                Text(store.settings.backgroundImagePath ?? "No image")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Choose…") { chooseBackgroundImage() }
                Button("Clear") { store.settings.backgroundImagePath = nil }
                    .disabled(store.settings.backgroundImagePath == nil)
            }
        }
    }

    private var backgroundColor: Binding<Color> {
        Binding(
            get: { Color(nsColor: NSColor(hex: store.settings.backgroundColorHex) ?? .black) },
            set: { store.settings.backgroundColorHex = NSColor($0).hexString })
    }

    private func chooseBackgroundImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.settings.backgroundImagePath = url.path
    }
}
