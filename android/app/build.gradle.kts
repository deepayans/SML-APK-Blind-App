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
    // MLC LLM Android runtime — published on JitPack
    // mlc4j bundles the MLC engine + TVM runtime for arm64
    implementation("com.github.mlc-ai:mlc-llm-android:v0.1.1")
    implementation("com.google.code.gson:gson:2.10.1")
}
