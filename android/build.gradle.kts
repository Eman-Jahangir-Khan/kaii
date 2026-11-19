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

// Agora jaise purane plugins ko naye compileSdk par compile karo
// (ye block evaluationDependsOn se PEHLE hona zaroori hai)
subprojects {
    afterEvaluate {
        if (plugins.hasPlugin("com.android.library") ||
            plugins.hasPlugin("com.android.application")
        ) {
            extensions.configure<com.android.build.gradle.BaseExtension> {
                compileSdkVersion(37)
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