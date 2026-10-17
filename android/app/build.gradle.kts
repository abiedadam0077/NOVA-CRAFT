import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

val envStorePath: String? = System.getenv("NOVA_KEYSTORE_PATH")
val envStorePassword: String? = System.getenv("NOVA_KEYSTORE_PASSWORD")
val envKeyAlias: String = System.getenv("NOVA_KEY_ALIAS") ?: "nova-craft"
val envKeyPassword: String? = System.getenv("NOVA_KEY_PASSWORD") ?: envStorePassword
val hasEnvSigning = !envStorePath.isNullOrEmpty() && !envStorePassword.isNullOrEmpty()
val hasFileSigning = keystorePropertiesFile.exists()
val hasReleaseSigning = hasEnvSigning || hasFileSigning

android {
    namespace = "io.github.abiedadam0077.novacraft"
    // Current AndroidX releases (pulled in by url_launcher and core) require
    // API 36 to compile. targetSdk stays at 35 so runtime behaviour and the
    // published permissions do not change.
    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "io.github.abiedadam0077.novacraft"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "1.0.0"
    }

    signingConfigs {
        // Keep a JAR (v1) signature alongside v2/v3. Modern Android only needs
        // v2, but v1 is what many sideload/inspection tools verify; AGP omits it
        // by default when minSdk >= 24, which made third-party tools report the
        // APK as unsigned even though Android accepted it.
        getByName("debug") {
            enableV1Signing = true
            enableV2Signing = true
            enableV3Signing = true
        }
        if (hasReleaseSigning) {
            create("release") {
                if (hasFileSigning) {
                    storeFile = file(keystoreProperties.getProperty("storeFile"))
                    storePassword = keystoreProperties.getProperty("storePassword")
                    keyAlias = keystoreProperties.getProperty("keyAlias")
                    keyPassword = keystoreProperties.getProperty("keyPassword")
                } else {
                    storeFile = file(envStorePath!!)
                    storePassword = envStorePassword
                    keyAlias = envKeyAlias
                    keyPassword = envKeyPassword
                }
                enableV1Signing = true
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseSigning) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")
}
