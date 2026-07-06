import Testing

// swift-testing entry point for the executable test host (see Package.swift).
// NOTE: __swiftPMEntryPoint is a double-underscore SwiftPM SPI — the accepted
// workaround for CLT-only machines; revisit if a full Xcode toolchain lands.
@main
struct TestMain {
    static func main() async {
        await Testing.__swiftPMEntryPoint() as Never
    }
}
