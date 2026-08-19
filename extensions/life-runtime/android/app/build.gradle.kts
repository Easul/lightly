import org.gradle.api.tasks.Sync

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val targetAbi = providers.environmentVariable("TARGET_ABI").orNull
val pluginVersionCode = providers.environmentVariable("PLUGIN_VERSION_CODE").orNull?.toIntOrNull() ?: 1
val pluginVersionName = providers.environmentVariable("PLUGIN_VERSION_NAME").orNull ?: "1.0.0"
val supportedAbis = when (targetAbi) {
    "arm64-v8a" -> setOf("arm64-v8a")
    "armeabi-v7a" -> setOf("armeabi-v7a")
    else -> setOf("arm64-v8a", "armeabi-v7a")
}
val runtimeBinDir = providers.environmentVariable("LIFE_RUNTIME_BIN_DIR").orNull
    ?.takeIf { it.isNotBlank() }
    ?.let(::file)
val runtimeGitDir = providers.environmentVariable("LIFE_RUNTIME_GIT_DIR").orNull
    ?.takeIf { it.isNotBlank() }
    ?.let(::file)
val runtimeNativeLibDir = layout.buildDirectory.dir("generated/life-runtime-native-libs")
val prepareRuntimeNativeLibs = tasks.register<Sync>("prepareLifeRuntimeNativeLibs") {
    runtimeBinDir?.let { source ->
        from(source) {
            include("mindgit", "liferecord")
            eachFile { path = "arm64-v8a/lib${name}.so" }
            includeEmptyDirs = false
        }
    }
    runtimeGitDir?.let { source ->
        from(File(source, "native/arm64-v8a")) {
            include("libgit.so", "libgit_remote_http.so")
            eachFile { path = "arm64-v8a/$name" }
            includeEmptyDirs = false
        }
    }
    into(runtimeNativeLibDir)
}

android {
    namespace = "lightly.tool.plugin.liferuntime"
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = JavaVersion.VERSION_17.toString() }

    defaultConfig {
        applicationId = "lightly.tool.plugin.liferuntime"
        minSdk = 24
        targetSdk = 36
        versionCode = pluginVersionCode
        versionName = pluginVersionName
        ndk { abiFilters += supportedAbis }
    }

    sourceSets.getByName("main").jniLibs.srcDir(runtimeNativeLibDir)
    runtimeGitDir?.let { sourceSets.getByName("main").assets.srcDir(File(it, "assets")) }
    tasks.matching {
        it.name != "prepareLifeRuntimeNativeLibs" &&
            (it.name.contains("JniLib", ignoreCase = true) ||
                it.name.contains("NativeLib", ignoreCase = true))
    }
        .configureEach { dependsOn(prepareRuntimeNativeLibs) }

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
            // The bundled ELF files are launched with execve, so they must be
            // extracted to nativeLibraryDir instead of remaining mmap-only in
            // the APK.
            useLegacyPackaging = true
            setOf("arm64-v8a", "armeabi-v7a", "x86", "x86_64")
                .minus(supportedAbis)
                .forEach { abi -> excludes += "**/$abi/*.so" }
        }
    }

    buildFeatures { aidl = true; buildConfig = false }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
}
