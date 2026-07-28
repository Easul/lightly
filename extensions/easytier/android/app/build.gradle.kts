plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val targetAbi = providers.environmentVariable("TARGET_ABI").orNull
val supportedAbis = when (targetAbi) {
    "arm64-v8a" -> setOf("arm64-v8a")
    "armeabi-v7a" -> setOf("armeabi-v7a")
    else -> setOf("arm64-v8a", "armeabi-v7a")
}

android {
    namespace = "lightly.tool.plugin.easytier"
    compileSdk = 36
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }
    defaultConfig {
        applicationId = "lightly.tool.plugin.easytier"
        minSdk = 24
        targetSdk = 36
        versionCode = 1
        versionName = "1.0.0"
        ndk { abiFilters += supportedAbis }
    }
    signingConfigs {
        create("release") {
            storeFile = rootProject.file("../../../android/app/upload-keystore.jks")
            storePassword = providers.environmentVariable("KEYSTORE_PASSWORD").orNull ?: "android"
            keyAlias = "upload"
            keyPassword = providers.environmentVariable("KEY_PASSWORD").orNull ?: "android"
        }
    }
    buildTypes {
        release {
            val releaseConfig = signingConfigs.getByName("release")
            signingConfig = if (releaseConfig.storeFile?.exists() == true) releaseConfig
                else signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
    packaging {
        jniLibs {
            useLegacyPackaging = false
            setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
                .minus(supportedAbis)
                .forEach { abi -> excludes += "**/$abi/*.so" }
        }
    }
    buildFeatures {
        aidl = true
        buildConfig = false
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.json:json:20180813")
}
