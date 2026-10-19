plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.wire)
}

wire {
    sourcePath { srcDir("${rootDir.parentFile}/Proto") }
    kotlin { rpcRole = "none" }
}

dependencies {
    implementation(libs.wire.runtime)
    implementation(libs.kotlin.coroutines.core)
    implementation(libs.kotlin.serialization.json)
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.coroutines.test)
    testImplementation(kotlin("test"))
    testRuntimeOnly(libs.junit.platform.launcher)
}
kotlin { jvmToolchain(21) }
tasks.test { useJUnitPlatform() }
