// swift-tools-version: 6.2
import PackageDescription

// CLT-only machine: Testing.framework ships with the Command Line Tools but
// sits outside the default search paths; its dylibs live one level deeper.
let testingFrameworksPath = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"
let testingLibPath = "/Library/Developer/CommandLineTools/Library/Developer/usr/lib"

let package = Package(
    name: "DropTerm",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "DropTermKit",
            dependencies: [.product(name: "SwiftTerm", package: "SwiftTerm")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "DropTerm",
            dependencies: ["DropTermKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Test host: CLT-only machines lack the xctest runner, so `swift test`
        // silently runs nothing. This executable hosts swift-testing instead.
        // Run the suite with: swift run DropTermTests
        .executableTarget(
            name: "DropTermTests",
            dependencies: ["DropTermKit"],
            path: "Tests/DropTermKitTests",
            swiftSettings: [
                .swiftLanguageMode(.v5),
                .unsafeFlags(["-F", testingFrameworksPath]),
            ],
            linkerSettings: [
                .unsafeFlags([
                    "-F", testingFrameworksPath,
                    "-Xlinker", "-rpath", "-Xlinker", testingFrameworksPath,
                    "-Xlinker", "-rpath", "-Xlinker", testingLibPath,
                ])
            ]
        ),
    ]
)
