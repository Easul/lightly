plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val tdlibVersion = "1.6.0"
val pluginVersionCode = providers.environmentVariable("PLUGIN_VERSION_CODE").orNull?.toIntOrNull() ?: 1
val pluginVersionName = providers.environmentVariable("PLUGIN_VERSION_NAME").orNull ?: "1.0.0"
val targetAbi = providers.environmentVariable("TARGET_ABI").orNull
val supportedAbis = when (targetAbi) {
    "arm64-v8a" -> setOf("arm64-v8a")
    "armeabi-v7a" -> setOf("armeabi-v7a")
    else -> setOf("arm64-v8a", "armeabi-v7a")
}
val tdlibJniDir = providers.environmentVariable("TDLIB_JNI_DIR").orNull?.let(::file)
    ?: rootProject.file("../.deps/tdlib-$tdlibVersion/jniLibs")

require(tdlibJniDir.isDirectory) {
    "TDLib JNI directory not found at $tdlibJniDir. " +
        "Run extensions/telegram/scripts/prepare_tdlib.sh or set TDLIB_JNI_DIR."
}
supportedAbis.forEach { abi ->
    require(File(tdlibJniDir, "$abi/libtdjson.so").isFile) {
        "TDLib $abi binary not found under $tdlibJniDir. " +
            "Run extensions/telegram/scripts/prepare_tdlib.sh again."
    }
}

android {
    namespace = "lightly.tool.plugin.telegram"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "lightly.tool.plugin.telegram"
        minSdk = 24
        targetSdk = 36
        versionCode = pluginVersionCode
        versionName = pluginVersionName

        ndk {
            abiFilters += supportedAbis
        }

        externalNativeBuild {
            cmake {
                arguments += "-DTDLIB_JNI_DIR=${tdlibJniDir.absolutePath}"
            }
        }
    }

    sourceSets {
        getByName("main") {
            jniLibs.srcDir(tdlibJniDir)
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
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
            signingConfig = if (releaseConfig.storeFile?.exists() == true) {
                releaseConfig
            } else {
                signingConfigs.getByName("debug")
            }
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
