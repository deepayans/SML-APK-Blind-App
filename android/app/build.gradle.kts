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
}

flutter {
    source = "../.."
}

dependencies {
    // mlc4j is NOT on any public Maven repo.
    // The CI workflow downloads it from the MLC LLM GitHub release
    // into android/app/libs/ before the build runs (see .github/workflows/build.yml).
    implementation(fileTree(mapOf("dir" to "libs", "include" to listOf("*.aar", "*.jar"))))

    // mlc4j transitive deps
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.7.3")
    implementation("com.google.code.gson:gson:2.10.1")
}
