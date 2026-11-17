import org.gradle.api.tasks.PathSensitivity

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.zettax.app"
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
        applicationId = "com.zettax.app"
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
            // Select signing by flavor, never by an optional distribution flag.
            // A Play release without its upload key stays unsigned for auditing.
            signingConfig = null
        }
    }

    productFlavors.getByName("direct").signingConfig = signingConfigs.getByName("debug")
    productFlavors.getByName("play").signingConfig = signingConfigs.findByName("playUpload")

}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

// Flutter 3.44.3 can leave flavored JNI merge tasks UP-TO-DATE after Dart
// recompiles (flutter/flutter#187553). Track the generated native libraries
// explicitly so APKs/AABs package the code compiled by this build.
androidComponents.onVariants { variant ->
    val taskSuffix = variant.name.replaceFirstChar { it.uppercaseChar() }
    tasks.matching { it.name == "merge${taskSuffix}JniLibFolders" }.configureEach {
        dependsOn("copyJniLibsflutterBuild${taskSuffix}")
        inputs.dir(layout.buildDirectory.dir("intermediates/flutter/${variant.name}/jniLibs"))
            .withPropertyName("zettaxFlutterNativeLibraries")
            .withPathSensitivity(PathSensitivity.RELATIVE)
    }
}
