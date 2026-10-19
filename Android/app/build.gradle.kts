import java.util.Properties
import javax.inject.Inject
import org.gradle.process.ExecOperations

plugins {
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "com.skaymer.gryonixnexus"
    compileSdk = 37

    defaultConfig {
        applicationId = "com.skaymer.gryonixnexus"
        minSdk = 26
        targetSdk = 37
        versionCode = 261011
        versionName = "26.10"
    }

    val keystoreProperties = rootProject.file("keystore.properties").takeIf { it.exists() }
        ?.let { file -> Properties().apply { file.inputStream().use { stream -> load(stream) } } }
    val keystorePath = keystoreProperties?.getProperty("storeFile")
        ?: System.getenv("GRYONIX_KEYSTORE_FILE")

    signingConfigs {
        if (keystorePath != null) {
            create("release") {
                storeFile = rootProject.file(keystorePath)
                storePassword = keystoreProperties?.getProperty("storePassword")
                    ?: System.getenv("GRYONIX_KEYSTORE_PASSWORD")
                keyAlias = keystoreProperties?.getProperty("keyAlias")
                    ?: System.getenv("GRYONIX_KEY_ALIAS")
                keyPassword = keystoreProperties?.getProperty("keyPassword")
                    ?: System.getenv("GRYONIX_KEY_PASSWORD")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
            isMinifyEnabled = false
        }
    }

    sourceSets["main"].jniLibs.srcDir("${rootDir}/runtimes/jniLibs")

    // GPL-2.0 wg tools, needed only by the unused root backend
    packaging { jniLibs { excludes += listOf("**/libwg.so", "**/libwg-quick.so") } }

    buildFeatures { compose = true }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }
}

dependencies {
    implementation(project(":core"))
    implementation(project(":catalog"))
    implementation(project(":vpnprofile"))
    implementation(project(":servercontrol"))
    implementation(project(":recipe"))
    implementation(project(":transport"))
    implementation(project(":agentcontrol"))
    implementation(libs.bouncycastle)
    implementation(libs.kotlin.serialization.json)
    implementation(files("${rootDir}/runtimes/awg-tunnel.aar"))
    implementation(files("${rootDir}/runtimes/libxray.aar"))
    implementation(libs.androidx.annotation)
    implementation(libs.androidx.collection)
    implementation(platform(libs.compose.bom))
    implementation(libs.compose.ui)
    implementation(libs.compose.ui.tooling.preview)
    implementation(libs.compose.material3)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.compose.material.icons)
    implementation(libs.kotlin.coroutines.android)
    implementation(libs.kotlin.coroutines.play.services)
    implementation(platform(libs.firebase.bom))
    implementation(libs.firebase.messaging)
    debugImplementation(libs.compose.ui.tooling)

    testImplementation(libs.junit.jupiter)
    testImplementation(kotlin("test"))
    testImplementation(libs.kotlin.coroutines.test)
    testRuntimeOnly(libs.junit.platform.launcher)
}

tasks.withType<Test>().configureEach {
    useJUnitPlatform()

    inputs.file(layout.projectDirectory.file("src/main/res/drawable/tab_icon_logo.xml"))
        .withPropertyName("brandMarkAndroid")
        .withPathSensitivity(PathSensitivity.NONE)
    inputs.file(
        rootProject.layout.projectDirectory.file(
            "../Apple/Shared/BrandMarks.xcassets/TabIconLogo.imageset/TabIconLogo.svg",
        ),
    )
        .withPropertyName("brandMarkApple")
        .withPathSensitivity(PathSensitivity.NONE)

    inputs.file(layout.projectDirectory.file("src/main/res/drawable/tab_icon_globe.xml"))
        .withPropertyName("brandGlobeAndroid")
        .withPathSensitivity(PathSensitivity.NONE)
    inputs.file(
        rootProject.layout.projectDirectory.file(
            "../Apple/Shared/BrandMarks.xcassets/TabIconGlobe.imageset/TabIconGlobe.svg",
        ),
    )
        .withPropertyName("brandGlobeApple")
        .withPathSensitivity(PathSensitivity.NONE)

    inputs.dir(layout.projectDirectory.dir("src/main/res"))
        .withPropertyName("launcherIconResources")
        .withPathSensitivity(PathSensitivity.RELATIVE)
    inputs.file(layout.projectDirectory.file("src/main/AndroidManifest.xml"))
        .withPropertyName("launcherIconManifest")
        .withPathSensitivity(PathSensitivity.NONE)
}

abstract class PackAgentSources : DefaultTask() {
    @get:InputFile
    abstract val script: RegularFileProperty

    @get:InputFiles
    abstract val serverTree: ConfigurableFileCollection

    @get:InputDirectory
    abstract val protoTree: DirectoryProperty

    @get:OutputDirectory
    abstract val outputDirectory: DirectoryProperty

    @get:Inject
    abstract val exec: ExecOperations

    @TaskAction
    fun pack() {
        val archive = outputDirectory.get().asFile.resolve("agent-src.bin")
        archive.parentFile.mkdirs()
        exec.exec {
            commandLine("bash", script.get().asFile.absolutePath, archive.absolutePath)
        }
    }
}

val packAgentSources = tasks.register<PackAgentSources>("packAgentSources") {
    script.set(rootProject.layout.projectDirectory.file("../Tools/pack-agent-sources.sh"))
    serverTree.from(rootProject.fileTree("../Server") { exclude("**/target/**") })
    protoTree.set(rootProject.layout.projectDirectory.dir("../Proto"))
}

androidComponents {
    onVariants { variant ->
        variant.sources.assets?.addGeneratedSourceDirectory(packAgentSources, PackAgentSources::outputDirectory)
    }
}
