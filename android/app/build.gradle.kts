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
    // ── Vision SML (ML Kit) — offline, zero download, instant ─────────────
    // These small on-device models extract structured data from the camera:
    // object positions and any visible text.  Results feed into Gemma.
    implementation("com.google.mlkit:object-detection:17.0.0")
    implementation("com.google.mlkit:text-recognition:16.0.0")

    // ── Language SML (MediaPipe Gemma 2B) — downloaded on first launch ────
    // Gemma 2B turns the ML Kit detections into fluent natural language.
    // Jetifier MUST be disabled (gradle.properties) — MediaPipe is already
    // AndroidX and Jetifier's ASM transformer crashes on its bytecode.
    implementation("com.google.mediapipe:tasks-genai:0.10.14")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
