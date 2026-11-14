// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConsumoBateria",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ConsumoBateria",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("CoreWLAN"),
                .linkedFramework("SystemConfiguration"),
            ]
        )
    ]
)
