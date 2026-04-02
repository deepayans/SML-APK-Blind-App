plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vision_assistant"
    compileSdk = 34
    ndkVersion = "26.1.10909125"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.vision_assistant"
        minSdk = 26
        targetSdk = 34
        // Hardcoded to avoid flutter.versionCode type ambiguity in Kotlin DSL.
        // Flutter 3.22 exposes versionCode as a method returning String in
        // some plugin variants — using a literal Int is always safe.
        versionCode = 1
        versionName = "1.0.0"

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // vision-common must be pinned explicitly — it provides InputImage.width/height
    // which are used in MlcLlmPlugin.  Without this the transitive version from
    // image-labeling may be too old (pre-17.3) and those properties won't resolve.
    implementation("com.google.mlkit:vision-common:17.3.0")

    // Core ML Kit detectors — all fully offline, zero runtime download
    implementation("com.google.mlkit:image-labeling:17.0.8")
    implementation("com.google.mlkit:object-detection:17.0.1")
    implementation("com.google.mlkit:text-recognition:16.0.0")

    // Coroutines
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
