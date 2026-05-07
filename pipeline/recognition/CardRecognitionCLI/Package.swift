// swift-tools-version: 5.9
//
// CardRecognitionCLI — macOS Swift package that runs the iOS scanner's
// recognition pipeline against still-image candidates from the pipeline
// staging queue. Designed to run in a `macos-15` GitHub Actions runner.
//
// Build:
//     cd pipeline/recognition/CardRecognitionCLI
//     swift build -c release
//
// The compiled binary lives at:
//     .build/release/cardreckon
//
// See README.md for the runtime contract.

import PackageDescription

let package = Package(
    name: "CardRecognitionCLI",
    platforms: [
        // Vision feature-print revision 2 (the index we ship in
        // BOBAPlaybook/feature-prints.bin) requires macOS 14+.
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cardreckon", targets: ["CardRecognitionCLI"])
    ],
    targets: [
        .executableTarget(
            name: "CardRecognitionCLI",
            path: "Sources/CardRecognitionCLI"
        )
    ]
)
