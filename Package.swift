// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Paddlr",
    platforms: [
        .macOS(.v11)
    ],
    products: [
        .executable(name: "Paddlr", targets: ["Paddlr"]),
        .executable(name: "PaddlrDetect", targets: ["PaddlrDetect"]),
        .executable(name: "PaddlrDiagnostics", targets: ["PaddlrDiagnostics"]),
        .executable(name: "PaddlrHIDProbe", targets: ["PaddlrHIDProbe"]),
        .executable(name: "PaddlrKeyOutputPOC", targets: ["PaddlrKeyOutputPOC"]),
        .executable(name: "PaddlrRawReportProbe", targets: ["PaddlrRawReportProbe"]),
        .executable(name: "PaddlrSelfTest", targets: ["PaddlrSelfTest"])
    ],
    targets: [
        .target(name: "PaddlrCore"),
        .executableTarget(
            name: "Paddlr",
            dependencies: ["PaddlrCore"]
        ),
        .executableTarget(
            name: "PaddlrDetect",
            dependencies: ["PaddlrCore"]
        ),
        .executableTarget(
            name: "PaddlrDiagnostics",
            dependencies: ["PaddlrCore"]
        ),
        .executableTarget(name: "PaddlrHIDProbe"),
        .executableTarget(
            name: "PaddlrKeyOutputPOC",
            dependencies: ["PaddlrCore"]
        ),
        .executableTarget(name: "PaddlrRawReportProbe"),
        .executableTarget(
            name: "PaddlrSelfTest",
            dependencies: ["PaddlrCore"]
        )
    ]
)
