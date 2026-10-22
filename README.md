# macmon

A small, always-on macOS menu bar monitor for Apple Silicon. Live CPU, memory, GPU, network, die temperature, and Claude subscription usage. Click the notch (or the menu bar item) to open a compact panel.

No history, no charts, no daemon: one `LSUIElement` process, one run loop, no IPC.

## Install, update, uninstall

`install.sh` is also the update command: it is idempotent and safe to run any time.

| Action | Command |
|---|---|
| Install, update, or reinstall | `./scripts/install.sh` |
| Uninstall, keep cached Claude stats | `./scripts/uninstall.sh` |
| Uninstall and clear all cached state | `./scripts/uninstall.sh --purge` |

What each one does:

- **Install / update**: builds `build/macmon.app`, boots out any running launch agent, stops the old process, replaces `~/Applications/macmon.app`, rewrites `~/Library/LaunchAgents/dev.arkab.macmon.plist`, then bootstraps it. Your cached Claude percentages in `~/Library/Application Support/macmon/` are preserved.
- **Uninstall**: boots out the launch agent, stops the process, deletes the app and the plist. Cached Claude stats and the JSONL read offsets remain.
- **Uninstall `--purge`**: same, plus deletes `claude.json` and `jsonl-state.json` and the cache directory. It never touches Keychain credentials, Claude Code logs, or Accessibility permissions.

Run the script names exactly; do not type the brackets (`[--purge]` is a glob in zsh and will fail).

After a reinstall, macOS may ask for **Accessibility** again (the bundle is replaced) and the Keychain prompt may reappear if the signature changed. Choose Always Allow / re-enable macmon in System Settings.

```
CPU          24%                MEMORY   12.4 GB / 16.0 GB
load 3.42 · 10 cores           wired 3.2 GB · comp 6.1 GB · swap 508 MB
GPU          41%                NETWORK  ↓ 5.2 KB/s   ↑ 50.4 KB/s
TEMPERATURE  53°C               gpu 51°C · peak 53°C
CLAUDE       PRO
5 hour       58%   resets in 2h 14m
weekly       50%   resets in 3d 4h
```

## Requirements

- macOS 14 or newer. Notch-click needs a built-in display with a notch (MacBook Air/Pro); otherwise use the menu bar item.
- Apple Silicon (temperature and GPU readers target Apple Silicon).
- Swift 6 toolchain. Command Line Tools are enough; Xcode is not required.
- No root, no sudo, no entitlements, no sandbox.

## Build

```sh
cd ~/Projects/macMonitor
./scripts/build.sh
```

Produces `build/macmon.app`, signed ad-hoc by default. To run it in development:

```sh
open build/macmon.app
```

Or run the binary directly (it sets accessory activation policy itself):

```sh
.build/release/MacmonApp
```

## Install as a login item

```sh
./scripts/install.sh
```

Copies the app to `~/Applications/macmon.app`, writes `~/Library/LaunchAgents/dev.arkab.macmon.plist` (`RunAtLoad`, `KeepAlive`), and bootstraps it into your GUI session. It starts immediately and on every login.

```sh
./scripts/measure.sh      # pid, RSS, footprint, idle CPU
./scripts/uninstall.sh    # remove app + launch agent, keep cached stats
./scripts/uninstall.sh --purge   # also remove cached stats
```

## Use

- Click the notch area, or the menu bar item, to toggle the panel.
- Click outside or press Escape to close.
- The panel is always dark with high-contrast text, regardless of the system light/dark setting, so it stays readable over any wallpaper.
- The menu bar title shows CPU percent and peak die temperature, e.g. `12% 53°`.
- Closed: samples every 5 s. Open: every 2 s. Sampling pauses when the display sleeps.
- Claude usage polls at most every 5 minutes, backs off on 429s, and shows cached values as `STALE` when offline or rate limited.

No history is stored. Only the latest sample exists in memory.

## What it reads

| Metric | Source | Notes |
|---|---|---|
| CPU | `host_processor_info` | total, per-core, load average |
| Memory | `host_statistics64`, `sysctl` | used/wired/compressed/cached, swap, pressure |
| GPU | IOKit `IOAccelerator` → `PerformanceStatistics` | device and renderer utilization |
| Network | `getifaddrs` + `if_data` | `en*` interfaces only; 32-bit counter wrap handled |
| Temperature | SMC (`AppleSMC`) | CPU `Tp*`, GPU `Tg*` sensors, no root |
| Claude | `api.anthropic.com/api/oauth/usage` | 5-hour and weekly utilization, plan, resets |

Temperature and GPU use private/undocumented interfaces. If the OS changes them, the module reports `--` instead of crashing.

## Claude usage and credentials

The app reads the OAuth credentials that Claude Code already stores in your login Keychain:

```
service: "Claude Code-credentials"
```

It uses `SecItemCopyMatching` in-process, keeps the token in memory, and sends it only to `api.anthropic.com/api/oauth/usage` with `User-Agent: claude-code/...`.

What it will not do: write to the Keychain, refresh or rotate the token, log it, or store it. Only utilization percentages, reset timestamps, and the plan name are cached, at:

```
~/Library/Application Support/macmon/claude.json
```

If the token is expired, the app waits for Claude Code to refresh it and shows cached values. If the API is unavailable or rate limited, it estimates the last 5 hours from `~/.claude/projects/**/*.jsonl` and labels the result `LOCAL ESTIMATE`.

Environment overrides:

```sh
CLAUDE_CODE_OAUTH_TOKEN=...   # use an explicit token instead of the Keychain
```

