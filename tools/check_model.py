#!/usr/bin/env python3
"""check_model.py <model> [proof-file ...] -- refuse to use a model that has
drifted from the proof text it claims to represent.

`build/all.aig` carried 110 bad states while thm/hazard3.proof listed 91
properties.  Nothing noticed, so a sweep silently checked a different set of
obligations than the one it reported against -- and properties absent from the
model came back looking like counterexamples.

Exit 0 = model matches the proof text.  Exit 4 = drift.
"""
import json, re, sys, subprocess
from pathlib import Path

HAVE  = re.compile(r"^\s*([A-Za-z0-9_]+):\s*have\s*\(")
GRAPH = re.compile(r"^\s*([A-Za-z0-9_]+):\s*graph_induction\b")

def proof_names(files):
    names = set()
    for f in files:
        for line in Path(f).read_text().split("\n"):
            m = HAVE.match(line) or GRAPH.match(line)
            if m:
                names.add(m[1])
    return names

def model_names(ywmap):
    d = json.load(open(ywmap))
    out = set()
    for a in d["asserts"]:
        m = re.match(r"\$\\top\.Step(\d+)_(.+?)\$", a[0])
        if m:
            out.add(m[2])
    return out

def aig_bads(aig):
    with open(aig, "rb") as f:
        h = f.readline().split()
    return int(h[6]) if len(h) > 6 else 0

def main():
    if len(sys.argv) < 2:
        sys.exit("usage: check_model.py <model> [proof files...]")
    model = sys.argv[1]
    proofs = sys.argv[2:] or sorted(str(p) for p in Path("thm").glob("*.proof"))
    aig, yw = f"build/{model}.aig", f"build/{model}.ywmap"
    for f in (aig, yw):
        if not Path(f).exists():
            sys.exit(f"check_model: missing {f}")

    mnames, pnames = model_names(yw), proof_names(proofs)
    bads = aig_bads(aig)
    nasserts = len(json.load(open(yw))["asserts"])

    print(f"check_model: {model}")
    print(f"  proof text : {len(pnames)} properties in {' '.join(proofs)}")
    print(f"  model      : {nasserts} asserts, {bads} bad states in {aig}")

    problems = []
    if bads != nasserts:
        problems.append(f"bad-state count {bads} != assert count {nasserts} (aig and ywmap disagree)")
    # generated names (covers, graph expansions) legitimately appear only in the model
    missing = {n for n in pnames if n not in mnames and
               not any(m.startswith(n + "_") for m in mnames)}
    if missing:
        problems.append(f"{len(missing)} propert{'y' if len(missing)==1 else 'ies'} in the proof text but NOT in the model: "
                        + " ".join(sorted(missing)[:10]) + (" ..." if len(missing) > 10 else ""))
    stale = {m for m in mnames if not m.endswith("_Cover") and m not in pnames and
             not any(m.startswith(p + "_") for p in pnames)}
    if stale:
        problems.append(f"{len(stale)} propert{'y' if len(stale)==1 else 'ies'} in the model but NOT in the proof text (stale build): "
                        + " ".join(sorted(stale)[:10]) + (" ..." if len(stale) > 10 else ""))

    if problems:
        print("  VERDICT: DRIFT -- this model does not represent the current proof text")
        for p in problems:
            print(f"    - {p}")
        print("  Rebuild before using this model, or results will not mean what they say.")
        sys.exit(4)
    print("  VERDICT: OK -- model matches the proof text")

if __name__ == "__main__":
    main()
