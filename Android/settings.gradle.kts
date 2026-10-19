// The module split mirrors the Swift package targets one-to-one, so a port is
// always "this file to that module" and never a judgement call. The pure-logic
// modules are Kotlin/JVM, not Android libraries: their tests then run on the
// JVM in seconds, without an emulator, exactly as `swift test` does today.
pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("org.gradle.toolchains.foojay-resolver-convention") version "1.0.0"
}

dependencyResolutionManagement {
    repositories {
        google()
        mavenCentral()
    }
}

rootProject.name = "gryonixNexus"

include(":core")           // gryonixNexusCore: domain, addresses, DNS, distributions
include(":catalog")        // ServiceCatalog: ManagedService and the shelves
include(":recipe")         // MailRecipe: artifact generation
include(":vpnprofile")     // VPNProfile: what is inside a share link, and the
include(":servercontrol")  // ServerControl: commands, parsers, fleet models
include(":agentclient")    // AgentClient: proto types + Connect framing
include(":agentcontrol")   // AgentControl: the agent-backed half of ServiceControlling
include(":transport")      // sshj transport — the Android replacement for Citadel
include(":app")            // Compose UI
