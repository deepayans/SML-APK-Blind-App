plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.vision_assistant"
    compileSdk = 35
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
        targetSdk = 35
        versionCode = flutter.versionCode()
        versionName = flutter.versionName()

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
    // ── On-device vision (ML Kit) ──────────────────────────────────────────
    // All three libraries work fully offline after the first launch.
    // Models are bundled inside the library or cached via Play Services.
    implementation("com.google.mlkit:image-labeling:17.0.9")
    implementation("com.google.mlkit:object-detection:17.0.2")
    implementation("com.google.mlkit:text-recognition:16.0.1")

    // ── On-device language generation (MediaPipe GenAI) ────────────────────
    // Gemma 2B is used to turn ML Kit detections into natural-language
    // descriptions.  The model file is downloaded once at first launch.
    // MediaPipe Tasks GenAI is on Maven Central — no custom repos needed.
    implementation("com.google.mediapipe:tasks-genai:0.10.22")

    // ── Support ────────────────────────────────────────────────────────────
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.google.code.gson:gson:2.10.1")
}
