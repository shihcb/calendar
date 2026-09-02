// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "LuminaCalendar",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "LuminaCalendar",
            targets: ["LuminaCalendar"]
        )
    ],
    targets: [
        .executableTarget(
            name: "LuminaCalendar",
            path: ".",
            sources: [
                "CalendarApp.swift",
                "ContentView.swift",
                "EventKitManager.swift",
                "HapticManager.swift"
            ]
        )
    ]
)
