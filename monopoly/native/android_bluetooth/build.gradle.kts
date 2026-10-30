// Compilar dentro de un proyecto Gradle Android: gradlew :android_bluetooth:assembleRelease
// y copiar el .aar a addons/magnates_bluetooth/bin/magnates-bluetooth-release.aar
plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.magnates.bluetooth"
    compileSdk = 35
    defaultConfig { minSdk = 24 }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    // Debe coincidir con la versión del editor (4.7.x).
    compileOnly("org.godotengine:godot:4.7.2.stable")
}
