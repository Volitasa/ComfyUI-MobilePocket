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
// file_picker 8.3.7 hardcodes compileSdk 34, but flutter_plugin_android_lifecycle 2.0.35
// requires dependents to compile against SDK 36. Override it here until file_picker is upgraded.
// NOTE: must be registered BEFORE the evaluationDependsOn block below, which forces
// early evaluation of subprojects.
subprojects {
    afterEvaluate {
        if (name == "file_picker") {
            extensions.configure<com.android.build.api.dsl.LibraryExtension>("android") {
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
