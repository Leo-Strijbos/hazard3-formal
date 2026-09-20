#!/usr/bin/env python3
"""h3insert.py <candidates.txt> | --remove <Name>...

Insert a batch of candidate lemmas at ONE new layer directly above the last
proven layer, or remove named entries. Candidates in a batch are independent,
so they share a rung; only a lemma that depends on another needs its own.
"""
import sys, re
from pathlib import Path
P = Path("thm/hazard3.proof")

def remove(names):
    t = P.read_text().split("\n")
    keep, dropped = [], []
    for line in t:
        m = re.match(r"\s*([A-Za-z0-9_]+):\s*have\s*\(", line)
        if m and m[1] in names:
            dropped.append(m[1]); continue
        keep.append(line)
    P.write_text("\n".join(keep))
    print(f"removed {len(dropped)}: {' '.join(dropped)}")

def insert(path):
    body = Path(path).read_text().rstrip()
    names = re.findall(r"^([A-Za-z0-9_]+):", body, re.M)
    t = P.read_text()
    anchor = "# GATE 5 GOALS"
    if anchor not in t:
        sys.exit("GATE 5 GOALS anchor missing")
    block = "  # --- batch layer ---\n" + "\n".join(
        f"  {l}" if not l.startswith("  ") else l for l in body.split("\n")) + "\n  /\n\n"
    P.write_text(t.replace(anchor, block + anchor, 1))
    print(f"inserted {len(names)} candidates at a new layer: {' '.join(names)}")

if len(sys.argv) > 1 and sys.argv[1] == "--remove":
    remove(set(sys.argv[2:]))
elif len(sys.argv) > 1:
    insert(sys.argv[1])
else:
    sys.exit(__doc__)
