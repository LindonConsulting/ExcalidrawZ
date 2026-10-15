// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TutorKit",
    platforms: [.macOS(.v13), .iOS(.v16)],
    products: [
        .library(name: "TutorKit", targets: ["TutorModels", "TutorStore", "TutorAI", "TutorRanking", "TutorSync", "LessonspaceImport"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.0"),
    ],
    targets: [
        .target(name: "TutorModels"),
        .target(
            name: "TutorStore",
            dependencies: ["TutorModels", "TutorSync", .product(name: "GRDB", package: "GRDB.swift")]
        ),
        .target(name: "TutorAI", dependencies: ["TutorModels"]),
        .target(name: "TutorRanking", dependencies: ["TutorModels"]),
        .target(name: "TutorSync", dependencies: ["TutorModels"]),
        .target(name: "LessonspaceImport"),
        .testTarget(
            name: "TutorKitTests",
            dependencies: ["TutorModels", "TutorStore", "TutorAI", "TutorRanking", "TutorSync", "LessonspaceImport"]
        ),
    ]
)
