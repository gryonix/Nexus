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

## Terminal routes

A terminal tries every way to its machine, in order, and starts with the one
that worked last (`app/terminal/TerminalRoutes.kt`):

- the entry server: its address (through its jump host, if one is set), then
  its fallback address;
- a machine behind another: through that machine, then straight to its tunnel
  address, which answers when this phone's VPN is up.

A wrong host key or login stops at the first route; only a route that did not
answer lets the next one try. The badge in the corner names the route in use.
When a live shell drops, the app reconnects by itself (after 1, 3, 8 and
15 seconds). When no route answered and the tunnel would help, the screen
offers to turn on the last VPN and dial again. sshj sends a keepalive every 10
seconds, inside the 30-second idle limit of the Xray tunnel, so idle shells
stay open.

## Server groups

Long-press a group to move it left or right, or export it with its servers as
one sealed `.gryonixserver` file; long-press All to export every group or
import a file. The file is the one the Apple app writes (`kind`
`gryonixgroups`), and importing it keeps the group order. Each server in it
carries only the groups the file holds.
