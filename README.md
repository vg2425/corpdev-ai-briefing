# corpdev-ai-briefing

Private archive of Victoria's twice weekly AI and Tech briefings, prepared in Cowork mode.

## Layout

```
corpdev-ai-briefing/
  index.html                  Landing page linking to every edition
  briefings/                  One HTML file per edition
    vic_ai_briefing_YYYY-MM-DD.html
  scripts/
    generate_index.py         Rebuilds index.html from the briefings/ folder
    auto_push.ps1             Commits new briefings and pushes main (Windows)
    install_auto_push.ps1     Registers the scheduled task that runs auto_push.ps1
  .github/workflows/
    publish.yml               Read only sanity check on index.html
  docs/AUTOMATION.md          How the automation works and how to fix it
```

## How a new edition gets added

Nothing to do by hand. Two pieces, kept separate:

1. **Cowork writes the files.** A Cowork scheduled task runs Monday and Thursday mornings, writes `briefings/vic_ai_briefing_YYYY-MM-DD.html` and runs `python scripts/generate_index.py`. Its sandbox cannot reach GitHub, so it does not push.
2. **A Windows scheduled task commits and pushes.** `corpdev-ai-briefing auto push` runs `scripts/auto_push.ps1` every 30 minutes and at logon. It clears lock files the sandbox leaves in `.git/`, makes one `briefing: YYYY-MM-DD` commit per new edition, rebases on `origin/main` and pushes.

Each run writes one line to `.push_status` in the repo root (time, result, HEAD, last push), so the Cowork run and you can see the last push at a glance. The full log is `%LOCALAPPDATA%\corpdev-ai-briefing\auto_push.log`.

To add an edition manually, drop the file into `briefings/`. The next task run commits and pushes it. To push right away, run:

```
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\auto_push.ps1
```

See `docs/AUTOMATION.md` for setup, troubleshooting and the GitHub credential setup.

## Sharing

Repo is private. If we enable GitHub Pages from this private repo (requires GitHub Pro / Team / Enterprise), the rendered briefings become reachable at a link without exposing the source.

## Caveats

Briefings are AI generated. They cross verify sources, but some quote attributions, dates, and dollar figures are flagged as uncertain inline. Always confirm before forwarding externally.
