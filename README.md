# reMarkable 2 KOReader Deployment

Automated deployment script for installing KOReader + readeck.koplugin on a reMarkable 2 (firmware 3.20+) using the xovi framework.

## What gets installed

| Component | Purpose |
|-----------|---------|
| [xovi](https://github.com/asivery/rm-xovi-extensions) | Extension framework (tethered — reboot returns to stock) |
| [rm-appload](https://github.com/asivery/rm-appload) | App launcher accessible from the stock UI sidebar |
| [xovi-tripletap](https://github.com/rmitchellscott/xovi-tripletap) | Start xovi by triple-pressing the power button (no SSH needed) |
| [KOReader](https://github.com/koreader/koreader) | Feature-rich e-book reader |
| [readeck.koplugin](https://github.com/iceyear/readeck.koplugin) | Sync articles from a Readeck server |

## Prerequisites

- reMarkable 2 with firmware ≥ 3.20
- USB cable connected to your computer
- SSH access to the device (root password from Settings > Help > Copyrights and licenses)
- `curl`, `ssh`, `scp`, `tar`, `unzip` available on your machine
- `sshpass` if you store the password in `.env` (`brew install sshpass`)

## Usage

```bash
./deploy.sh          # install or repair (asks for confirmation)
./status.sh          # read-only health check
```

The script will:
1. Verify SSH connectivity and detect firmware/architecture
2. Show what will be installed and ask for confirmation
3. Create a local backup of existing files
4. Download latest releases from GitHub
5. Install everything in the correct order
6. Start xovi

Options: `--yes` (skip the confirmation prompt) and `--if-changed` (exit early when the
device's `/etc/version` matches `.last-firmware`, i.e. the firmware has not been updated
since the last successful run).

Expect SSH to be dead for about a minute after the script finishes: the last step restarts
`xochitl`.

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REMARKABLE_IP` | `10.11.99.1` | Device IP (change if using WiFi SSH) |
| `REMARKABLE_PASS` | *(none)* | SSH root password (avoids repeated prompts; requires `sshpass`) |

Both are read from `.env` in this directory if present.

## Surviving reMarkable OS updates

Firmware updates replace the root filesystem. `/home/root` survives, so KOReader itself
(and its settings and downloads) is not deleted — but the rootfs pieces are: the
hashtable, any `/etc` hooks, and xovi's compatibility with the new libraries. In
practice, after every update xovi must be reinstalled and its hashtable rebuilt against
the new firmware, or KOReader will not launch.

Re-running `./deploy.sh` does exactly that, and it is safe to repeat:
- xovi and rm-appload are reinstalled, and `rebuild_hashtable` runs.
- KOReader is merged over the existing directory instead of replaced, so
  `settings/`, books and `readeck/` are kept.
- The installed firmware is recorded in `.last-firmware`.

To have this happen without you doing anything, install the watchdog once:

```bash
./autoupdate.sh          # install
./autoupdate.sh remove   # uninstall
```

That adds a launchd job (`com.<you>.remarkable-koreader`) that runs
`deploy.sh --yes --if-changed` every 15 minutes and logs to `autoupdate.log`. It only
does work when the device is reachable and its firmware version changed. The device must
be on USB or the same network for the check to succeed.

## Installing with a coding agent

The install procedure is packaged as an agent skill, so a coding agent can do the work
instead of you:

```
.agents/skills/remarkable-koreader/SKILL.md
```

Point the agent at this repo and ask it to install KOReader on the tablet. The skill covers
prerequisites (`sshpass`, `.env`), the install/verify loop, and every failure mode this
repo has actually hit — host-key changes, login rate limits, archive format changes, the
SSH dropout after a restart, and the Readeck download-directory error. `AGENTS.md` points
there too, so agents discover it on their own.

## Post-install: Using KOReader

1. After the script completes, the device will restart into xovi
2. Open the **sidebar** (swipe from right edge) and tap **AppLoad**
3. Launch **KOReader** from the AppLoad menu

### After a reboot

The device boots into stock reMarkable OS. To get KOReader back:
- **Triple-press the power button** — xovi-tripletap will start xovi automatically
- Or SSH in and run: `xovi/start`

## Post-install: Configuring Readeck

The readeck.koplugin requires a running [Readeck](https://readeck.org) server.

### Setup steps (in KOReader on the device)

1. Open KOReader
2. Go to **Main Menu → Readeck → Settings → Configure Readeck server**
3. Enter your server URL (e.g., `https://read.example.com` — without `/api`)
4. Choose authentication:
   - **API Token** — paste your token
   - **OAuth (Device Flow)** — follow the on-screen prompts
5. Set a **Download folder** — e.g. `/home/root/readeck/`. It must exist on the device
   (`mkdir -p /home/root/readeck`); the plugin refuses to sync otherwise. Do not use
   `/media/...`: that lives on the root filesystem and disappears at the next firmware
   update.
6. (Optional) Configure tag filters, sort order, sync settings

### Full plugin documentation

See the [readeck.koplugin README](https://github.com/iceyear/readeck.koplugin#readme) for all configuration options including:
- Highlight sync
- Reading progress sync
- Periodic auto-sync
- Article completion actions (archive/delete)

## Safety notes

- **xovi is tethered by design** — a simple reboot always returns to stock OS
- **Never set xovi to auto-start on boot** via systemd — this can cause bootloops
- xovi-tripletap is the safe alternative (user-initiated, not automatic)
- The backup created by the script is saved in `./backups/` with a timestamp

## Troubleshooting

| Problem | Solution |
|---------|----------|
| SSH connection refused or timeout | Check the cable, `ping 10.11.99.1`. After an install, wait ~60 s: xochitl is restarting |
| `Host key verification failed` | The device regenerates its host key on firmware updates. `deploy.sh` already ignores known_hosts |
| `Permission denied` on repeated runs | The device rate-limits login bursts. `deploy.sh` multiplexes one connection; wait a minute if it still bites |
| `unzip: short read` | Upstream changed the archive format. Update `deploy.sh`; it picks the extractor from the filename |
| Install hangs on "Starting xovi..." | `xovi/start` can hold the channel open. The script runs it detached; check `/tmp/xovi-start.log` |
| KOReader not in AppLoad | Hashtable built against a different firmware: re-run `./deploy.sh --yes` |
| Readeck: "download directory is not valid" | The folder does not exist. `mkdir -p /home/root/readeck` and set it in Readeck settings |
| Readeck sync does nothing on schedule | Periodic sync needs the network; on USB there is no internet, use Wi-Fi |
| xovi-tripletap not working | `ls /home/root/xovi-tripletap`; reinstall from its [repo](https://github.com/rmitchellscott/xovi-tripletap) if missing |
| Want to uninstall everything | Reboot (clears xovi), then `rm -rf ~/xovi ~/xovi-tripletap ~/shims`. Books and settings live in `~/xovi/exthome/appload/koreader/` — delete that too if you mean it |

## Updating

Re-run `./deploy.sh`. It downloads the latest releases and merges them over the existing
installation, so `settings/`, books and the Readeck folder survive. Plugins you disabled
live in `koreader/plugins.disabled/` and stay disabled across updates — move one back into
`plugins/` to re-enable it.

## License

This deployment script is provided as-is. The installed components have their own licenses:
- xovi: GPL-3.0
- rm-appload: GPL-3.0
- xovi-tripletap: GPL-3.0
- KOReader: AGPL-3.0
- readeck.koplugin: MIT
