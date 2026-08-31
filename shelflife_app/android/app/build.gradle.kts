import java.util.Properties
import java.io.File
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing credentials, kept out of the repo.
//
// `android/key.properties` is gitignored and holds the keystore path and its
// passwords. It is absent on a fresh clone, and that is not a failure: the
// build falls back to debug signing so `flutter build apk` still produces a
// runnable artifact. Only a distributable build needs the real key.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKey = keystorePropertiesFile.exists()
if (hasReleaseKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

/// Resolves `storeFile` relative to key.properties, not to the app module.
///
/// This is the fix for a CI failure that cost an eleven-minute build. The
/// workflow writes `storeFile=release.jks` beside key.properties in `android/`,
/// but `file(path)` inside `app/build.gradle.kts` resolves against
/// `android/app/` -- so Gradle looked for `android/app/release.jks`, found
/// nothing, and failed at `validateSigningRelease` *after* compiling
/// everything. It never showed up locally because a local key.properties
/// written by tools/setup_signing.py holds an absolute path.
///
/// A path written in a file should be relative to that file. Anything else is a
/// trap for whoever writes the next one by hand.
fun resolveKeystore(path: String): File {
    val candidate = File(path)
    return if (candidate.isAbsolute) candidate
    else File(keystorePropertiesFile.parentFile, path)
}

android {
    namespace = "com.shelflife.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // ML Kit and flutter_local_notifications use java.time APIs that are
        // not on older Android runtimes without this.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "com.shelflife.app"
        // Flutter's default, currently 24 (Android 7.0). Comfortably above the
        // floor for mobile_scanner and ML Kit, which both need 21.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storePassword = keystoreProperties["storePassword"] as String

                val declared = keystoreProperties["storeFile"] as String?
                    ?: throw GradleException(
                        "android/key.properties exists but has no storeFile. " +
                        "Delete the file to build debug-signed, or point it at " +
                        "the keystore.")
                val resolved = resolveKeystore(declared)
                // Fail now, at configuration time, rather than after Gradle has
                // compiled the whole app and reached validateSigningRelease.
                if (!resolved.exists()) {
                    throw GradleException(
                        "The signing keystore is missing.\n" +
                        "  key.properties says : " + declared + "\n" +
                        "  which resolves to   : " + resolved.absolutePath + "\n" +
                        "A relative path here is taken relative to " +
                        "android/key.properties. Fix the path, or delete " +
                        "key.properties to build debug-signed.")
                }
                storeFile = resolved
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                // Debug-signed, so the build still runs and installs. It is not
                // suitable for distribution, and INSTALL.md says so.
                signingConfigs.getByName("debug")
            }
            // Shrinking is off deliberately. ML Kit's text recogniser resolves
            // model classes reflectively, and R8 strips them unless every rule
            // is right — the failure mode is a release APK where OCR silently
            // returns nothing, which is exactly the kind of bug that only
            // appears after shipping. The size cost is a few MB.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
