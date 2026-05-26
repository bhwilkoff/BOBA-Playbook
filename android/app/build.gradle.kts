import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import java.util.Properties

// ---------------------------------------------------------------------
// Read secrets / config out of (in order): the matching env var (CI),
// then android/local.properties (local dev). Empty string fallback —
// the affected surface degrades but the rest of the app still builds.
// ---------------------------------------------------------------------
fun loadLocalProp(name: String): String {
    val env = System.getenv(name)
    if (!env.isNullOrBlank()) return env
    val f = rootProject.file("local.properties")
    if (!f.exists()) return ""
    return Properties().apply { load(f.inputStream()) }.getProperty(name, "")
}

val mapsApiKey: String = loadLocalProp("MAPS_API_KEY")

// Release-signing creds — set via env vars in CI, or via local.properties
// for local release smoke-tests. Missing values trigger an unsigned
// release build (still useful for R8 / minify validation) — Play
// Console upload requires a signed AAB.
val uploadKeystorePath:     String = loadLocalProp("UPLOAD_KEYSTORE_PATH")
val uploadKeystorePassword: String = loadLocalProp("UPLOAD_KEYSTORE_PASSWORD")
val uploadKeyAlias:         String = loadLocalProp("UPLOAD_KEY_ALIAS").ifBlank { "boba-upload" }
val uploadKeyPassword:      String = loadLocalProp("UPLOAD_KEY_PASSWORD")

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
        // 2026-05-25: bumped to 2 / 0.1.1 for first Play Console closed-testing
        // upload after the bobaId v3 migration + Collection-empty bug fixes.
        versionCode = 4
        versionName = "0.1.3"

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

        // Thread the Maps API key into the manifest as a placeholder.
        // The <meta-data android:name="com.google.android.geo.API_KEY">
        // element in AndroidManifest.xml references ${MAPS_API_KEY}.
        manifestPlaceholders["MAPS_API_KEY"] = mapsApiKey
    }

    // Release signing — wired when UPLOAD_KEYSTORE_PATH +
    // UPLOAD_KEYSTORE_PASSWORD + UPLOAD_KEY_PASSWORD are present (in
    // env vars on CI, or in local.properties for local builds). When
    // any field is blank we skip configuring the signing config; the
    // release build will produce an unsigned AAB, which the Play
    // upload step then rejects — but `assembleRelease` still runs for
    // R8 / minify validation.
    signingConfigs {
        if (uploadKeystorePath.isNotBlank() &&
            uploadKeystorePassword.isNotBlank() &&
            uploadKeyPassword.isNotBlank()
        ) {
            create("release") {
                storeFile     = file(uploadKeystorePath)
                storePassword = uploadKeystorePassword
                keyAlias      = uploadKeyAlias
                keyPassword   = uploadKeyPassword
            }
        }
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
            // Bind the release signing config when it exists. Resolves
            // by-name so a missing config (creds not set) silently
            // leaves the release build unsigned.
            signingConfigs.findByName("release")?.let { signingConfig = it }
            // ML Kit ships via Google Play Services dynamic delivery
            // (DECISIONS.md #043 amended 2026-05-26), so the AAB no
            // longer carries libmlkit_google_ocr_pipeline.so. A few
            // tiny stripped .so files still ship via AndroidX (graphics
            // path), CameraX (image_processing_util_jni), and DataStore
            // (shared_counter). FULL asks AGP to extract whatever it
            // can — at minimum build IDs — so Play Console gets a
            // non-empty symbols upload and stops warning.
            ndk.debugSymbolLevel = "FULL"
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

// ----------------------------------------------------------------------
// native-debug-symbols.zip for Play Console
// ----------------------------------------------------------------------
// Play Console fires "App Bundle contains native code, and you've not
// uploaded debug symbols" whenever the AAB contains any `.so` files
// without a paired symbols upload. The AAB contains ~191 KB of
// stripped `.so` files Google ships pre-stripped via AndroidX +
// CameraX + DataStore (verified via `readelf -S`), so AGP's
// `extractReleaseNativeDebugMetadata` task reports NO-SOURCE and no
// symbols zip is produced.
//
// The fix (confirmed working at Play Console as of 2026-05): zip the
// stripped `.so` files themselves with ABI folders at the top level
// and upload via `edits.deobfuscationfiles.upload` with
// `deobfuscationFileType=nativeCode`. Play Console validates BuildID
// matches the AAB, accepts the upload, and dismisses the warning.
// Crash reports get correct library attribution (which .so a native
// frame belongs to) — line numbers stay unsymbolicated, which is
// unavoidable for Google-shipped stripped binaries.
//
// Run via `:app:bundleRelease` — wired as `finalizedBy` below so the
// zip is always produced alongside every release AAB. Output lives at
// `app/build/outputs/native-debug-symbols/release/native-debug-symbols.zip`
// which is the path the GitHub Actions workflow already expects.
val packageReleaseNativeDebugSymbols = tasks.register<Zip>("packageReleaseNativeDebugSymbols") {
    description = "Zip stripped native libs for Play Console upload (workaround for AndroidX libs Google ships pre-stripped)."
    group = "build"
    val mergedLibsRoot = layout.buildDirectory.dir(
        "intermediates/merged_native_libs/release/mergeReleaseNativeLibs/out/lib"
    )
    from(mergedLibsRoot)
    include("**/*.so")
    archiveFileName.set("native-debug-symbols.zip")
    destinationDirectory.set(layout.buildDirectory.dir("outputs/native-debug-symbols/release"))
    dependsOn("mergeReleaseNativeLibs")
}

tasks.matching { it.name == "bundleRelease" }.configureEach {
    finalizedBy(packageReleaseNativeDebugSymbols)
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
    implementation(libs.androidx.browser)         // Chrome Custom Tabs for Discord OAuth + ToS / Privacy links
    implementation(libs.play.services.maps)       // Google Maps SDK — Find a Store map (Purchase tab)
    implementation(libs.maps.compose)             // GoogleMap composable + Marker + CameraPositionState
    implementation(libs.datastore.preferences)    // grid-density + first-run hint dismissal
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

    // Navigation Compose 2.x — workhorse for compact-width single-stack
    // pushes (Find → CardDetail, Decks → Manage/Rules, Learn category →
    // article). Nav3 wired for future when its API stabilizes.
    implementation(libs.nav.compose)
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
