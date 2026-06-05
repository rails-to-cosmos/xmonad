# Proposal: `xmesh` — a tiny live mesh for my xmonad devices

**Status:** Draft / proposal
**Last updated:** 2026-06-03
**Depends on:** a personal WireGuard overlay (`10.10.0.0/24`) — see `wireguard-setup.md`

---

## Motivation

A Syncthing-like idea, but applied to the *live* layer of my xmonad setup rather
than to files. A small daemon (`xmesh`) runs on each of my devices, discovers the
others over the personal WireGuard overlay, and provides:

- a **control plane** ("restart xmonad / pull config + recompile / run an action on
  all my machines"),
- **shared clipboard**,
- **peer presence** (an xmobar widget: "mesh: 2/3"),
- later: notification relay, workspace-name sync.

### What this is NOT (be honest about scope)

| Need | Better existing tool | Build in xmesh? |
|------|----------------------|-----------------|
| Config files (xmonad.hs, xmobar, scripts, emacs) | **git** (versions, conflicts, history) | No |
| Arbitrary file sync (`~/sync`) | **Syncthing over the WG overlay** | No |
| **Live state** (clipboard, layout, presence) | — | **Yes** |
| **Control plane** (run/restart/push across devices) | ssh / small RPC over overlay | **Yes** |

The real niche is the *live/control* layer; file sync is already solved by git +
Syncthing-over-WireGuard.

---

## Guiding principles

1. **xmesh does NOT solve NAT.** It assumes mutual reachability already exists
   (the personal WG overlay, or a shared LAN). This removes ~80% of Syncthing's
   complexity. Dynamic IPs are WireGuard's problem (roaming), not ours.
2. **Vertical slices, not layers.** Every phase is a working end-to-end feature.
3. **Security-first for `exec`.** "Run on all devices" is a remote code execution
   channel. Token + allowlist from day one, before it can do anything.

---

## Architecture at a glance

```
device 1                              device 2
┌────────────────────┐               ┌────────────────────┐
│ xmesh (single bin) │   overlay/LAN │ xmesh              │
│  ├ HTTP API (warp) │◄──TCP/HTTP───►│  ├ HTTP API        │
│  ├ heartbeat loop  │  bearer-token │  ├ heartbeat loop  │
│  ├ clipboard watch │               │  ├ clipboard watch │
│  └ state: TVar     │               │  └ state: TVar     │
└─────▲────────┬─────┘               └────────────────────┘
      │ CLI    │ spawn allowlisted action
 xmonad keys   ▼
 xmobar    xclip / xmonad --restart / git pull …
```

Single binary, modes: `xmesh daemon` and CLI `xmesh peers|copy|run|status`.
xmonad keybindings and the xmobar widget call the CLI.

---

## Tech choices

| Component | Choice | Why |
|-----------|--------|-----|
| Language/build | Haskell, **cabal project** (GHC 9.6.7) | long-running daemon w/ deps → not runghc |
| HTTP | `warp` + `servant` (or raw `wai`) | testable with curl; easy to call from shell |
| Concurrency | `async` + `stm` (`TVar`) | server / heartbeat / clipboard threads |
| Serialization | `aeson` (JSON) for v1 | human-readable, debuggable; CBOR later |
| Clipboard | external `xclip` + `clipnotify` | no X11 bindings in v1 |
| Service | `systemd --user` unit | like Syncthing |

---

## Decisions to lock (recommended defaults)

1. **Discovery v1:** static peer list of overlay IPs in `~/.config/xmesh/config.toml`.
   Evolves to mDNS/gossip later. *(default: static)*
2. **Transport v1:** HTTP/JSON over the overlay; daemon binds **only to the wg
   interface** (not `0.0.0.0`). *(default: HTTP/JSON)*
3. **exec model:** named **allowlist** of actions (`restart-xmonad`, `pull-config`,
   `recompile`, `notify`) — NOT arbitrary shell by default (separate flag, off).
   *(default: allowlist)*
4. **Auth:** shared `bearer` token in config (HMAC later). Defense-in-depth on top
   of WireGuard's own encryption. *(default: bearer)*

---

## v1 protocol surface

Daemon HTTP endpoints (bound to overlay IP, port e.g. `48222`):

- `GET  /ping`       → `{device, version, ts}` (liveness)
- `GET  /peers`      → known peers + last-seen
- `POST /clipboard`  → `{text, hash, origin}` set local clipboard
- `POST /exec`       → `{action, token}` run an allowlisted action

Auth: `Authorization: Bearer <token>` on all POSTs. CLI:

- `xmesh peers`            — query local daemon `/peers`
- `xmesh copy`             — push current clipboard to peers
- `xmesh run <action> --all` — POST `/exec` to all peers
- `xmesh status`           — one line for the xmobar widget

---

## Phased plan

**Phase 0 — Skeleton (~½ day).** Cabal project, config parser, `xmesh daemon`
serving `GET /ping` on the wg IP; `xmesh ping <peer>` hits another. *Proves:* build,
overlay networking, config. Deliverable: two daemons see each other's `/ping`.

**Phase 1 — Presence/membership (~½ day).** Heartbeat loop polls configured peers,
tracks liveness in a `TVar`. `GET /peers`, CLI `xmesh peers`, and `xmesh status` →
`mesh: 2/3` for an xmobar widget. *Proves:* background threads, shared state, bar
integration. First visible feature.

**Phase 2 — exec security (~½ day, BEFORE any commands).** Bearer token on mutating
endpoints, bind only to wg-iface, allowlist registry, `notify-send` on every
received command (live audit). *Proves:* the control plane is safe before it can do
anything.

**Phase 3 — Control plane (~1 day).** `POST /exec {action,token}` runs an
allowlisted action. CLI `xmesh run restart-xmonad --all`; `xmesh run pull-config
--all` → git pull + recompile everywhere. *The killer feature.*

**Phase 4 — Clipboard sync (~1 day).** `clipnotify` → on local change POST
`/clipboard` to peers; receiver applies via `xclip`. Loop-prevention via hash of the
last value. Opt-in "text only / no secrets". *Proves:* bidirectional live state.

**Phase 5+ (optional).** Gossip membership (SWIM-style: seed node → learn the rest),
notification relay (dunst→dunst), workspace-name sync, CBOR instead of JSON, mDNS
discovery over the overlay.

---

## Security (critical for Phase 2)

```
- listen only on the wg-interface address (config: bind_addr)
- Authorization: Bearer <token> on all POSTs
- exec: named-action registry, not shell; arbitrary_exec=false by default
- notify-send on every incoming exec (real-time audit)
- (later) HMAC signature + nonce against replay
```

---

## Repo layout

```
xmesh/                      (separate repo, or a subfolder of ~/.config/xmonad)
├── xmesh.cabal
├── app/Main.hs             — subcommand dispatch: daemon|peers|copy|run|status
├── src/Xmesh/
│   ├── Config.hs           — parse ~/.config/xmesh/config.toml
│   ├── Protocol.hs         — Message/Peer types (typed DSL)
│   ├── Server.hs           — warp endpoints
│   ├── Client.hs           — http calls to peers
│   ├── Heartbeat.hs        — background loop + TVar liveness
│   ├── Clipboard.hs        — clipnotify/xclip glue
│   └── Actions.hs          — allowlist of named actions
├── systemd/xmesh.service   — user service
└── README.md
```

---

## Prerequisites before Phase 0

- Personal WireGuard overlay up (`wireguard-setup.md`), with each device's stable
  `10.10.0.x` address.
- Device list + overlay IPs.
- Repo location: separate (`~/src/xmesh`) or subfolder of `~/.config/xmonad`?
- Confirm the 4 default decisions above.

## Next step

Once the overlay is up and the 4 decisions confirmed: scaffold **Phase 0** — cabal
project, `Config.hs`, `xmesh daemon` with `/ping`, CLI `xmesh ping`, and
`xmesh.service`. Verify `cabal build` + cross-device `/ping`, then iterate phase by
phase.
