plugins {
    alias(libs.plugins.kotlin.jvm)
    alias(libs.plugins.kotlin.serialization)
}

dependencies {
    api(libs.kotlin.coroutines.core)
    implementation(libs.kotlin.serialization.json)
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.kotlin.coroutines.test)
    testImplementation(libs.bouncycastle)
    testRuntimeOnly(libs.junit.platform.launcher)
}

kotlin { jvmToolchain(21) }

tasks.test {
    useJUnitPlatform()
    inputs.dir(
        rootProject.layout.projectDirectory.dir("../Apple/Packages/gryonixNexus/Tests/TVLinkTests/Resources"),
    )
        .withPropertyName("swiftTvLinkGolden")
        .withPathSensitivity(PathSensitivity.RELATIVE)
}
