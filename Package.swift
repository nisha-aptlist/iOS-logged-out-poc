// swift-tools-version: 6.0
import PackageDescription

/// Feature modules live in SPM so they build, test, and preview independently of
/// the app shell. The app target itself is declared in `project.yml` (XcodeGen)
/// because SwiftPM cannot produce an iOS `.app` bundle.
///
/// Dependency direction is strictly one way:
///
///     ALCore  ←  ALAuth, ALLocation, ALDesignSystem
///        ↑                    ↑
///     ALLaunchFeature, ALMapFeature, ALListingFeature
///                             ↑
///                        ALAppFeature
///
/// No feature module imports another feature module. Cross-feature coordination
/// happens in ALAppFeature through `AppCoordinator`, which keeps the graph acyclic and
/// lets any feature be built in isolation.
let package = Package(
    name: "ApartmentListMap",
    defaultLocalization: "en",
    // macOS is declared even though this is an iOS app.
    //
    // Without it, the macOS deployment floor falls back to an ancient default,
    // and Xcode building any scheme against "My Mac" fails in ALCore with
    // "'Duration' is only available in macOS 13.0 or newer" and "'Task' is
    // only available in macOS 10.15 or newer". ALCore is UIKit-free, so it
    // compiles for macOS once the floor is honest; the UI modules are iOS-only
    // by their imports.
    //
    // To build the APP, select an iOS Simulator destination, not My Mac.
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ALCore", targets: ["ALCore"]),
        .library(name: "ALDesignSystem", targets: ["ALDesignSystem"]),
        .library(name: "ALAuth", targets: ["ALAuth"]),
        .library(name: "ALLocation", targets: ["ALLocation"]),
        .library(name: "ALLaunchFeature", targets: ["ALLaunchFeature"]),
        .library(name: "ALMapFeature", targets: ["ALMapFeature"]),
        .library(name: "ALListingFeature", targets: ["ALListingFeature"]),
        .library(name: "ALAppFeature", targets: ["ALAppFeature"])
    ],
    targets: [
        .target(name: "ALCore"),

        .target(
            name: "ALDesignSystem",
            dependencies: ["ALCore"],
            resources: [.process("Resources")]
        ),

        .target(name: "ALAuth", dependencies: ["ALCore"]),
        .target(name: "ALLocation", dependencies: ["ALCore"]),

        .target(
            name: "ALLaunchFeature",
            dependencies: ["ALCore", "ALDesignSystem"]
        ),
        // iOS-only by its imports: MKAnnotationView, UILabel, UIColor. It has
        // no macOS story and is not meant to have one.
        .target(
            name: "ALMapFeature",
            dependencies: ["ALCore", "ALDesignSystem", "ALLocation"]
        ),
        .target(
            name: "ALListingFeature",
            dependencies: ["ALCore", "ALDesignSystem", "ALAuth"]
        ),
        .target(
            name: "ALAppFeature",
            dependencies: [
                "ALCore", "ALDesignSystem", "ALAuth", "ALLocation",
                "ALLaunchFeature", "ALMapFeature", "ALListingFeature"
            ]
        ),

        .testTarget(name: "ALCoreTests", dependencies: ["ALCore"]),
        .testTarget(name: "ALMapFeatureTests", dependencies: ["ALMapFeature", "ALCore"]),
        .testTarget(name: "ALLocationTests", dependencies: ["ALLocation"])
    ],
    swiftLanguageModes: [.v6]
)
