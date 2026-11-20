// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MaqamTrainer",
    platforms: [
        .iOS(.v16)
    ],
    products: [
        .executable(name: "MaqamTrainer", targets: ["MaqamTrainer"])
    ],
    targets: [
        .executableTarget(
            name: "MaqamTrainer",
            path: "Sources/MaqamTrainer",
            // Info.plist is excluded from the SPM target on purpose: SwiftPM
            // cannot place an Info.plist at an app-bundle root. The file is
            // kept in the source folder for the real app wrapper (Xcode
            // project / TestFlight build); the CI build below is a
            // compile-verification build only. See README.md.
            exclude: ["Info.plist"],
            resources: [
                // Teacher avatar asset catalog (contains the
                // "TeacherAvatar" placeholder image slot).
                .process("Assets.xcassets"),
                // Drop-in AI-teacher audio folder: manifest.json maps
                // each maqam id to its scale/phrase audio files.
                // Copied as a directory so Bundle.module can address
                // files under the "TeacherAudio" subdirectory.
                .copy("TeacherAudio")
            ]
        )
    ]
)
