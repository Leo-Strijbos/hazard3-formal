#!/usr/bin/env python3
"""make_timeline.py <log>... -> markdown table, one row per round, in log order.
Reads the runner's markers: '=== ROUND <r> (', 'RESULT <name> ...', 'REPROVE ...', 'GOAL-CTI', 'ROUND-<r>-DONE'."""
import re, sys
rows = []
for path in sys.argv[1:]:
    era = path.split("/")[-1]
    cur = None
    for l in open(path, errors="replace"):
        m = re.match(r"=== ROUND (\S+) \(", l)
        if m:
            cur = {"era": era, "round": m[1], "start": re.search(r"(\d\d:\d\d)", l), "proved": [], "failed": [], "refuted": [], "goals": [], "goal_cti": [], "done": ""}
            cur["start"] = cur["start"][1] if cur["start"] else ""
            rows.append(cur); continue
        if cur is None: continue
        m = re.match(r"RESULT (\S+) (.*)", l)
        if m:
            n, rest = m[1], m[2]
            if "(GOAL)" in rest and "RESULT: UNSAT" in rest: cur["goals"].append(n)
            elif rest.startswith("RESULT: UNSAT") or "RESULT: UNSAT" in rest: cur["proved"].append(n)
            elif rest.startswith("RESULT: AXIOM"): cur["proved"].append(n + " (axiom)")
            elif "REFUTED" in rest: cur["refuted"].append(n)
            elif "SKIPPED" in rest or rest.strip().startswith("t=") or "NO-STEP" in rest or "SELECT" in rest: cur["failed"].append(n)
            continue
        m = re.match(r"GOAL-CTI (\S+)", l)
        if m: cur["goal_cti"].append(m[1]); continue
        m = re.match(r"ROUND-(\S+)-DONE (\d\d:\d\d)", l)
        if m and m[1] == cur["round"]: cur["done"] = m[2]
def short(xs, k=6):
    xs = sorted(set(xs)); return ", ".join(xs[:k]) + (f" (+{len(xs)-k})" if len(xs) > k else "")
print("| log | round | start | done | proved | not proved | refuted | goals proved | goals with CTI |")
print("|---|---|---|---|---|---|---|---|---|")
for r in rows:
    print(f"| {r['era']} | {r['round']} | {r['start']} | {r['done']} | {short(r['proved'])} | {short(r['failed'])} | {short(r['refuted'])} | {short(r['goals'])} | {short(r['goal_cti'])} |")
