plugins { alias(libs.plugins.kotlin.jvm) }

dependencies {
    api(project(":agentclient"))
    api(project(":servercontrol"))
    api(libs.sshj)
    implementation(libs.bouncycastle)
    implementation(libs.kotlin.coroutines.core)
    testImplementation(libs.junit.jupiter)
    testImplementation(libs.mina.sshd.core)
    testImplementation(libs.mina.sshd.common)
    testImplementation(libs.eddsa)
    testImplementation(libs.kotlin.coroutines.test)
    testImplementation(kotlin("test"))
    testRuntimeOnly(libs.junit.platform.launcher)
}
kotlin { jvmToolchain(21) }
tasks.test { useJUnitPlatform() }
