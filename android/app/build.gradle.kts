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
    // ── Vision ML (ML Kit) ─────────────────────────────────────────────────
    // On-device vision models — zero extra download required.
    // Object Detection: bounding boxes → spatial positions (left/centre/right)
    // Image Labeling:   400+ categories → specific labels (person, chair, tv…)
    // Text Recognition: OCR → reads visible text
    implementation("com.google.mlkit:object-detection:17.0.0")
    implementation("com.google.mlkit:image-labeling:17.0.8")
    implementation("com.google.mlkit:text-recognition:16.0.0")

    // ── Language SLM (Gemma 2B via Google AI Edge) ─────────────────────────
    // tasks-genai:0.10.22 is the first version that introduced this artifact.
    // Requires android.enableJetifier=false (set in gradle.properties).
    // It uses Google's LiteRT (Lite RunTime) engine internally — same engine
    // as TensorFlow Lite, just rebranded. No cloud calls, no API keys.
    // Jetifier is disabled in gradle.properties (mandatory for this dep).
    implementation("com.google.mediapipe:tasks-genai:0.10.22")

    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
}
