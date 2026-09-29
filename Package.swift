// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Narly",
    defaultLocalization: "en",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Narly", targets: ["NarlyApp"])],
    targets: [
        .target(name: "PickerKit", resources: [.process("Resources")]),
        .executableTarget(name: "NarlyApp", dependencies: ["PickerKit"]),
        .executableTarget(name: "NarlyIconExporter", dependencies: ["PickerKit"]),
        .testTarget(name: "PickerKitTests", dependencies: ["PickerKit"])
    ]
)
