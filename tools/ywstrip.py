#!/usr/bin/env python3
"""ywstrip.py <ywmap> <Prop>...  -- retire properties from a ywmap IN PLACE by
renaming their assert entries Step<N>_<Prop> -> Step9999_<Prop>.  aig-manip
select then never treats them as constraints (their step exceeds every target)
and deletes them from every selection, exactly as a rebuild without them would.
The AIG is untouched; the 1:1 assert<->output mapping is preserved.  The next
round's real `make` regenerates the map from the edited proof file."""
import json, re, sys
path, props = sys.argv[1], set(sys.argv[2:])
d = json.load(open(path))
hit = []
for a in d["asserts"]:
    m = re.match(r"^(\$\\top\.Step)(\d+)_(.+?)(\$.*)$", a[0])
    if m and m[3] in props and m[2] != "9999":
        a[0] = f"{m[1]}9999_{m[3]}{m[4]}"; hit.append(m[3])
json.dump(d, open(path, "w"))
missing = props - set(hit)
print(f"retired {len(hit)}: {' '.join(sorted(hit))}" + (f"  MISSING: {' '.join(sorted(missing))}" if missing else ""))
sys.exit(1 if missing else 0)
