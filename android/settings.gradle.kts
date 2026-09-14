pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.0.1" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
    // Lee android/app/google-services.json y genera los recursos con las claves del proyecto de
    // Firebase (0142 / Tanda 1b). `apply false` aca: se declara la version en el proyecto raiz y se
    // aplica en el modulo :app, que es donde vive el json.
    id("com.google.gms.google-services") version "4.4.2" apply false
}

include(":app")
