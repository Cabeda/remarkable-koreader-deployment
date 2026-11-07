---
name: remarkable-koreader
description: Install, update, repair or verify KOReader on a reMarkable 2 over USB. Use when asked to "install KOReader on the reMarkable", "update the tablet", "KOReader is gone after the update", "KOReader is not in AppLoad", or "is the reader healthy". Covers xovi/rm-appload reinstalls, hashtable rebuilds, keeping reading data, and the failure modes this repo already hit.
---

# reMarkable 2 KOReader deployment

`deploy.sh` installs xovi, rm-appload, xovi-tripletap, KOReader and readeck.koplugin over
USB, and is safe to re-run. It merges KOReader over the existing tree, so `settings/`,
books and the Readeck folder survive. Everything is idempotent — when in doubt, run it
again rather than hand-fixing the device.

## Preconditions

Check these before running anything; don't start a 45 MB download to discover them.

1. `.env` exists with `REMARKABLE_IP` and `REMARKABLE_PASS` (copy `.env.example`).
2. `sshpass` is installed when `REMARKABLE_PASS` is set (`brew install sshpass`).
3. The device answers: `ping -c1 10.11.99.1` (USB) or the configured IP.
4. `./status.sh` runs without `unreachable`. It exits 2 when the device is not there.

Never print, commit or echo `REMARKABLE_PASS`. It lives in `.env`, which is gitignored.

## Workflow

1. `./status.sh` — record what is there now.
2. `./deploy.sh --yes` — install or repair. Without `--yes` it prompts; agents must pass it.
3. Wait ~60 s after it finishes. The last step restarts xochitl, and SSH drops for about a
   minute. That is expected, not a failure.
4. `./status.sh` — expect `xovi: running`, a `koreader:` version, and `readeck:` present.
5. Tell the owner to open the sidebar → **AppLoad** → **KOReader**. The agent cannot
   launch or verify the GUI.

For the "never think about it again" setup, install the watchdog once:
`./autoupdate.sh` (launchd, every 15 min, re-installs only when `/etc/version` changed).

## Failure modes already seen here

| Symptom | Cause | Fix |
|---|---|---|
| `Host key verification failed` | Firmware updates regenerate the device host key | Already handled: SSH args use `UserKnownHostsFile=/dev/null` |
| `Permission denied` after several fast SSH calls | Device rate-limits login bursts (~8 in a row) | Already handled: connections multiplex over one `ControlMaster` |
| `unzip: short read` / archive errors | Upstream switched assets to `.tar.gz`/`.targz` | Already handled: extraction is chosen from the filename |
| Script hangs on "Starting xovi..." | `xovi/start` can hold the SSH channel open | Already handled: it runs detached, log at `/tmp/xovi-start.log` |
| SSH dead right after install | xochitl restart, ~60 s | Wait and retry |
| `The download directory is not valid.` (Readeck) | Plugin requires the folder to exist (`lfs.attributes`) | `mkdir -p /home/root/readeck` and set it in Readeck settings |
| KOReader missing from AppLoad | Hashtable built against a different firmware | `./deploy.sh --yes`, then re-check |

`/media` is on the rootfs: anything created there disappears at the next firmware update.
Keep user data under `/home/root/`.

## Hard rules

- **Do not edit `settings.reader.lua` while KOReader is running.** It rewrites the file on
  exit and silently undoes the change. Stop KOReader first (`pidof koreader`).
- **Do not add xovi to boot via systemd.** It is tethered on purpose; auto-start can
  bootloop the device. xovi-tripletap is the supported way to start it.
- **Do not delete `/home/root`.** It holds the only copy of books, settings and Readeck
  downloads. `deploy.sh` backs up xovi/shim dirs to `backups/<timestamp>/` before touching
  anything.
- **Never reboot the device unless asked.** A reboot drops xovi until the owner triple-taps
  the power button.
- Firmware updates are the owner's decision. Don't trigger them; expect them.

## Repo layout

| Path | Purpose |
|---|---|
| `deploy.sh` | install/repair/update; `--yes`, `--if-changed` |
| `status.sh` | read-only health check |
| `autoupdate.sh` | install/remove the launchd watchdog |
| `.last-firmware` | last firmware deployed (gitignored, written by `deploy.sh`) |
| `backups/` | pre-install tarballs (gitignored) |
