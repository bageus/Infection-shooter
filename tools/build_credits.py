"""Build assets/interface/credits.json (shown in About) from assets/audio/CREDITS.md.

CREDITS.md is excluded from exports (*.md), so attribution-required sources
(everything except CC0) are bundled as JSON. Run: python tools/build_credits.py
"""
import json
from pathlib import Path

root = Path(__file__).resolve().parent.parent
seen = {}
for line in (root / "assets/audio/CREDITS.md").read_text(encoding="utf8").splitlines():
    cells = [c.strip() for c in line.strip().strip("|").split("|")] if line.startswith("|") else []
    if len(cells) != 5 or set(cells[0]) <= set("-") or cells[0] == "Source file":
        continue
    _, author, licence, link, _ = cells
    if licence.upper().replace(" ", "").startswith("CC0"):
        continue
    seen.setdefault((author, licence), link if link.startswith("http") else "")
entries = [[a, l, u] for (a, l), u in sorted(seen.items(), key=lambda x: x[0][0].lower())]
(root / "assets/interface/credits.json").write_text(
    json.dumps({"audio": entries}, ensure_ascii=False, indent=1) + "\n", encoding="utf8")
print(len(entries), "entries")
