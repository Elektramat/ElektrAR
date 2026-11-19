// swift-tools-version:5.9
// Lets `swift test` run the pure core logic (pricing, cart, measuring) on the Mac,
// without a simulator. The app target compiles the same files from Kabelmeter/Core.
import PackageDescription

let package = Package(
    name: "KabelmeterCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    targets: [
        .target(name: "KabelmeterCore", path: "Kabelmeter/Core"),
        .testTarget(name: "KabelmeterTests", dependencies: ["KabelmeterCore"], path: "KabelmeterTests"),
    ]
)
