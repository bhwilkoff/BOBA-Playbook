// Top-level build file
//
// Plugins are declared with `apply false` so they're available to subprojects
// without applying at the root. Each module applies the ones it needs.
//
// AGP 9 includes built-in Kotlin support — the `org.jetbrains.kotlin.android`
// plugin is no longer required for Android modules and is intentionally
// absent from this list.

plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.jvm) apply false
    alias(libs.plugins.kotlin.compose) apply false
    alias(libs.plugins.kotlin.serialization) apply false
    alias(libs.plugins.ksp) apply false
    alias(libs.plugins.hilt) apply false
    alias(libs.plugins.google.services) apply false
    alias(libs.plugins.roborazzi) apply false
}
