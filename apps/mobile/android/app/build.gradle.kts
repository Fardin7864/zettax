plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.primevest.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    buildFeatures {
        buildConfig = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.primevest.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "distribution"
    productFlavors {
        create("direct") {
            dimension = "distribution"
        }
        create("play") {
            dimension = "distribution"
        }
    }

    val playUploadKeyPath = System.getenv("ZETTAX_PLAY_UPLOAD_KEYSTORE")
    val playUploadPassword = System.getenv("ZETTAX_PLAY_UPLOAD_PASSWORD")
    signingConfigs {
        if (!playUploadKeyPath.isNullOrBlank() && !playUploadPassword.isNullOrBlank()) {
            create("playUpload") {
                storeFile = file(playUploadKeyPath)
                storePassword = playUploadPassword
                keyAlias = "zettax-upload"
                keyPassword = playUploadPassword
            }
        }
    }

    buildTypes {
        release {
            // Preserve the original signing certificate for direct APK updates.
            // The Play bundle uses a separate upload key when explicitly requested.
            signingConfig = if (System.getenv("ZETTAX_ANDROID_DISTRIBUTION") == "play") {
                signingConfigs.findByName("playUpload")
                    ?: error("Set ZETTAX_PLAY_UPLOAD_KEYSTORE and ZETTAX_PLAY_UPLOAD_PASSWORD before building a Play release.")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
