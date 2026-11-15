# Network scenarios

When you set up a server, you choose how it is reached. This choice is the
**scenario**. It decides which services can run, who can reach them, and what
you need besides the server itself: a domain, open ports, a second machine.

There are seven scenarios.

| Scenario | Machines | Public IP | Domain | Ports to open | Certificate | Mail | VPN | Reach from outside |
|---|---|---|---|---|---|---|---|---|
| **Public IP** | 1 (VPS or a machine with a public IP) | Yes | Yes | On the server | Let's Encrypt | Yes | Yes | Anyone, over the internet |
| **Public IP (VPS) + Local server** | 2 (a VPS and a machine at home) | On the VPS | Yes | On the VPS only | Let's Encrypt | Yes | Yes | Anyone, over the internet |
| **Local Server** | 1 (at home) | No | No | None | Self-signed | No | No | Your own network only |
| **Server without open ports** | 1 | No | Yes, at Cloudflare | None | Cloudflare | No | No | Anyone, web only |
| **Home server with a changing address** | 1 (at home) | Yes, changes over time | Yes | On the router | Let's Encrypt | Yes | Yes | Anyone, over the internet |
| **Only my own devices** | 1 | No | No | None | Self-signed | No | No | Devices in your Headscale mesh |
| **Only my own devices (Tailscale)** | 1 | No | No | None | Tailscale | No | No | Devices on your Tailscale account |

## How to choose

Answer these in order:

1. **Do you need mail or a VPN?** Both need ports reachable from the internet.
   That leaves "Public IP", "Public IP (VPS) + Local server" or "Home server with a
   changing address".
2. **Is the server a VPS, or at home?**
   - A VPS: **Public IP**.
   - At home, and the provider gives you a public IPv4 address and lets you
     forward ports: **Home server with a changing address**.
   - At home, behind CGNAT, or you do not want to open ports at home:
     **Public IP (VPS) + Local server**. Rent
     a small VPS that receives the traffic.
3. **Only web services, no ports at home, but reachable from anywhere?**
   **Server without open ports** (needs a domain at Cloudflare).
4. **Nobody but you should ever reach it?**
   - At home only: **Local Server**.
   - From your own phones and laptops anywhere: **Only my own devices
     (Tailscale)**. If you would rather not depend on an outside account and
     your devices join from home: **Only my own devices**.

| You want | Pick |
|---|---|
| Everything, cheapest, one machine | Public IP |
| Your data at home, everything public, no ports at home | Public IP (VPS) + Local server |
| Your data at home, everything public, ports at home are fine | Home server with a changing address |
| Nextcloud from anywhere, no VPS, no ports | Server without open ports |
| Home Assistant and photos, only for the family's own devices | Only my own devices (Tailscale) |
| A lab on the home network | Local Server |

## The scenarios in detail

### Public IP

One server with a public IP address. The services, the HTTPS certificates and
the DNS records all point at it. This is the simplest setup and the fastest one,
because every connection goes straight to the machine.

- The app writes the firewall on the server and lists the ports you must also
  open in your hosting provider's firewall.
- If you give the app a DNS provider token, it creates the records itself.
  Otherwise it shows you the records to enter.

### Public IP (VPS) + Local server

Two machines working as one server. The **local server** at home holds the
services and their data. The **VPS** has the public IP: it receives the traffic
and forwards it to the home machine over a WireGuard tunnel that the home
machine opens to the VPS. Nothing has to be opened on your home router.

- Ports are opened on the VPS only.
- The home machine keeps its own local address. On your home network, the app
  and the terminal reach it directly; away from home, through the VPS.
- Services meant only for the home network, such as Home Assistant or
  Zigbee2MQTT, stay at home and are not published.

**Where the VPN runs.** The VPN can run on the home machine or on
the VPS, and you can move it at any time from the server's VPN section ("Move
the VPN to the VPS"). Keys, devices and their addresses move with it, so
devices keep their configurations.

- **On the VPS (recommended for speed).** Internet traffic from your devices
  leaves straight from the VPS. Only traffic to your own sites still goes home
  through the tunnel. The VPN is as fast as the VPS's connection.
- **At home.** Everything the VPN carries crosses your home connection twice:
  in from the VPS and back out to the internet. Your home **upload** speed caps
  the VPN, and most home connections upload far slower than they download. Pick
  this only if traffic must leave from your home address.

While the VPN runs on the VPS, its web panel is not published. Devices are
managed from the app.

### Local Server

A server on your own network only: no public IP, no domain, a self-signed
certificate. Mail and the VPN are not available, since both must be reachable
from outside. Good for a lab or for services nobody outside the house needs.

### Server without open ports

Your domain, reached through a Cloudflare Tunnel. The server dials out to
Cloudflare, so nothing is forwarded to it and no port is opened. A tunnel
carries web traffic only, so mail and the VPN are not available. You need a
domain managed at Cloudflare and a token for it.

### Home server with a changing address

A real domain and open ports at home, but the provider changes your IP now and
then. The agent watches the address and updates the DNS records itself, so the
names never go stale. Mail and the VPN work. You need a public IPv4 address
(not CGNAT) and ports forwarded on the router; the app lists which ones.

### Only my own devices

No public address and no open ports. The server runs **Headscale**, its own
private mesh, and the services answer only to phones and laptops joined to it.
The server joins its own mesh too. The certificate is self-signed, so devices
join from your own network. Away from home, use the Tailscale variant.

### Only my own devices (Tailscale)

The same idea, but the private network is your own Tailscale account, so it
works behind any router and from anywhere. Needs an account at tailscale.com,
and every device runs Tailscale on that account.

## Requirements common to every scenario

- **Debian or Ubuntu**, x86-64 or ARM (a Raspberry Pi works), with SSH access
  for root or a user who can use sudo.
- About 1 GB of free disk for the installer, plus room for the services.
- For "Public IP", "Public IP (VPS) + Local server" and "Home server with a
  changing address": a domain. The app can
  create the records through Cloudflare, DigitalOcean, GoDaddy, Google Cloud
  DNS, Hetzner, OVH, Porkbun or Route 53, or show them for you to enter.
