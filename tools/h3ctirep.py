#!/usr/bin/env python3
"""h3ctirep.py <cti.vcd> <Property> [out.txt]

Render a counterexample-to-induction as something a lemma writer can act on.

The previous renderer printed every signal holding a NON-ZERO value, truncated
alphabetically at 60 entries.  For a CTI that is exactly backwards: the model is
full of boolean harness predicates, and the ones that carry information are the
predicates that are FALSE -- those are the facts the unreachable start state
violates.  Sorting alphabetically and cutting at 60 meant we only ever saw
Step0_A* .. Step0_Mc*, i.e. 60 assumptions that held.  Useless.

This prints, per frame: which proof obligations fail, which harness predicates
are false, the word-level architectural state, and what changes between frames.
"""
import sys, re
from collections import OrderedDict

vcd_path = sys.argv[1]
prop     = sys.argv[2] if len(sys.argv) > 2 else "?"
out_path = sys.argv[3] if len(sys.argv) > 3 else None

VAR = re.compile(r"^\$var\s+\S+\s+(\d+)\s+(\S+)\s*(.*?)\s*\$end\s*$")

scope, sym2name, sym2w = [], {}, {}
lines = open(vcd_path, errors="replace").read().split("\n")
i = 0
while i < len(lines):
    l = lines[i].strip()
    if l.startswith("$scope"):
        p = l.split()
        scope.append(p[2] if len(p) > 2 else "?")
    elif l.startswith("$upscope"):
        if scope: scope.pop()
    elif l.startswith("$var"):
        m = VAR.match(l)
        if m:
            w, sym, name = int(m.group(1)), m.group(2), m.group(3)
            if name:
                sym2name[sym] = ".".join(scope[1:] + [name]) if len(scope) > 1 else name
                sym2w[sym] = w
    elif l.startswith("$enddefinitions"):
        break
    i += 1

frames, vals, t = [], {}, None
for l in lines[i:]:
    l = l.rstrip()
    if not l: continue
    if l[0] == "#":
        if t is not None: frames.append((t, dict(vals)))
        t = int(l[1:])
    elif l[0] == "b":
        parts = l[1:].split(" ", 1)
        if len(parts) == 2: vals[parts[1].strip()] = parts[0]
    elif l[0] in "01xzXZ" and len(l) > 1:
        vals[l[1:]] = l[0]
if t is not None: frames.append((t, dict(vals)))

def val(fr, sym):
    return fr.get(sym, "?")

def as_hex(v, w):
    if v in ("?", ""): return "?"
    if any(c in "xzXZ" for c in v): return "0b" + v.rjust(w, "x")
    try: return f"0x{int(v, 2):0{max(1,(w+3)//4)}x}"
    except ValueError: return v

def is_bool(sym): return sym2w.get(sym, 1) == 1

names = {s: n for s, n in sym2name.items()}
o = []
w = o.append

w(f"CTI for {prop}   ({len(frames)} frames)")
w("=" * 78)
w("")
w("A CTI is a state that satisfies every assumed fact but still breaks the")
w("target.  It is NOT a bug -- it is a state the real core can never reach.")
w("The lemma to write is whatever fact rules this state out.")
w("")

# ---- A. proof obligations failing, per frame -------------------------------
w("--- A. Proof obligations FAILING (Step*_ == 0) ---")
for idx, (tm, fr) in enumerate(frames):
    bad = sorted(names[s] for s in names
                 if names[s].startswith("Step") and is_bool(s) and val(fr, s) == "0")
    w(f"  frame {idx}: {len(bad)} failing")
    for b in bad: w(f"      {b}")
w("")

# ---- B. harness predicates false in the final frame ------------------------
final = frames[-1][1] if frames else {}
first = frames[0][1] if frames else {}
w("--- B. Harness predicates FALSE in final frame (candidate lemma material) ---")
falses = sorted(names[s] for s in names
                if is_bool(s) and not names[s].startswith("Step")
                and val(final, s) == "0")
for f_ in falses: w(f"      {f_}")
w(f"  ({len(falses)} false of {sum(1 for s in names if is_bool(s))} boolean signals)")
w("")

# ---- C. word-level architectural state -------------------------------------
w("--- C. Word-level state per frame ---")
words = sorted((names[s], s) for s in names if not is_bool(s))
hdr = f"  {'signal':<44}" + "".join(f"{('f%d' % k):>14}" for k in range(len(frames)))
w(hdr); w("  " + "-" * (44 + 14 * len(frames)))
for n, s in words:
    row = [as_hex(val(fr, s), sym2w[s]) for _, fr in frames]
    if all(r == "?" for r in row): continue
    w(f"  {n:<44}" + "".join(f"{r:>14}" for r in row))
w("")

# ---- D. what changes -------------------------------------------------------
if len(frames) >= 2:
    w("--- D. Signals that CHANGE across the trace ---")
    ch = []
    for s in names:
        row = [val(fr, s) for _, fr in frames]
        if len(set(row)) > 1: ch.append((names[s], row))
    for n, row in sorted(ch):
        w(f"  {n:<44}" + "".join(f"{(r if len(r)<13 else r[:10]+'..'):>14}" for r in row))
    w(f"  ({len(ch)} changing signals)")
    w("")

text = "\n".join(o) + "\n"
if out_path:
    open(out_path, "w").write(text)
    print(f"  report: {out_path} ({len(text)} bytes, {len(frames)} frames, "
          f"{len(falses)} false predicates)")
else:
    sys.stdout.write(text)
