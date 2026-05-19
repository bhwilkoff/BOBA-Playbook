import org.jetbrains.kotlin.gradle.dsl.JvmTarget

// :core:domain is pure Kotlin — NO Android imports anywhere in this
// module. This is the seed for a future KMP `:shared` module if Web ever
// wants typed BOBA data models. Keep it dependency-light.

plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

java {
    sourceCompatibility = JavaVersion.VERSION_17
    targetCompatibility = JavaVersion.VERSION_17
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

dependencies {
    implementation(libs.kotlinx.serialization.json)
    implementation(libs.kotlinx.collections.immutable)

    testImplementation(libs.junit)
}
