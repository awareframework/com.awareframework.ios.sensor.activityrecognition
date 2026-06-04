// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "com.awareframework.ios.sensor.activityrecognition",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "com.awareframework.ios.sensor.activityrecognition",
            targets: [
                "com.awareframework.ios.sensor.activityrecognition"
            ]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/awareframework/com.awareframework.ios.core.git", from: "1.1.0")
    ],
    targets: [
        .target(
            name: "com.awareframework.ios.sensor.activityrecognition",
            dependencies: [
                .product(name: "com.awareframework.ios.core",
                         package: "com.awareframework.ios.core", condition: .when(platforms: [.iOS]))
            ],
            path: "Sources/com.awareframework.ios.sensor.activityrecognition"
        ),
        .testTarget(
            name: "com.awareframework.ios.sensor.activityrecognitionTests",
            dependencies: ["com.awareframework.ios.core",
                           "com.awareframework.ios.sensor.activityrecognition"]
        )
    ],
    swiftLanguageModes: [.v5]
)
