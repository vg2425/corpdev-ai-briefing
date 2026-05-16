# Bi weekly publishing automation

Two cleanly separated pieces. Keep them separate so each can fail or be re run independently.

## Piece 1 · Generation (Cowork side)

Cowork's `mcp__scheduled-tasks__create_scheduled_task` runs a recurring task that calls the briefing prompt and saves the output as `briefings/vic_ai_briefing_YYYY-MM-DD.html`.

Recommended cadence: Monday 06:00 and Thursday 06:00 in Victoria's timezone. Cron form (UTC, assuming ET):
```
0 10 * * 1     # Mondays  06:00 ET
0 10 * * 4     # Thursdays 06:00 ET
```

The task should:
1. Run the standing briefing prompt (already saved).
2. Write the HTML file to the local clone of this repo at `briefings/`.
3. Run `python scripts/generate_index.py` to refresh the landing page.
4. `git add`, `git commit -m "briefing: <date>"`, `git push origin main`.

If Cowork cannot push directly (sandbox network), the alternative is to write the file into the Cowork output folder and let a thin local cron job on Victoria's machine sync that folder into this repo and push.

## Piece 2 · Publishing (GitHub Actions)

`.github/workflows/publish.yml` runs on every push to `main` and does two things:

1. Re runs `scripts/generate_index.py` (idempotent, safe).
2. (Optional) Deploys the repo as a GitHub Pages site so each briefing becomes a private link, e.g. `https://<user>.github.io/corpdev-ai-briefing/briefings/vic_ai_briefing_2026-05-16.html`.

GitHub Pages from a private repo requires GitHub Pro / Team / Enterprise. Confirm Victoria's plan tier before enabling Pages.

## Failure modes worth thinking about now

- **Cowork run produces a file but cannot push.** Mitigation: log the file path in the scheduled task output, and have Victoria pick it up manually for the first few runs until the push path is verified.
- **Briefing source quality drift.** The standing prompt does the cross verification, but a weekly spot check by Victoria is healthy. Treat the first month as supervised.
- **Stale index after manual file additions.** Always run `generate_index.py` before committing. The workflow regenerates anyway, but local diffs are cleaner if it's done first.
