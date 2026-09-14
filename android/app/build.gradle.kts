plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase Cloud Messaging (Tanda 1b). Va DESPUES del plugin de Flutter: necesita que el
    // modulo de Android ya este configurado para inyectarle los recursos de google-services.json.
    id("com.google.gms.google-services")
}

android {
    // Cambiado el 2026-09-14, antes de crear el proyecto de Firebase: el applicationId es la
    // identidad definitiva de la app y NO se puede cambiar una vez publicada sin perderla -- los
    // usuarios ya instalados se quedan en la vieja. Y el prefijo de ejemplo que traia Flutter
    // ademas esta prohibido en Google Play.
    //
    // namespace es el paquete del codigo generado (build-time) y applicationId es la identidad
    // publicada: son cosas distintas y podrian diferir, pero mantenerlos iguales evita tener que
    // explicar cual es cual cada vez.
    namespace = "com.computopro.app"
    // Fijo en 36, no flutter.compileSdkVersion (que hoy resuelve a 34 con el Flutter SDK
    // instalado) -- file_picker (vía flutter_plugin_android_lifecycle) exige compilar contra 36.
    // Solo compileSdk: compilación únicamente, sin efecto en runtime ni en qué dispositivos
    // instalan la app -- minSdk/targetSdk siguen atados a flutter.minSdkVersion/targetSdkVersion,
    // sin tocar.
    compileSdk = 36
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.computopro.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // `record` (nota de voz del libro, tanda 3) pide API 23 como piso. `maxOf` y no un 23
        // fijo: si el Flutter SDK sube su minimo, este numero no lo tiene que frenar.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
