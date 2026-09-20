#!/usr/bin/env python3
"""Readable CTI summary: DESIGN signals only, not assertion outputs."""
import sys, re
vcd, out = sys.argv[1], sys.argv[2]
scope, sym = [], {}
lines = open(vcd).read().split("\n"); i = 0
while i < len(lines):
    l = lines[i].strip()
    if l.startswith("$scope"): scope.append(l.split()[2])
    elif l.startswith("$upscope"): scope.pop()
    elif l.startswith("$var"):
        q = l.split(); sym[q[3]] = ".".join(scope + [q[4]])
    elif l.startswith("$enddefinitions"): break
    i += 1
frames, vals, t = [], {}, None
for l in lines[i:]:
    l = l.strip()
    if l.startswith("#"):
        if t is not None: frames.append(dict(vals))
        t = int(l[1:])
    elif l.startswith("b"):
        v, s = l[1:].split(" ", 1); vals[s] = v
    elif l and l[0] in "01xz" and len(l) > 1: vals[l[1:]] = l[0]
if t is not None: frames.append(dict(vals))
SKIP = re.compile(r"^(Step\d+_|\$|top\.\$)")
with open(out, "w") as f:
    f.write(f"CTI: {len(frames)} frames. Design signals that differ or are non-zero:\n\n")
    if frames:
        last = frames[-1]
        rows = []
        for s, v in last.items():
            n = sym.get(s, s); short = n.split(".")[-1]
            if SKIP.match(short) or SKIP.match(n): continue
            if v in ("0", "") or set(v) == {"0"}: continue
            rows.append((short, v))
        for n, v in sorted(rows)[:50]:
            f.write(f"  {n:<40} {v}\n")
        f.write(f"\n({len(rows)} design signals non-zero; assertion outputs excluded)\n")
