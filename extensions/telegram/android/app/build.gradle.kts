plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val targetAbi = providers.environmentVariable("TARGET_ABI").orNull

android {
    namespace = "lightly.tool.plugin.telegram"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "lightly.tool.plugin.telegram"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            when (targetAbi) {
                "arm64-v8a" -> abiFilters += setOf("arm64-v8a")
                "armeabi-v7a" -> abiFilters += setOf("armeabi-v7a")
            }
        }
    }

    signingConfigs {
        create("release") {
            storeFile = rootProject.file("../../../android/app/upload-keystore.jks")
            storePassword = providers.environmentVariable("KEYSTORE_PASSWORD").orNull
                ?: "android"
            keyAlias = "upload"
            keyPassword = providers.environmentVariable("KEY_PASSWORD").orNull
                ?: "android"
        }
    }

    buildTypes {
        release {
            val releaseConfig = signingConfigs.getByName("release")
            signingConfig = if (releaseConfig.storeFile?.exists() == true) {
                releaseConfig
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"))
        }
    }
}

flutter {
    source = "../.."
}
