import java.io.File
import java.io.FileNotFoundException

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val targetAbi = providers.environmentVariable("TARGET_ABI").orNull
val buildVersionLabel = providers.environmentVariable("BUILD_VERSION_LABEL").orNull
val excludedAbis = when (targetAbi) {
    "arm64-v8a" -> listOf("armeabi-v7a", "x86", "x86_64")
    "armeabi-v7a" -> listOf("arm64-v8a", "x86", "x86_64")
    else -> emptyList()
}

// 自动版本管理：从 Git commit count 计算，确保单调递增
// 使用偏移量 5000 避免与旧版本冲突
val buildVersionCode: Int = try {
    val commitCount = providers.exec {
        workingDir(rootDir.parentFile)
        commandLine("git", "rev-list", "--count", "HEAD")
    }.standardOutput.asText.get().trim().toIntOrNull() ?: 1
    5000 + commitCount
} catch (e: Exception) {
    5001
}

android {
    namespace = "lightly.tool"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "lightly.tool"
        // Opus 编码库需要 API 21+ (Android 5.0)
        // Android 7 = API 24, 完全兼容
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Keep Android versionCode monotonic for adb upgrades while allowing
        // the user-facing version label to follow semantic +build notation.
        versionCode = buildVersionCode ?: 4032
        versionName = buildVersionLabel ?: "${flutter.versionName}+${flutter.versionCode}"

        ndk {
            when (targetAbi) {
                "arm64-v8a" -> abiFilters += setOf("arm64-v8a")
                "armeabi-v7a" -> abiFilters += setOf("armeabi-v7a")
            }
        }
    }

    signingConfigs {
        create("release") {
            storeFile = file("upload-keystore.jks")
            storePassword = providers.environmentVariable("KEYSTORE_PASSWORD").orNull
                ?: "android"
            keyAlias = "upload"
            keyPassword = providers.environmentVariable("KEY_PASSWORD").orNull
                ?: "android"
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".test"
        }
        getByName("profile") {
            applicationIdSuffix = ".profile"
            signingConfig = signingConfigs.getByName("debug")
        }
        release {
            val releaseConfig = signingConfigs.findByName("release")
            val keystoreExists = releaseConfig?.storeFile?.exists() ?: false
            println("[Signing] Release keystore path: ${releaseConfig?.storeFile}")
            println("[Signing] Release keystore exists: $keystoreExists")
            
            signingConfig = if (keystoreExists) {
                println("[Signing] Using release keystore for signing")
                releaseConfig
            } else {
                println("[Signing] Warning: Release keystore not found, using debug signing")
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }

    packaging {
        jniLibs {
            excludedAbis.forEach { abi ->
                excludes += "**/$abi/*.so"
            }
        }
    }
}

dependencies {
    implementation("androidx.webkit:webkit:1.12.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    testImplementation("junit:junit:4.13.2")
}

flutter {
    source = "../.."
}

// 版本号管理由 scripts/build_multi_abi.sh 统一控制
// 保持多 ABI 构建使用相同的 versionCode
