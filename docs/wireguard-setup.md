# Personal WireGuard Overlay — Setup Guide

**Hardware:** Framework Laptop 16 (AMD) + other personal devices (phone, etc.)
**OS:** CachyOS, kernel 7.0.x
**Last updated:** 2026-06-03
**Purpose:** A *personal* WireGuard overlay between my own devices, separate from the
corporate `wg-crypto` tunnel. This overlay (`10.10.0.0/24`) is the foundation the
`xmesh` daemon assumes for peer connectivity — see `xmesh-proposal.md`.

---

## Why a separate overlay

- `wg-crypto` is the work tunnel (subnet ~`10.17.0.0/16`). Do **not** reuse it.
- The personal mesh lives on its own interface (`wg0`) and subnet (`10.10.0.0/24`)
  so the two coexist with zero routing conflicts (details at the bottom).
- WireGuard gives each device a **stable overlay IP** (`10.10.0.x`) regardless of
  its changing public IP — its roaming feature updates a peer's endpoint on any
  authenticated packet, so dynamic client IPs "just work" as long as the hub is
  reachable.

---

## Step 0 — Choose the anchor (determines everything)

WireGuard has no built-in discovery; with dynamic IPs you need ONE node with a
stable address that the others connect to (hub-and-spoke).

| Anchor | When it fits | Cost |
|--------|--------------|------|
| **VPS** (Hetzner/etc., ~$4/mo) | always works, even if clients are behind CGNAT | most reliable |
| **Home box + port-forward + DDNS** | only if home has a **public IPv4** (no CGNAT) | free |
| **No anchor** | only same-LAN, or all devices have public IPv6 | limited |

> Recommended default: **hub-and-spoke with a VPS**. The recipe below uses that.
> Variant for a home anchor: identical, but the hub is your home machine,
> `Endpoint` is a DDNS name, and you must port-forward UDP 51820 on the router.

**Decision pending:** VPS, or home anchor with public IPv4? (Check CGNAT/IPv6 with
`curl -4 ifconfig.co` / `curl -6 ifconfig.co`.)

---

## Step 1 — Generate keys (on every device)

```bash
wg genkey | tee privatekey | wg pubkey > publickey
# privatekey = secret, never share. publickey goes into the peer's config.
```

Do this for: the hub (VPS), the laptop, the phone, etc. Record which public key
belongs to which device.

---

## Step 2 — Hub config (on the VPS: `/etc/wireguard/wg0.conf`)

```ini
[Interface]
Address    = 10.10.0.1/24
ListenPort = 51820
PrivateKey = <VPS_PRIVATE_KEY>
# enable spoke<->spoke routing (so laptop can reach phone through the hub):
PostUp     = sysctl -w net.ipv4.ip_forward=1

[Peer]                       # laptop
PublicKey  = <LAPTOP_PUBLIC_KEY>
AllowedIPs = 10.10.0.2/32

[Peer]                       # phone
PublicKey  = <PHONE_PUBLIC_KEY>
AllowedIPs = 10.10.0.3/32
```

Open the UDP port on the VPS: `ufw allow 51820/udp` (or in the provider firewall).

> No NAT/MASQUERADE is needed: all traffic stays inside the `10.10.0.0/24` overlay;
> the hub only *forwards* between spokes. MASQUERADE is only required if you route
> the public internet through the hub (full-tunnel), which we are NOT doing.

---

## Step 3 — Client config (laptop: `/etc/wireguard/wg0.conf`)

```ini
[Interface]
Address    = 10.10.0.2/32
PrivateKey = <LAPTOP_PRIVATE_KEY>

[Peer]                       # hub
PublicKey           = <VPS_PUBLIC_KEY>
Endpoint            = vps.example.com:51820   # or the VPS IP
AllowedIPs          = 10.10.0.0/24            # overlay ONLY — never 0.0.0.0/0
PersistentKeepalive = 25                       # keeps the NAT mapping alive
```

Key points:
- **`AllowedIPs = 10.10.0.0/24`** (not `0.0.0.0/0`): only mesh traffic enters the
  tunnel; normal internet and `wg-crypto` are untouched. This is the secret to
  peaceful coexistence.
- Whole-`/24` AllowedIPs means "all other spokes via the hub" — combined with
  forwarding (Step 2), laptop<->phone works through the VPS.
- The phone is the same pattern (`Address = 10.10.0.3/32`); the official WireGuard
  app imports the config, optionally via QR: `qrencode -t ansiutf8 < wg0.conf`.

---

## Step 4 — Bring up + autostart

```bash
sudo wg-quick up wg0
sudo systemctl enable wg-quick@wg0     # start on boot
```

Separate interface `wg0` (not `wg-crypto`); can be managed by systemd or an xmonad
startup spawn — independent of the work tunnel.

---

## Step 5 — Verify

```bash
sudo wg show wg0          # peers, latest handshake, rx/tx
ping 10.10.0.1            # hub
ping 10.10.0.3            # another of my devices (routed via hub)
ip -br a show wg0         # stable overlay IP
```

A fresh `latest handshake` = tunnel alive. A successful ping between two of my own
devices = the overlay for `xmesh` is ready.

---

## Coexistence with `wg-crypto`

- Different interfaces (`wg0` vs `wg-crypto`), different subnets (`10.10` vs `10.17`),
  different config files — no conflict.
- Even if `wg-crypto` is full-tunnel (`0.0.0.0/0`), `wg0` with
  `AllowedIPs=10.10.0.0/24` only installs a *more specific* route, so the default
  route is not overridden. Both tunnels can be up simultaneously.
- Existing `ab-vpn-connect` / `ab-vpn-disconnect` (for `wg-crypto`) stay as-is; for
  the personal mesh add `wg-quick up/down wg0` (or autostart).

---

## Helper functions (fish)

Add to `~/.config/fish/config.fish` to mirror the existing `ab-vpn-*`:

```fish
function mesh-up
    sudo wg-quick up wg0
end
function mesh-down
    sudo wg-quick down wg0
end
function mesh-status
    sudo wg show wg0
end
```

---

## References

- [WireGuard Quick Start](https://www.wireguard.com/quickstart/)
- [wg-quick(8)](https://man7.org/linux/man-pages/man8/wg-quick.8.html)
- `xmesh-proposal.md` — the daemon that rides on this overlay
