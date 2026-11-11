# Agent notes

Deploying KOReader to the reMarkable 2 is covered by a skill:

- [.agents/skills/remarkable-koreader/SKILL.md](.agents/skills/remarkable-koreader/SKILL.md)

Read it before touching the device. Short version: `./status.sh` to see state,
`./deploy.sh --yes` to install or repair, wait ~60 s afterwards because xochitl restarts.
Never edit `koreader/settings.reader.lua` while KOReader is running, and never delete
`/home/root`.
