// swift-tools-version:6.0
import PackageDescription

// KSPlayer, Omnia's second playback engine, with its own FFmpeg. It builds
// as a framework that exports only this module's Swift API, so its FFmpeg
// 6.1 stays separate from the FFmpeg 8 inside Omnia's mpv.
let package = Package(
    name: "OmniaKSEngine",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "OmniaKSEngine", type: .dynamic, targets: ["OmniaKSEngine"]),
    ],
    dependencies: [
        // The open-source GPLv3 branch, pinned to one reviewed commit.
        .package(url: "https://github.com/kingslay/KSPlayer.git", revision: "be7f60d3b94a0941c643fe8699113cfce4f08e83"),
    ],
    targets: [
        .target(
            name: "OmniaKSEngine",
            dependencies: [.product(name: "KSPlayer", package: "KSPlayer")],
            // KSPlayer stays out of this module's interface; the compiler
            // checks that nothing of it leaks into what the app sees.
            swiftSettings: [.enableExperimentalFeature("CheckImplementationOnly")],
            // Xcode also applies these to the app's own link. The app keeps
            // its Swift symbols (for Xcode Previews) and the entry point
            // Xcode's debug launcher looks up; nothing else in the app needs
            // exporting.
            linkerSettings: [
                .unsafeFlags([
                    "-Xlinker", "-exported_symbol", "-Xlinker", "_$s13OmniaKSEngine*",
                    "-Xlinker", "-exported_symbol", "-Xlinker", "_$s5Omnia*",
                    "-Xlinker", "-exported_symbol", "-Xlinker", "___debug_*",
                ]),
            ]
        ),
    ],
    swiftLanguageModes: [.v5]
)
