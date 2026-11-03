// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SideQuest",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "SideQuest", targets: ["SideQuest"])],
    targets: [
        .executableTarget(
            name: "SideQuest",
            resources: [
                .copy("Resources/fonts"),
                .process("Resources/l10n")
            ]
        )
    ]
)
