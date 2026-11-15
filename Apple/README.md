# Apple

The gryonixNexus app for iPhone, iPad and Mac: one project, one set of sources.

- `App/`: the screens and the app's services.
- `Packages/gryonixNexus/`: Swift packages with the logic: models, the service
  catalog, the generated setup scripts, SSH and the agent client.
- `TunnelExtension/`: the VPN tunnel that runs on the device.
- `Widgets/`: widgets, the Control Centre toggle and Live Activities.
- `Shared/`: assets used by the app and its extensions.
- `Screenshots/`: the pictures shown in the main README.
- `AppTests/`, `TunnelExtensionTests/`: unit tests.
- `project.yml`: the project definition for all targets.

## SSH library

Citadel's swift-nio-ssh fork is required at 0.3.7 or later in
`Packages/gryonixNexus/Package.swift`. Older releases send a channel window
adjust after CLOSE, and a terminal closed mid-output then traps in
`sendChannelWindowAdjust`. `Tools/verify.sh` checks the requirement.
