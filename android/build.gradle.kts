allprojects {
    repositories {
        google()
        mavenCentral()
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

// flutter_timezone компилирует Java под 11, а Kotlin под 1.8 → Gradle падает с
// «Inconsistent JVM-target compatibility». Выравниваем его Kotlin на 11 (под его
// же Java). Остальные модули не трогаем — они и так согласованы.
subprojects {
    if (name == "flutter_timezone") {
        tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
            .configureEach {
                compilerOptions {
                    jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
                }
            }
    }
}

// file_picker тянет flutter_plugin_android_lifecycle, который требует compileSdk
// 36+. Плагин-модули по умолчанию берут flutter.compileSdkVersion (<36) → AAR
// metadata check падает. Поднимаем compileSdk до 36 во всех плагин-модулях.
// afterEvaluate — чтобы перебить compileSdk, выставленный build.gradle плагина.
// Исключаем :app: он уже вычислен (evaluationDependsOn выше) → afterEvaluate на
// нём бросит; его compileSdk и так 36 в app/build.gradle.kts.
subprojects {
    if (name != "app") {
        afterEvaluate {
            val ext = extensions.findByName("android")
            if (ext is com.android.build.gradle.LibraryExtension) {
                ext.compileSdk = 36
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
