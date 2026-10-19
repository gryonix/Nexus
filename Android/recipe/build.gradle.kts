plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":core"))
    implementation(libs.kotlin.serialization.json)
    implementation(libs.bouncycastle)
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.serialization.json)
    testRuntimeOnly(libs.junit.platform.launcher)
}

kotlin { jvmToolchain(21) }
tasks.test { useJUnitPlatform() }
