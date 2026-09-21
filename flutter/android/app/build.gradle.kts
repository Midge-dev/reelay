import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing identity — key.properties + app/release.keystore are both
// gitignored, same pattern the Kotlin app used (see its build.gradle.kts
// history). Falls back to the debug key if either is missing, so a fresh
// checkout or CI runner without the real secrets still builds (unsigned in
// effect, since it's the debug key), rather than failing outright.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    // Matches the real Kotlin source package the Flutter engine embeds at
    // (android/app/src/main/kotlin/com/reelay/reelay/) — distinct from
    // applicationId below by design; renaming this would mean moving the
    // MainActivity.kt package too, which buys nothing.
    namespace = "com.reelay.reelay"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Cutover complete (2026-09-20): this is now the production id,
        // matching what the retired Kotlin app shipped as. Signed with the
        // same release keystore below so this installs as an upgrade on any
        // device that already has the Kotlin build — EXCEPT wherever that
        // Kotlin build was itself installed as a debug build (the Shield's
        // "watch something tonight" fallback was) — Android refuses an
        // install over a signature mismatch, so that one needs an explicit
        // uninstall of the old com.reelay.tv first, losing its local
        // Plex/relay state.
        applicationId = "com.reelay.tv"
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

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
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
