plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.kodivex.biometric.flutter"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    // Módulo nativo del repo. En la app Flutter, agregar en settings.gradle.kts:
    //   include(":biometric-core"); project(":biometric-core").projectDir = file("../../../android/biometric-core")
    implementation(project(":biometric-core"))
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}
