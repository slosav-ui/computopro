allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

// Fija compileSdk = 36 en TODOS los subproyectos (los plugins de Flutter incluidos, ej.
// file_picker, flutter_plugin_android_lifecycle), no solo en :app -- cada plugin trae su propio
// build.gradle y su propio compileSdk (por default, flutter.compileSdkVersion, que hoy resuelve a
// 34), así que fijarlo solo en android/app/build.gradle.kts no alcanza: el error real
// ("file_picker is currently compiled against android-34") viene del build del subproyecto
// :file_picker en sí, no del de :app.
//
// afterEvaluate porque el override tiene que aplicarse DESPUÉS de que el build.gradle propio de
// cada plugin ya corrió (y fijó su propio compileSdk) -- así el valor de acá gana como última
// escritura, en vez de perder contra lo que el plugin ya configuró.
//
// ESTE bloque tiene que ir ANTES que el `project.evaluationDependsOn(":app")` de más abajo -- ese
// fuerza a Gradle a evaluar :app de inmediato, ahí mismo, en cuanto lo procesa el primer
// subproyecto de la iteración. Si el registro de afterEvaluate llegara después (como en el primer
// intento), :app ya habría terminado de evaluarse para cuando este bloque lo alcanza, y
// project.afterEvaluate() sobre un proyecto ya evaluado tira
// "Cannot run Project.afterEvaluate(Action) when the project is already evaluated" -- exactamente
// el error que apareció. Registrando acá arriba, antes de que nada fuerce una evaluación
// temprana, el callback ya está enganchado en :app para cuando evaluationDependsOn lo dispara.
//
// withGroovyBuilder en vez de importar com.android.build.gradle.BaseExtension: el classpath de
// AGP no está garantizado en el script del proyecto raíz (acá :app es el único que aplica
// com.android.application de verdad, vía "apply false" a nivel de settings.gradle.kts) -- esto
// evita depender de ese import y funciona igual llamando al método compileSdkVersion(Int) de la
// extensión "android" de forma dinámica, sin importar de qué subtipo (AppExtension/
// LibraryExtension) se trate.
//
// Alternativa descartada: android.suppressUnsupportedCompileSdk (gradle.properties) resuelve un
// problema distinto -- silencia el aviso de "este AGP no probó este compileSdk todavía", no el
// fallo real acá, que es que el compileSdk de :file_picker es MENOR al mínimo que exige una AAR
// de la que depende (checkDebugAarMetadata). Esa propiedad no habría arreglado nada.
subprojects {
    afterEvaluate {
        if (project.plugins.hasPlugin("com.android.application") || project.plugins.hasPlugin("com.android.library")) {
            project.extensions.findByName("android")?.withGroovyBuilder {
                // Llama al método compileSdkVersion(Int) de la extensión "android" (la sobrecarga
                // que atiende la sintaxis Groovy `compileSdkVersion 36`) -- NO el setter de la
                // propiedad (compileSdkVersion(String), ej. "android-36"), que rechazaría un Int.
                "compileSdkVersion"(36)
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
