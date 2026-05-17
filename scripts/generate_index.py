#!/usr/bin/env python3
"""
Rebuild index.html from the briefings/ folder.

Looks for files matching briefings/vic_ai_briefing_YYYY-MM-DD.html,
sorts them newest first, and writes a landing page that lists each
edition (date, weekday, link) plus a keyword-search bar that filters
cards by substring match against the briefing text.
"""

from __future__ import annotations

import html
import json
import re
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
BRIEFINGS_DIR = REPO_ROOT / "briefings"
INDEX_PATH = REPO_ROOT / "index.html"

FILE_RE = re.compile(r"vic_ai_briefing_(\d{4})-(\d{2})-(\d{2})\.html$")

# Cap embedded plain text per briefing so index.html stays bounded as
# the archive grows.
MAX_TEXT_CHARS = 20000


def find_briefings() -> list[tuple[datetime, Path]]:
    items: list[tuple[datetime, Path]] = []
    for p in BRIEFINGS_DIR.glob("vic_ai_briefing_*.html"):
        m = FILE_RE.search(p.name)
        if not m:
            continue
        d = datetime(int(m.group(1)), int(m.group(2)), int(m.group(3)))
        items.append((d, p))
    items.sort(key=lambda t: t[0], reverse=True)
    return items


def extract_text(source: str) -> str:
    s = re.sub(r"<script\b[^>]*>.*?</script>", " ", source, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<style\b[^>]*>.*?</style>", " ", s, flags=re.DOTALL | re.IGNORECASE)
    s = re.sub(r"<!--.*?-->", " ", s, flags=re.DOTALL)
    s = re.sub(r"<[^>]+>", " ", s)
    s = html.unescape(s)
    s = re.sub(r"\s+", " ", s).strip()
    return s[:MAX_TEXT_CHARS]


def render(items: list[tuple[datetime, Path]]) -> str:
    records: list[dict] = []
    cards: list[str] = []
    for idx, (d, p) in enumerate(items):
        href = f"briefings/{p.name}"
        weekday = d.strftime("%A")
        nice = d.strftime("%b %d %Y")
        edition = "Thursday edition" if d.weekday() == 3 else (
            "Monday edition" if d.weekday() == 0 else f"{weekday} edition"
        )
        text = extract_text(p.read_text(encoding="utf-8"))
        records.append({
            "file": p.name,
            "href": href,
            "date": nice,
            "edition": edition,
            "text": text,
        })
        cards.append(
            f"""    <a class="card" href="{href}" data-idx="{idx}">
      <div class="row">
        <span class="date">{nice}</span>
        <span class="badge">{edition}</span>
      </div>
      <div class="filename">{p.name}</div>
      <div class="snippet" data-idx="{idx}"></div>
    </a>"""
        )

    cards_html = "\n".join(cards) if cards else (
        '    <div class="empty">No briefings yet. Drop the first one into <code>briefings/</code>.</div>'
    )

    # Guard against an accidental </script> inside record text closing
    # the embedding <script> early.
    briefings_json = json.dumps(records, ensure_ascii=False).replace("</", "<\\/")

    updated = datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC")
    count = len(items)

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8" />
<meta name="viewport" content="width=device-width, initial-scale=1.0" />
<title>Victoria's AI &amp; Tech Briefings</title>
<link rel="preconnect" href="https://fonts.googleapis.com" />
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin />
<link href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700;800&amp;family=JetBrains+Mono:wght@500&amp;display=swap" rel="stylesheet" />
<style>
  :root {{
    --bg: #0d0d0f;
    --surface: #17171a;
    --surface-2: #1f1f24;
    --border: #2a2a30;
    --text: #ececf1;
    --muted: #8a8a96;
    --purple: #7c6df5;
    --blue: #4fc3f7;
  }}
  * {{ box-sizing: border-box; }}
  html, body {{
    margin: 0; padding: 0;
    background: var(--bg); color: var(--text);
    font-family: 'Inter', system-ui, sans-serif;
    line-height: 1.55; font-size: 15px;
  }}
  .wrap {{ max-width: 780px; margin: 0 auto; padding: 40px 22px 80px; }}
  .hero {{
    border: 1px solid var(--border);
    background: linear-gradient(140deg, rgba(124, 109, 245, 0.12), rgba(79, 195, 247, 0.06) 60%, transparent);
    border-radius: 16px; padding: 28px;
  }}
  .eyebrow {{
    display: inline-flex; align-items: center; gap: 8px;
    font-size: 12px; text-transform: uppercase; letter-spacing: 0.12em;
    color: var(--muted); font-weight: 600;
  }}
  .eyebrow .dot {{ width: 8px; height: 8px; border-radius: 50%; background: var(--purple); box-shadow: 0 0 12px var(--purple); }}
  h1 {{ font-size: 30px; font-weight: 800; margin: 10px 0 4px; letter-spacing: -0.02em; }}
  .subtitle {{ color: var(--muted); font-size: 14px; margin: 0; }}
  .meta {{ margin-top: 14px; display: flex; gap: 8px; flex-wrap: wrap; }}
  .pill {{
    background: var(--surface-2); border: 1px solid var(--border);
    font-size: 12px; padding: 6px 11px; border-radius: 999px; font-weight: 500;
  }}
  .pill strong {{ color: var(--purple); font-weight: 700; }}
  h2 {{
    font-size: 13px; text-transform: uppercase; letter-spacing: 0.14em;
    color: var(--muted); font-weight: 700;
    margin: 36px 0 14px; padding-bottom: 8px; border-bottom: 1px solid var(--border);
  }}
  .search {{ position: relative; margin: 22px 0 10px; }}
  .search input {{
    width: 100%;
    background: var(--surface);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 12px 92px 12px 42px;
    color: var(--text);
    font-family: inherit;
    font-size: 14.5px;
    transition: border-color 0.18s, background 0.18s;
    outline: none;
  }}
  .search input::placeholder {{ color: var(--muted); }}
  .search input:focus {{ border-color: var(--purple); background: var(--surface-2); }}
  .search .icon {{
    position: absolute; left: 14px; top: 50%; transform: translateY(-50%);
    color: var(--muted); font-size: 16px; pointer-events: none;
  }}
  .search .kbd {{
    position: absolute; right: 12px; top: 50%; transform: translateY(-50%);
    font-family: 'JetBrains Mono', monospace; font-size: 11px;
    color: var(--muted);
    background: var(--surface-2);
    border: 1px solid var(--border);
    border-radius: 6px;
    padding: 2px 8px;
    pointer-events: none;
  }}
  .search input:focus ~ .kbd {{ opacity: 0; }}
  .status {{
    color: var(--muted); font-size: 12px; margin: 0 4px 14px;
    font-family: 'JetBrains Mono', monospace;
    letter-spacing: 0.02em;
    min-height: 16px;
  }}
  .list {{ display: flex; flex-direction: column; gap: 10px; }}
  .card {{
    display: block; text-decoration: none; color: var(--text);
    border: 1px solid var(--border); background: var(--surface);
    border-radius: 12px; padding: 16px 18px;
    transition: border-color 0.18s ease, transform 0.18s ease;
  }}
  .card:hover {{ border-color: var(--purple); }}
  .card.hidden {{ display: none; }}
  .row {{ display: flex; align-items: center; gap: 12px; }}
  .date {{ font-size: 16px; font-weight: 700; letter-spacing: -0.01em; }}
  .badge {{
    margin-left: auto;
    font-size: 11px; padding: 3px 8px; border-radius: 6px;
    background: rgba(124, 109, 245, 0.15); color: #b4a7ff;
    border: 1px solid rgba(124, 109, 245, 0.35);
    font-weight: 600; text-transform: uppercase; letter-spacing: 0.04em;
  }}
  .filename {{
    color: var(--muted); font-size: 12px; margin-top: 6px;
    font-family: 'JetBrains Mono', monospace;
  }}
  .snippet {{
    color: #c8c8d2; font-size: 13px; margin-top: 10px;
    line-height: 1.55;
    padding-top: 10px;
    border-top: 1px dashed var(--border);
  }}
  .snippet:empty {{ display: none; }}
  mark {{
    background: rgba(124, 109, 245, 0.32);
    color: #ffffff;
    padding: 0 2px;
    border-radius: 3px;
  }}
  .empty {{
    color: var(--muted); font-size: 14px; padding: 24px;
    border: 1px dashed var(--border); border-radius: 12px; text-align: center;
  }}
  .empty code {{ color: var(--blue); background: var(--surface-2); padding: 1px 6px; border-radius: 4px; }}
  footer {{ margin-top: 50px; padding-top: 22px; border-top: 1px solid var(--border); color: var(--muted); font-size: 12px; text-align: center; }}
</style>
</head>
<body>
<div class="wrap">

  <header class="hero">
    <div class="eyebrow"><span class="dot"></span>Archive</div>
    <h1>Victoria's AI &amp; Tech Briefings</h1>
    <p class="subtitle">Twice weekly AI and tech briefings, prepared in Cowork mode.</p>
    <div class="meta">
      <span class="pill"><strong>{count}</strong> editions</span>
      <span class="pill">Updated {updated}</span>
    </div>
  </header>

  <h2>All Editions</h2>

  <div class="search">
    <span class="icon">&#9906;</span>
    <input id="q" type="search" autocomplete="off" spellcheck="false"
           placeholder="Search keywords across all briefings…" aria-label="Search briefings" />
    <span class="kbd">/</span>
  </div>
  <div class="status" id="status"></div>

  <div class="list" id="list">
{cards_html}
  </div>

  <footer>
    Private archive · sorted newest first · generated by <code>scripts/generate_index.py</code>
  </footer>

</div>

<script>
const BRIEFINGS = {briefings_json};
const input = document.getElementById('q');
const statusEl = document.getElementById('status');
const cards = Array.from(document.querySelectorAll('.card'));
const snippets = cards.map(c => c.querySelector('.snippet'));

function escapeHtml(s) {{
  return s.replace(/[&<>"']/g, c => ({{
    '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
  }}[c]));
}}

