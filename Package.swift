// swift-tools-version: 6.0
import PackageDescription
import Foundation
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().path
let package = Package(
    name: "HlgBridge",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "HlgBridge", targets: ["HlgBridge"]),
               .executable(name: "hlgbridge-cli", targets: ["HlgCLI"])],
    targets: [
        .target(name: "CHDR", cSettings: [.unsafeFlags(["-I", root + "/.build/native/include"])],
                linkerSettings: [.unsafeFlags(["-L", root + "/.build/native/lib"]), .linkedLibrary("uhdr"), .linkedLibrary("jpeg"), .linkedLibrary("c++")]),
        .target(name: "HlgCore", dependencies: ["CHDR"]),
        .executableTarget(name: "HlgBridge", dependencies: ["HlgCore"]),
        .executableTarget(name: "HlgCLI", dependencies: ["HlgCore"]),
        .executableTarget(name: "HlgChecks", dependencies: ["HlgCore"], path: "Tests/HlgCoreTests")
    ], swiftLanguageModes: [.v5]
)
