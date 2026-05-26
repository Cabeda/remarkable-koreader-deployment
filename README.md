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

## Usage

```bash
./deploy.sh
```

The script will:
1. Verify SSH connectivity and detect firmware/architecture
2. Show what will be installed and ask for confirmation
3. Create a local backup of existing files
4. Download latest releases from GitHub
5. Install everything in the correct order
6. Start xovi

### Environment variables

| Variable | Default | Description |
|----------|---------|-------------|
| `REMARKABLE_IP` | `10.11.99.1` | Device IP (change if using WiFi SSH) |
| `REMARKABLE_PASS` | *(none)* | SSH root password (avoids repeated prompts; requires `sshpass`) |

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
5. Set a **Download folder** (e.g., `/home/root/xovi/exthome/appload/koreader/readeck/`)
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
| SSH connection refused | Check USB cable, verify IP with `ping 10.11.99.1` |
| KOReader not in AppLoad | Run `xovi/rebuild_hashtable` on device, restart xovi |
| xovi-tripletap not working | Check: `systemctl status xovi-tripletap` on device |
| Readeck plugin not visible | Verify plugin is in `koreader/plugins/readeck.koplugin/` |
| Want to uninstall everything | Reboot (clears xovi), then `rm -rf ~/xovi ~/xovi-tripletap ~/shims` |

## Updating

Re-run `./deploy.sh` — it will download the latest versions and overwrite existing installations. Your KOReader settings and readeck configuration are preserved (stored in `koreader/settings/`).

## License

This deployment script is provided as-is. The installed components have their own licenses:
- xovi: GPL-3.0
- rm-appload: GPL-3.0
- xovi-tripletap: GPL-3.0
- KOReader: AGPL-3.0
- readeck.koplugin: MIT
