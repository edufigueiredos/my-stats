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
        .executableTarget(
            name: "ConsumoBateria",
            dependencies: [.product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
            ]
        )
    ]
)
