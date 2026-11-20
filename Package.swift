// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hostshift",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Hostshift", targets: ["Hostshift"])],
    targets: [
        .target(name: "HostsCore"),
        .target(name: "ArgumentParserToolInfo", path: "Vendor/swift-argument-parser/Sources/ArgumentParserToolInfo"),
        .target(name: "ArgumentParser", dependencies: ["ArgumentParserToolInfo"], path: "Vendor/swift-argument-parser/Sources/ArgumentParser"),
        .executableTarget(name: "Hostshift", dependencies: ["HostsCore", "ArgumentParser"]),
        .executableTarget(name: "HostshiftHelper", dependencies: ["HostsCore"]),
        .executableTarget(name: "HostsCoreChecks", dependencies: ["HostsCore"], path: "scripts", exclude: ["build.sh", "test.sh", "sdk.sh", "package-dmg.sh", "icon.swift", "dmg-background.swift", "helper-checks.swift", "profile-checks.swift", "editor-checks.swift", "update-checks.swift"], sources: ["checks.swift"])
    ]
)
