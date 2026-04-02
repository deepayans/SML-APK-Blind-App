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

    // Prevent duplicate native library conflicts between ML Kit and MediaPipe
    packaging {
        jniLibs {
            pickFirsts += setOf(
                "lib/arm64-v8a/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/x86/libc++_shared.so",
                "lib/x86_64/libc++_shared.so"
            )
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    // ── On-device vision — ML Kit ──────────────────────────────────────────
    implementation("com.google.mlkit:image-labeling:17.0.8")
    implementation("com.google.mlkit:object-detection:17.0.1")
    implementation("com.google.mlkit:text-recognition:16.0.0")

    // ── On-device LLM — MediaPipe Gemma 2B ────────────────────────────────
    // tasks-genai 0.10.14 is the latest confirmed stable release.
    // Jetifier MUST be disabled (gradle.properties) or this transform fails.
    implementation("com.google.mediapipe:tasks-genai:0.10.14")

    // ── Support ────────────────────────────────────────────────────────────
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.google.code.gson:gson:2.10.1")
}
