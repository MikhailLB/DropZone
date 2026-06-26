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

    // ---------------------------------------------------------------------
    // Some plugin Android modules still ship with `compileSdk = 34`, while
    // their transitive dependencies (e.g. flutter_plugin_android_lifecycle)
    // already require 36. `CheckAarMetadata` aborts the build with a
    // misleading "applications that depend on it" error.
    //
    // Force every Android library subproject to compile against the same
    // SDK level the app uses (36+). The override must be registered BEFORE
    // the `evaluationDependsOn(":app")` block below — otherwise the target
    // projects are already evaluated and Gradle refuses to attach a new
    // afterEvaluate callback ("Project.afterEvaluate cannot run when the
    // project is already evaluated").
    // ---------------------------------------------------------------------
    afterEvaluate {
        extensions
            .findByType(com.android.build.gradle.LibraryExtension::class.java)
            ?.apply {
                if ((compileSdk ?: 0) < 36) {
                    compileSdk = 36
                }
            }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
