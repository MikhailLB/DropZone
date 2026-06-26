import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after Android + Kotlin.
    id("dev.flutter.flutter-gradle-plugin")
}

// The Google Services plugin requires `google-services.json`. When that
// file is not yet checked in (during early development), applying the
// plugin would fail with "File google-services.json is missing".
// Apply it conditionally — Firebase is still optional at runtime via the
// try/catch in main.dart.
val googleServicesJson = file("google-services.json")
if (googleServicesJson.exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasKeystore = keystorePropertiesFile.exists()
if (hasKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.dropzone.dropzonegame"
    // Targeting 36 here too — required by the override registered in the
    // root build.gradle.kts (otherwise transitive plugin deps fail with
    // "requires libraries and applications that depend on it to compile
    // against version 36 or later").
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Needed by flutter_local_notifications 18.x — it pulls in
        // java.time.* APIs that are unavailable on API 24–25 unless we
        // explicitly desugar them.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.dropzone.dropzonegame"
        // minSdk 30 — Android 11+. Matches the shell template recommendation
        // and keeps the per-version branches in the keyboard handling logic
        // simple.
        minSdk = 30
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    if (hasKeystore) {
        signingConfigs {
            create("release") {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (hasKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

flutter {
    source = "../.."
}
