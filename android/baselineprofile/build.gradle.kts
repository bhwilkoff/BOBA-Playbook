// :baselineprofile — empty placeholder for M0.
//
// In M8 this becomes a `com.android.test` module with a Macrobenchmark
// test that exercises the critical user journey (launch → Find →
// search → tap card → scroll grid → switch tab) and emits
// baseline-prof.txt. ART pre-compiles those code paths at install time
// for a 20-40% cold-start improvement (ANDROID-DEV.md §11.2).
//
// For now this is intentionally empty so settings.gradle.kts can
// include(":baselineprofile") without breaking the sync.

plugins {
    alias(libs.plugins.kotlin.jvm)
}

// No dependencies until the test module ships in M8.
