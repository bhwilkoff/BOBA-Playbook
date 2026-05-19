import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    alias(libs.plugins.android.application)
    // AGP 9 auto-applies Kotlin support — no `kotlin.android` plugin needed.
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
    alias(libs.plugins.ksp)
    alias(libs.plugins.hilt)
    alias(libs.plugins.google.services)
}

android {
    namespace = "com.bobaplaybook.app"
    compileSdk = libs.versions.compile.sdk.get().toInt()

    defaultConfig {
        applicationId = "com.bobaplaybook.app"
        minSdk = libs.versions.min.sdk.get().toInt()
        targetSdk = libs.versions.target.sdk.get().toInt()
        // versionCode + versionName auto-managed by CI / Play Console release flow
        // (See ANDROID-DEV.md §13.2). Bumped locally only for sideload smoke-tests.
        versionCode = 1
        versionName = "0.1.0"

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables { useSupportLibrary = true }

        // BuildConfig fields — public identifiers safe to embed in the
        // APK. Real secrets (Supabase service-role key, Play Service
        // Account JSON) NEVER appear here — those are Worker/CI-only.
        //
        // GOOGLE_WEB_CLIENT_ID: the Web Application OAuth client ID
        // consumed by Credential Manager's GetGoogleIdOption for Sign
        // in with Google. NOT a secret — Google docs explicitly state
        // OAuth client IDs are public. The matching Android-type
        // OAuth client (350111546071-a5lcvfqmavueq07uiiomm4dg3gs9g82c)
        // is auto-consumed by Google services via package + SHA-1
        // match; no code reference needed.
        buildConfigField(
            "String",
            "GOOGLE_WEB_CLIENT_ID",
            "\"350111546071-8nr3kumje5uor60t3vufl6a005a8os93.apps.googleusercontent.com\""
        )
    }

    buildTypes {
        debug {
            // Don't suffix applicationId in debug — keeps the same
            // package name as release so google-services.json's single
            // Firebase Android app registration matches both build
            // types. Trade-off: can't install debug + release side-by-
            // side on the same device. Worth it for the simpler config.
            versionNameSuffix = "-debug"
            isMinifyEnabled = false
        }
        release {
            // R8 is mandatory for release per ANDROID-DEV.md §11.1.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            // Signing config bound at CI time via Play App Signing.
            // For local release builds, configure via ~/.gradle/gradle.properties
            // (see android/SETUP.md).
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlin {
        compilerOptions {
            jvmTarget.set(JvmTarget.JVM_17)
        }
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }

    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

// ----------------------------------------------------------------------
// Shared-asset sync — runs before `preBuild` so card catalog + fonts
// are always fresh from the monorepo root before the APK is packaged.
// Same shape as the iOS pipeline/recognition/sync_mirror.sh approach.
// ----------------------------------------------------------------------

val syncSharedAssets = tasks.register<Exec>("syncSharedAssets") {
    description = "Copy cards.json + categories.json + fonts from monorepo root into Android assets/res."
    group = "build"
    workingDir = rootDir
    commandLine("bash", "scripts/sync_shared_assets.sh")
}

tasks.named("preBuild").configure {
    dependsOn(syncSharedAssets)
}


dependencies {
    implementation(project(":core:ui"))
    implementation(project(":core:domain"))
    implementation(project(":core:network"))
    implementation(project(":core:data"))

    // Compose BOM — pins every Compose lib to a tested matrix.
    implementation(platform(libs.compose.bom))
    androidTestImplementation(platform(libs.compose.bom))

    // Core Android + Compose
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.core.splashscreen)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.window)
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.foundation)
    implementation(libs.compose.material3)
    implementation(libs.compose.material3.adaptive)
    implementation(libs.compose.material3.adaptive.layout)
    implementation(libs.compose.material3.adaptive.navigation)
    implementation(libs.compose.material3.adaptive.nav.suite)
    implementation(libs.compose.material.icons.extended)
    implementation(libs.compose.animation)
    debugImplementation(libs.compose.ui.tooling)
    debugImplementation(libs.compose.ui.test.manifest)

    // Navigation 3 — modern Compose-first navigation (replaces Nav2)
    implementation(libs.nav3.runtime)
    implementation(libs.nav3.ui)

    // DI
    implementation(libs.hilt.android)
    ksp(libs.hilt.compiler)
    implementation(libs.hilt.nav.compose)

    // Image loading
    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)

    // Camera + ML Kit (M3 scan pipeline)
    implementation(libs.camerax.core)
    implementation(libs.camerax.camera2)
    implementation(libs.camerax.lifecycle)
    implementation(libs.camerax.view)
    implementation(libs.camerax.mlkit)
    implementation(libs.mlkit.text.recognition)

    // Auth — Credential Manager (M7 Sign in with Google)
    implementation(libs.credentials)
    implementation(libs.credentials.play.services.auth)
    implementation(libs.googleid)

    // Supabase — wired in M7 for auth + writes
    implementation(platform(libs.supabase.bom))
    implementation(libs.supabase.auth)
    implementation(libs.supabase.postgrest)

    // Networking
    implementation(libs.ktor.client.core)
    implementation(libs.ktor.client.okhttp)
    implementation(libs.ktor.client.content.negotiation)
    implementation(libs.ktor.serialization.json)
    implementation(libs.ktor.client.logging)
    implementation(libs.okhttp)                        // explicit so BOBAApplication's OkHttpClient compiles cleanly
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.collections.immutable)
    implementation(libs.coroutines.android)

    // Firebase (FCM only — DECISIONS.md #052)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)

    // Tests
    testImplementation(libs.junit)
    testImplementation(libs.turbine)
    testImplementation(libs.mockk)
    testImplementation(libs.coroutines.test)
    androidTestImplementation(libs.androidx.test.ext.junit)
    androidTestImplementation(libs.androidx.test.espresso.core)
    androidTestImplementation(libs.compose.ui.test.junit4)
}