function buildSnippet(text, query) {{
  const ql = query.toLowerCase();
  const tl = text.toLowerCase();
  const i = tl.indexOf(ql);
  if (i < 0) return '';
  const radius = 70;
  const start = Math.max(0, i - radius);
  const end = Math.min(text.length, i + query.length + radius);
  const slice = text.slice(start, end);
  const sliceLower = slice.toLowerCase();
  let out = '';
  let pos = 0;
  while (pos < slice.length) {{
    const j = sliceLower.indexOf(ql, pos);
    if (j < 0) {{ out += escapeHtml(slice.slice(pos)); break; }}
    out += escapeHtml(slice.slice(pos, j));
    out += '<mark>' + escapeHtml(slice.slice(j, j + query.length)) + '</mark>';
    pos = j + query.length;
  }}
  if (start > 0) out = '… ' + out;
  if (end < text.length) out = out + ' …';
  return out;
}}

function pluralize(n) {{ return n === 1 ? '' : 's'; }}

function filter() {{
  const q = input.value.trim();
  if (!q) {{
    cards.forEach((card, i) => {{
      card.classList.remove('hidden');
      snippets[i].innerHTML = '';
    }});
    statusEl.textContent = BRIEFINGS.length === 0
      ? 'No editions yet.'
      : `Showing all ${{BRIEFINGS.length}} edition${{pluralize(BRIEFINGS.length)}}.`;
    return;
  }}
  const ql = q.toLowerCase();
  let shown = 0;
  cards.forEach((card, i) => {{
    const rec = BRIEFINGS[i];
    const text = rec ? rec.text : '';
    if (text.toLowerCase().includes(ql)) {{
      card.classList.remove('hidden');
      snippets[i].innerHTML = buildSnippet(text, q);
      shown++;
    }} else {{
      card.classList.add('hidden');
      snippets[i].innerHTML = '';
    }}
  }});
  statusEl.textContent = shown === 0
    ? `No matches for "${{q}}".`
    : `Found in ${{shown}} of ${{BRIEFINGS.length}} edition${{pluralize(BRIEFINGS.length)}}.`;
}}

input.addEventListener('input', filter);

document.addEventListener('keydown', e => {{
  if (e.key === '/' && document.activeElement !== input) {{
    e.preventDefault();
    input.focus();
    input.select();
  }} else if (e.key === 'Escape' && document.activeElement === input) {{
    if (input.value) {{
      input.value = '';
      filter();
    }} else {{
      input.blur();
    }}
  }}
}});

filter();
</script>

</body>
</html>
"""


def main() -> None:
    BRIEFINGS_DIR.mkdir(exist_ok=True)
    items = find_briefings()
    INDEX_PATH.write_text(render(items), encoding="utf-8")
    print(f"Wrote {INDEX_PATH} with {len(items)} edition(s).")


if __name__ == "__main__":
    main()
