// swift-tools-version: 6.0
import PackageDescription
let package = Package(name: "Clementine", platforms: [.macOS(.v13)], products: [.executable(name: "Clementine", targets: ["Clementine"])], targets: [.executableTarget(name: "Clementine", swiftSettings: [.swiftLanguageMode(.v5)]), .testTarget(name: "ClementineTests", dependencies: ["Clementine"])])
