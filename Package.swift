// swift-tools-version: 6.2
import PackageDescription

// Сборка и тесты требуют установленного Xcode (CLT не исполняет тесты - нет раннера xctest).
// LLM изолирован в таргете DopishiLLM с C++ interop (нужен для LocalLLMClient/llama.cpp),
// чтобы DopishiApp оставался без interop.
let package = Package(
    name: "Dopishi",
    platforms: [.macOS("14.0")],
    dependencies: [
        // Форк с патчами (BOS для .plain, batch.clear в Context.clear, logprob-аккумулятор) -
        // pin по ТОЧНОЙ ревизии, чтобы сборка была воспроизводима из чистого clone. Патчи также в
        // vendor-patches/localllmclient.patch.txt (база tattn @ cd971ff). См. форк ветку dopishi-patches.
        .package(url: "https://github.com/Fedotoff-Alex/LocalLLMClient.git", revision: "209abcdc58cfe4af858f056125ed85024f447a91"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0")
    ],
    targets: [
        .target(name: "DopishiCore"),
        // Локальная память контекста (SQLite через GRDB). C-interop (SQLite), без C++ -
        // отдельный таргет, чтобы DopishiCore оставался без зависимостей и легко тестировался.
        .target(
            name: "DopishiMemory",
            dependencies: [
                "DopishiCore",
                .product(name: "GRDB", package: "GRDB.swift"),
            ]
        ),
        .target(
            name: "DopishiLLM",
            dependencies: [
                "DopishiCore",
                .product(name: "LocalLLMClient", package: "LocalLLMClient"),
                .product(name: "LocalLLMClientLlama", package: "LocalLLMClient"),
            ],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "DopishiApp",
            dependencies: ["DopishiCore", "DopishiLLM", "DopishiMemory"],
            swiftSettings: [
                // C++ interop заразен через import DopishiLLM (тянет C++ модуль llama.cpp),
                // поэтому потребитель тоже обязан быть в interop-режиме.
                .interoperabilityMode(.Cxx)
            ]
        ),
        .executableTarget(
            name: "DopishiBench",
            dependencies: ["DopishiCore", "DopishiLLM"],
            swiftSettings: [.interoperabilityMode(.Cxx)]
        ),
        .testTarget(
            name: "DopishiCoreTests",
            dependencies: ["DopishiCore"]
        ),
        .testTarget(
            name: "DopishiMemoryTests",
            dependencies: ["DopishiMemory"]
        ),
        .testTarget(
            name: "DopishiLLMTests",
            dependencies: ["DopishiLLM"],
            swiftSettings: [
                .interoperabilityMode(.Cxx)
            ]
        ),
    ]
)
