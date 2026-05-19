pluginManagement {
    repositories {
        google {
            content {
                includeGroupByRegex("com\\.android.*")
                includeGroupByRegex("com\\.google.*")
                includeGroupByRegex("androidx.*")
            }
        }
        mavenCentral()
        gradlePluginPortal()
    }
}

@Suppress("UnstableApiUsage")
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "BOBAPlaybook"

include(":app")
include(":core:ui")
include(":core:domain")
include(":core:network")
include(":core:data")
// M8 adds :baselineprofile (com.android.test module with Macrobenchmark).
// For now its directory exists as a placeholder but is NOT included in
// the build — keeps M0 Gradle sync lean. Uncomment when M8 lands:
// include(":baselineprofile")
