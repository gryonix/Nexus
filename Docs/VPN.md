# VPN

gryonixNexus installs a VPN server on your own machine and then manages it:
devices, their keys, where it runs and how fast it is. The same app is also the
VPN client on iPhone, iPad, Mac and Apple TV.

A VPN needs ports reachable from the internet, so it is available in the
scenarios **Public IP**, **Public IP (VPS) + Local server** and **Home server
with a changing address** (see
[SCENARIOS.md](SCENARIOS.md)).

## Protocols

You can install one protocol or several side by side. Every device gets its own
keys, so one device can be removed without touching the others.

| Protocol | Transport, default port | Looks like | Speed | Reaches your own sites | Use it when |
|---|---|---|---|---|---|
| **WireGuard** | UDP 51820 | WireGuard | Fastest | Yes | The network does not block VPNs. The default choice. |
| **AmneziaWG** | UDP 51822 | Random UDP noise | As fast as WireGuard when it runs in the kernel | Yes | WireGuard is blocked or throttled on the network. |
| **Shadowsocks** (2022, AES-256-GCM) | TCP and UDP 8388 | Unrecognisable encrypted stream | Fast | No, internet only | Simple obfuscation is enough. |
| **VLESS with Reality** (Xray) | TCP 8443 | An ordinary HTTPS connection to a real website | Fast | No, internet only | The network inspects traffic and blocks anything that is not HTTPS. |
| **OpenVPN** | UDP 1194 | OpenVPN | Slower | No, internet only | A device or router only speaks OpenVPN. |

"Reaches your own sites" means the device can open the services on your server
by their names through the tunnel, including admin pages that are limited to the
VPN. The other protocols carry internet traffic only.

All ports can be changed when the protocol is installed.

### Which one to pick

- Start with **WireGuard**.
- If WireGuard does not connect from some network (a hotel, a mobile carrier, a
  country that blocks VPNs), add **AmneziaWG** for the same devices.
- Where even AmneziaWG is blocked, **VLESS with Reality** is the hardest to tell
  apart from normal web traffic.
- **OpenVPN** is there for compatibility, not for speed.

### AmneziaWG in the kernel

AmneziaWG can run as a program or as a kernel module. As a program it is
limited by the server's processor. In the kernel it is as fast as WireGuard and
uses far less of the processor. The server's VPN speed page shows which one is
running and can switch to the kernel. Building the module needs about 300 to
400 MB of disk for the kernel headers and compiler; switching it off frees them.

## Where the VPN runs with a VPS and a local server

In the "Public IP (VPS) + Local server" scenario the VPN can run on the home
machine or on the VPS. **On the VPS it
is faster**: internet traffic leaves straight from the VPS, and only traffic to
your own sites goes home through the tunnel. At home, every byte crosses your
home connection twice, so your home upload speed caps the VPN.

The server's VPN section has **Move the VPN to the VPS** and **Move the VPN
home**. Keys, devices and their addresses move with the VPN, so devices keep
their configurations and reconnect on their own. The VPN pauses for a few
minutes while it moves.

## Devices

- **Add a device** in the server's VPN section. The app creates its keys and
  shows the configuration as a file, a link or a QR code for the official
  client apps (WireGuard, AmneziaVPN, Shadowsocks and Xray clients, OpenVPN).
- **This device**: the iPhone, iPad, Mac or Apple TV running the app can join
  the server's VPN itself, with no other app. On the Mac the VPN also lives in
  the menu bar.
- **Remove a device** and its keys stop working at once.
- **Imported configurations.** The app's VPN can also use a configuration from a
  VPN you did not set up with it: a WireGuard or AmneziaWG file, an Amnezia
  `vpn://` key, an `ss://` or a `vless://` link, pasted, opened as a file or
  scanned as a QR code on iPhone.

## The VPN panel

Next to the protocols the server runs a small web panel to hand out client
profiles. By default it answers only through the VPN. It has no access to the
host's Docker or kernel modules: it asks the agent for the few things it needs
(restarting a protocol, reading its state, OpenVPN client files), and the agent
refuses everything else. See [SECURITY.md](../SECURITY.md).

## Speed

The server's VPN section has a speed page. It shows how each protocol runs (in
the kernel or as a program) and the packets the server drops: run a speed test
on the device, then read the page again, and drops that grew during the test
are what cost speed. For the best speed:

1. With a VPS in front of a home machine, run the VPN on the VPS.
2. Prefer WireGuard, or AmneziaWG in the kernel.
3. Pick a VPS close to you, with enough bandwidth.

## Practical notes

- **Long quiet SSH sessions through Shadowsocks or VLESS.** These tunnels close
  a connection that has been silent for a while. Let your SSH client send
  keepalives, for example `ServerAliveInterval 15` in `~/.ssh/config`. The
  app's own terminal already does this.
- **The VPN and your own sites.** Only WireGuard and AmneziaWG carry traffic to
  your server's own services. On the other protocols, open your sites over the
  internet as usual.
- **DNS through the VPN.** Devices use the DNS the server offers for VPN
  clients. If AdGuard Home or Pi-hole is installed, it can filter for every VPN
  device.