First Keychain read prompts once. Choose **Always Allow**. Rebuilding with an ad-hoc signature changes the binary's identity and triggers the prompt again. To avoid that, create a self-signed code-signing certificate named `macmon-dev` (Keychain Access → Certificate Assistant → Create a Certificate → Code Signing). `build.sh` detects and uses it automatically.

## Permissions

- **Accessibility** — required only to detect clicks in the notch region via a global mouse monitor. macOS prompts on first launch. Without it, the menu bar item still works fully.
- **Keychain** — read-only access to the Claude Code credentials item, as above.
- Nothing else. No screen recording, no input monitoring beyond the click monitor, no network access other than the usage endpoint.

## Claude usage panel

The Claude section never re-reads the Keychain on a timer: credentials are read
once per app lifecycle and only re-read after a 401/403 or when the cached token
is within 60 s of expiry (capped at three forced reloads per lifecycle).

Under the 5-hour bar a projection line summarizes the trend from the last 30
minutes of utilization samples: `exhausted` (red), `runout ~… before reset`
(orange), `hot pace · throttle likely` (yellow, > 25 %/h), `idle · resets …`
(green) or `on pace · resets …` (green). The weekly bar shows
`N% used · resets <day time>`.

### Open sessions

`OPEN SESSIONS →` on the metrics page opens a session list: running `claude` /
`opencode` processes with their terminal tty and working directory. `opencode`
rows are enriched with title/directory from the local `opencode.db`
(read-only, loaded via dlopen only while the page is open). Clicking a row
focuses the terminal tab (iTerm2 or Terminal) via that tty, falling back to
opening the directory in Finder.

## Memory and footprint

Measured on a MacBook Air M5 (16 GB, macOS 26.4), one minute after launch with the panel closed, installed as a LaunchAgent:

| Metric | Value |
|---|---|
| `phys_footprint` closed | 10–21 MB (graphics caches warm or cold) |
| Private dirty | ~7–10 MB |
| RSS | ~39–49 MB (includes shared AppKit/Swift pages) |
| Idle CPU | 0.0–0.4 % (0.1 % steady) |
| Binary size | ~470 KB |
| Peak footprint at first launch | ~58 MB (Swift runtime + URLSession + first Keychain/JSON work) |

RSS overstates a Swift/AppKit app because it counts shared framework pages; use `footprint -p <pid>` for the number that matters. Gates used during development: footprint ≤ 24 MB, private dirty ≤ 8 MB, idle CPU ≤ 0.3 %.

## Development

```sh
swift build -c release

.build/release/MacmonApp --selftest   # pure math/format/geometry checks
.build/release/MacmonApp --probe      # one-shot sensor dump incl. Claude
.build/release/MacmonApp --geometry   # screen, notch rect, trigger rect
.build/release/MacmonApp --render /tmp/panel.png   # render the metrics page to PNG
.build/release/MacmonApp --render-sessions /tmp/sessions.png   # render the sessions page to PNG
.build/release/MacmonApp --sessions   # print running claude/opencode sessions
MM_DEBUG=1 .build/release/MacmonApp --probe   # verbose SMC discovery/values
MACMON_DEMO=1 .build/release/MacmonApp        # open the panel after 1.5 s
```

There is no XCTest target: Command Line Tools only ship without XCTest, so checks live in `SelfCheck` and run via `--selftest`.

To create a stable signing identity for development:

1. Keychain Access → Certificate Assistant → Create a Certificate.
2. Name `macmon-dev`, type Code Signing, self-signed.
3. Run `./scripts/build.sh`; it picks the identity up.

## Troubleshooting

**Temperature shows `--`.** Run `MM_DEBUG=1 .build/release/MacmonApp --probe`. If SMC discovery fails, the keys may have changed in an OS update; the rest of the app still works.

**Clicking the notch does nothing.** Grant Accessibility to `macmon` in System Settings → Privacy & Security → Accessibility, then relaunch. After reinstalling, re-add the app.

**Keychain prompt on every rebuild.** Ad-hoc signatures change identity. Use the `macmon-dev` certificate.

**Claude section says STALE or LOCAL ESTIMATE.** The usage endpoint rate-limits undocumented clients. The panel shows the reason. Polling is already floored at 5 minutes with exponential backoff; do not lower it.

**Launch agent does not start.**

```sh
launchctl print gui/$(id -u)/dev.arkab.macmon
log show --last 5m --predicate 'process == "macmon"'
```

**Menu bar item is missing.** macOS hides overflow items; remove another item or widen available space. The notch trigger is independent of the status item.

## Project layout

```
Package.swift
Sources/
  CShims/            C: Mach CPU/memory, IOKit GPU, getifaddrs, SMC
  MacmonCore/
    Models.swift     snapshots and readings
    Samplers.swift   SystemMonitor
    Deltas.swift     counter math
    Formatters.swift byte/rate/temp/countdown formatting
    SelfCheck.swift  built-in checks
    Claude/          Keychain, usage client, JSONL fallback
    Notch/           notch geometry
    UI/              PanelView (single custom-drawn view)
    App/             AppDelegate, NotchController
  MacmonApp/         main.swift
Resources/Info.plist
scripts/             build, install, uninstall, measure
```

## Privacy

No telemetry, analytics, or crash reporting. The only outbound request is the Claude usage GET described above. The only persisted state is the small Claude cache and JSONL read offsets, both in `~/Library/Application Support/macmon/`.

Credentials are never written by this app. If a token is exposed by other means, rotate it with `/logout` + `/login` in Claude Code and revoke the session in claude.ai settings.
