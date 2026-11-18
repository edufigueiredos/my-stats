// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConsumoBateria",
    platforms: [.macOS(.v14)],
    dependencies: [
        // Atualização automática pelas releases do GitHub (docs/atualizacao.md). Versão exata, a mesma do Bridge Loop.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0"),
    ],
    targets: [
        // Protocolo entre o app e o ajudante das ventoinhas (docs/ventoinhas.md).
        .target(name: "VentoinhasXPC"),
        // Ajudante root que muda a rotação das ventoinhas no SMC; registrado pelo app com SMAppService.
        .executableTarget(
            name: "MyStatsVentoinhas",
            dependencies: ["VentoinhasXPC"],
            // Callbacks do NSXPC não são Sendable; o estado fica todo numa fila serial (Central.fila).
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .executableTarget(
            name: "ConsumoBateria",
            dependencies: [.product(name: "Sparkle", package: "Sparkle"), "VentoinhasXPC"],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
                // Sparkle.framework: em Contents/Frameworks no app montado, ao lado do binário no swift build (--foto, --sensores).
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks",
                              "-Xlinker", "-rpath", "-Xlinker", "@executable_path"]),
            ]
        )
    ]
)
