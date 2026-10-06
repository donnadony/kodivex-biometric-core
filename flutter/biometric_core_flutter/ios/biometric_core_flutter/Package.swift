// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

// BiometricCore vive en este mismo repo: ios/BiometricCore.
// Flutter no compila el plugin desde aquí, sino desde un symlink en
// <app>/ios/Flutter/ephemeral/Packages/.packages/biometric_core_flutter, y SwiftPM
// resuelve las rutas relativas desde ese symlink. Por eso resolvemos primero el
// symlink y luego aplicamos la ruta relativa hacia la raíz del repo.
let pluginDirectory = URL(fileURLWithPath: Context.packageDirectory).resolvingSymlinksInPath()
let biometricCorePath = pluginDirectory
    .appendingPathComponent("../../../../ios/BiometricCore")
    .standardizedFileURL
    .path

let package = Package(
    name: "biometric_core_flutter",
    platforms: [
        .iOS("15.0")
    ],
    products: [
        // El nombre de la librería usa guiones en vez de guiones bajos, como pide Flutter.
        .library(name: "biometric-core-flutter", targets: ["biometric_core_flutter"])
    ],
    dependencies: [
        // Lo provee Flutter (3.44 o superior) junto al symlink del plugin.
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(name: "BiometricCore", path: biometricCorePath)
    ],
    targets: [
        .target(
            name: "biometric_core_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "BiometricCore", package: "BiometricCore")
            ],
            resources: [
                // El plugin no usa required reason APIs; si en el futuro hace falta un
                // PrivacyInfo.xcprivacy, agregarlo en Sources/biometric_core_flutter y descomentar:
                // .process("PrivacyInfo.xcprivacy"),
            ]
        )
    ]
)
