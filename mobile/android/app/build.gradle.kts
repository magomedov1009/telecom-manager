import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val playReleaseRequested =
    project.findProperty("PLAY_STORE_RELEASE") == "true" ||
        System.getenv("PLAY_STORE_RELEASE") == "true"
val uploadKeyPropertiesFile = rootProject.file("key.properties")
val uploadKeyProperties = Properties()
if (playReleaseRequested) {
    if (!uploadKeyPropertiesFile.isFile) {
        throw GradleException(
            "Google Play signing requires mobile/android/key.properties; keep this file and the upload key out of Git.",
        )
    }
    uploadKeyPropertiesFile.inputStream().use(uploadKeyProperties::load)
}

android {
    namespace = "ru.telecommanager.telecom_manager_mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    flavorDimensions += "distribution"
    productFlavors {
        create("direct") {
            dimension = "distribution"
        }
        create("play") {
            dimension = "distribution"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "ru.telecommanager.telecom_manager_mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (playReleaseRequested) {
        signingConfigs.create("playUpload") {
            val requiredProperty: (String) -> String = { key ->
                uploadKeyProperties.getProperty(key)?.takeIf { it.isNotBlank() }
                    ?: throw GradleException(
                        "Missing '$key' in mobile/android/key.properties",
                    )
            }
            storeFile = rootProject.file(requiredProperty("storeFile"))
            storePassword = requiredProperty("storePassword")
            keyAlias = requiredProperty("keyAlias")
            keyPassword = requiredProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = if (playReleaseRequested) {
                signingConfigs.getByName("playUpload")
            } else {
                // Keep GitHub/test APK signing separate from the Play upload key.
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
