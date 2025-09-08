import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// conditionally apply google-services (keeps your original intent)
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

// Load local.properties (flutter.*) safely
val localProperties = Properties().apply {
    val localPropertiesFile = rootProject.file("local.properties")
    if (localPropertiesFile.exists()) {
        localPropertiesFile.reader(Charsets.UTF_8).use { reader -> load(reader) }
    }
}

// Read flutter version info from local.properties (fallbacks)
var flutterVersionCode: Int = localProperties.getProperty("flutter.versionCode")?.toIntOrNull() ?: 1
var flutterVersionName: String = localProperties.getProperty("flutter.versionName") ?: "1.0"
val flutterTargetSdk: Int = localProperties.getProperty("flutter.targetSdkVersion")?.toIntOrNull() ?: 33

// Load key.properties if present
val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        FileInputStream(keystorePropertiesFile).use { fis -> load(fis) }
    }
}
val keystorePropertiesFile = rootProject.file("key.properties")

android {
    compileSdk = 35
    namespace = "com.talktolearn.chat"

    sourceSets {
        getByName("main").java.srcDirs("src/main/kotlin")
    }

    // Lint: disable an id if you really need it (same effect as lintOptions.disable "InvalidPackage")
    lint {
        disable += "InvalidPackage"
    }

    defaultConfig {
        applicationId = "com.talktolearn.chat"
        minSdk = 21
        targetSdk = flutterTargetSdk
        versionCode = flutterVersionCode
        versionName = flutterVersionName
        multiDexEnabled = true

        // Disable others for now, so it takes less space
        ndk {
            abiFilters += listOf("armeabi-v7a", "arm64-v8a")
        }
    }

    // Signing configs (create release if keystore present)
    signingConfigs {
        // keep the default debug config provided by AGP
        create("release") {
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
            versionNameSuffix = "-debug"
        }
        getByName("release") {
            isMinifyEnabled = false
            isShrinkResources = false
            // use the release signing config we created above (will be used only if key properties exist)
            signingConfig = signingConfigs.getByName("release")
        }
    }

    // Packaging / native libs
    packagingOptions {
        jniLibs {
            pickFirsts += listOf(
                //"lib/x86/libc++_shared.so",
                //"lib/x86_64/libc++_shared.so",
                "lib/armeabi-v7a/libc++_shared.so",
                "lib/arm64-v8a/libc++_shared.so"
            )
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    // Kotlin JVM target
    kotlinOptions {
        jvmTarget = "17"
    }
}

// Flutter extension (Kotlin DSL: assign property if available)
extensions.findByName("flutter")?.let { ext ->
    try {
        // typical flutter DSL has a 'source' property; set it if available
        ext.javaClass.getMethod("setSource", String::class.java).invoke(ext, "../..")
    } catch (_: Exception) {
        // ignore if not available in this plugin version
    }
}

dependencies {
    implementation(platform("com.google.firebase:firebase-bom:32.8.0"))
    implementation("com.google.firebase:firebase-analytics")
    implementation("com.google.firebase:firebase-database")

    implementation("androidx.multidex:multidex:2.0.1")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}

// (optional) previously commented exclusions:
// configurations.all {
//     exclude(group = "com.google.android.gms")
// }
