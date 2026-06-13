// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "CodexQuota",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "CodexQuotaCore",
            targets: ["CodexQuotaCore"]
        ),
        .executable(
            name: "CodexQuotaCoreChecks",
            targets: ["CodexQuotaCoreChecks"]
        ),
        .executable(
            name: "CodexQuotaInspector",
            targets: ["CodexQuotaInspector"]
        ),
        .executable(
            name: "CodexQuotaRefreshOnce",
            targets: ["CodexQuotaRefreshOnce"]
        )
    ],
    targets: [
        .target(
            name: "CodexQuotaCore",
            path: "Sources/CodexQuotaCore"
        ),
        .executableTarget(
            name: "CodexQuotaCoreChecks",
            dependencies: ["CodexQuotaCore"],
            path: "Tests/CodexQuotaCoreChecks"
        ),
        .executableTarget(
            name: "CodexQuotaInspector",
            dependencies: ["CodexQuotaCore"],
            path: "Sources/CodexQuotaInspector"
        ),
        .executableTarget(
            name: "CodexQuotaRefreshOnce",
            dependencies: ["CodexQuotaCore"],
            path: "Sources/CodexQuotaRefreshOnce"
        )
    ]
)
