plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(project(":catalog"))
    implementation(libs.kotlin.serialization.json)
    implementation(libs.kotlin.coroutines.core)
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.coroutines.test)
    testImplementation(kotlin("test"))
    testRuntimeOnly(libs.junit.platform.launcher)
}

kotlin { jvmToolchain(21) }
tasks.test { useJUnitPlatform() }
