// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Hostshift",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Hostshift", targets: ["Hostshift"])],
    targets: [
        .target(name: "HostsCore"),
        .executableTarget(name: "Hostshift", dependencies: ["HostsCore"]),
        .executableTarget(name: "HostshiftHelper", dependencies: ["HostsCore"]),
        .executableTarget(name: "HostsCoreChecks", dependencies: ["HostsCore"], path: "scripts", exclude: ["build.sh", "test.sh", "icon.swift", "helper-checks.swift", "sdk.sh"], sources: ["checks.swift"])
    ]
)
