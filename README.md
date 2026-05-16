# corpdev-ai-briefing

Private archive of Victoria's twice weekly AI and Tech briefings, prepared in Cowork mode.

## Layout

```
corpdev-ai-briefing/
  index.html              Landing page linking to every edition
  briefings/              One HTML file per edition
    vic_ai_briefing_YYYY-MM-DD.html
  scripts/
    generate_index.py     Rebuilds index.html from the briefings/ folder
  .github/workflows/      Reserved for the bi weekly automation (see below)
```

## How a new edition gets added

1. Cowork generates the next briefing as `briefings/vic_ai_briefing_YYYY-MM-DD.html`.
2. Run `python scripts/generate_index.py` to refresh the landing page.
3. Commit and push. The Monday and Thursday cadence is the default.

## Bi weekly automation (next step)

Two cleanly separated pieces:

1. **Generation** runs inside Cowork on a schedule (Mon and Thu mornings) and writes the new HTML file into this folder.
2. **Publishing** is handled by a small GitHub Actions workflow placed in `.github/workflows/publish.yml` that, on each push to `main`, regenerates `index.html` and (optionally) deploys to GitHub Pages.

See `docs/AUTOMATION.md` for the full plan once it's wired up.

## Sharing

Repo is private. If we enable GitHub Pages from this private repo (requires GitHub Pro / Team / Enterprise), the rendered briefings become reachable at a link without exposing the source.

## Caveats

Briefings are AI generated. They cross verify sources, but some quote attributions, dates, and dollar figures are flagged as uncertain inline. Always confirm before forwarding externally.
