# Android

The gryonixNexus Android app, in Kotlin and Jetpack Compose. Not released yet.

Each Gradle module mirrors a target of the Apple app's Swift packages, so the
shared logic exists once per platform:

- `core`, `catalog`, `recipe`: models, the service catalog and the generated
  setup scripts.
- `servercontrol`, `transport`: managing a server over SSH.
- `agentclient`, `agentcontrol`: talking to the server agent.
- `vpnprofile`: VPN profiles; `xraybridge`: the Go bridge to Xray.
- `app`: the screens.
