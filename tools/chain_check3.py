#!/usr/bin/env python3
"""chain_check3.py <Goal> [--ywmap PATH] [--log PATH] [--proof PATH]

Mechanical chain of custody, per PROOF rather than per property.

A property's proof at log line L used, as constraints, every property at a
lower step that was PRESENT in the proof file at line L.  The proof is VALID
iff every such constraint is (a) still present now and (b) itself validly
proven (recursively; step-0 originals are the base, taken on the proof
header's word).  Properties inserted below it AFTER line L are irrelevant to
that proof (a proof under fewer constraints holds under more).  A constraint
REMOVED after line L makes the proof STALE.

Presence over time comes from the log's `inserted ...: names` and
`removed N: names` lines; anything in the proof with no `inserted` line is an
original, present from line 0.  Ordering "below" uses current steps, which is
sound because inserts always go above every existing lemma and below the
goals, and removals preserve order.
"""
import sys, re, json, argparse
ap = argparse.ArgumentParser()
ap.add_argument("goal"); ap.add_argument("--ywmap", default="build/all.ywmap")
ap.add_argument("--log", default="/var/tmp/h3loop.log"); ap.add_argument("--proof", default="thm/hazard3.proof")
a = ap.parse_args()

step = {}
for x in json.load(open(a.ywmap))["asserts"]:
    m = re.match(r"\$\\top\.Step(\d+)_(.+?)\$", x[0])
    if m: step[m[2]] = int(m[1])
present_now = set(re.findall(r"^\s*([A-Za-z0-9_]+):\s*have", open(a.proof).read(), re.M))

ins, rem, proof = {}, {}, {}          # name -> [line...], name -> [line...], name -> last UNSAT line
axioms = {}                            # name -> first "AXIOM <name> assumed" log line (never proven, by decision)
for n, line in enumerate(open(a.log, errors="replace"), 1):
    m = re.match(r"inserted \d+ candidates at a new layer: (.*)", line)
    if m:
        for p in m[1].split(): ins.setdefault(p, []).append(n)
        continue
    m = re.match(r"AXIOM ([A-Za-z0-9_]+) assumed", line)
    if m: axioms.setdefault(m[1], n); continue
    m = re.match(r"removed \d+: (.*)", line)
    if m:
        for p in m[1].split(): rem.setdefault(p, []).append(n)
        continue
    m = re.match(r"(?:RESULT|REPROVE) ([A-Za-z0-9_]+) RESULT: UNSAT|PROBE ([A-Za-z0-9_]+) kind: RESULT: UNSAT", line)
    if m: proof[m[1] or m[2]] = n

def present_at(p, L):
    """was p in the proof file at log line L?"""
    evs = sorted([(l, "+") for l in ins.get(p, [])] + [(l, "-") for l in rem.get(p, [])])
    state = p not in ins            # originals start present
    for l, e in evs:
        if l >= L: break
        state = (e == "+")
    return state

def ins_line(p): return min(ins[p]) if p in ins else 0
def below_at_proof(q, p, L):
    """was q at a lower step than p when p was proved at line L?
    Both currently present: compare current steps (order is preserved by
    insert/remove).  q since REMOVED (no current step): fall back to insertion
    order -- inserts always land above every existing lemma, so an earlier
    insertion is a lower-or-equal layer; equal is treated as below
    (conservative: a same-batch removal is flagged rather than trusted)."""
    if q in step and p in step: return step[q] < step[p]
    return ins_line(q) < ins_line(p)      # strict: same batch is not 'below'
universe = set(step) | set(ins) | set(rem)

memo = {}
def valid(p, depth=0):
    if p in memo: return memo[p]
    if depth > 200: return ("CYCLE", [])
    memo[p] = ("IN-PROGRESS", [])           # cycle guard: a re-entrant visit reports, not recurses
    s = step.get(p)
    if s == 0: memo[p] = ("base", []); return memo[p]
    L = proof.get(p)
    if L is None and p in axioms and p in present_now: memo[p] = ("axiom", []); return memo[p]
    if L is None: memo[p] = ("MISSING", []); return memo[p]
    if p not in present_now: memo[p] = ("REMOVED", []); return memo[p]
    problems = []
    for q in universe:
        if q == p or not present_at(q, L) or not below_at_proof(q, p, L): continue
        if q not in present_now: problems.append(f"{q} (removed after this proof)"); continue
        st, _ = valid(q, depth + 1)
        if st not in ("base", "ok", "axiom"): problems.append(f"{q}:{st}")
    
    memo[p] = ("ok" if not problems else "STALE", problems); return memo[p]

g = a.goal
print(f"goal {g} step={step.get(g)}  proof line={proof.get(g)}  ywmap={a.ywmap}")
st, probs = valid(g)
gL = proof.get(g, 10**9)
cons = sorted([(step.get(q, -1), q) for q in universe if q != g and present_at(q, gL) and below_at_proof(q, g, gL)])
base = sum(1 for s, q in cons if s == 0)
print(f"constraints at proof time: {len(cons)}  (step-0 originals: {base})")
for s, q in cons:
    if s == 0: continue
    if q not in present_now: print(f"  REMOVED  step {s:<2} {q:<34} was a constraint, removed after the goal's proof"); continue
    vs, vp = valid(q)
    flag = "ok  " if vs in ("ok", "base") else ("AXIOM" if vs == "axiom" else vs)
    print(f"  {flag:8s} step {s:<2} {q:<34} proof@{proof.get(q, '-')}" + (f"  <- {'; '.join(vp[:2])}" if vp else ""))
print(f"goal's own proof: {st}" + (f"  <- {'; '.join(probs[:3])}" if probs else ""))
used_axioms = sorted(q for q in memo if memo[q][0] == "axiom")
if st == "ok" and used_axioms:
    print("VERDICT: PROVEN MODULO AXIOMS [" + " ".join(used_axioms) + "] — every other constraint present and validly proven; the axioms were never attempted (user decision)")
elif st == "ok":
    print("VERDICT: PROVEN on this model — every constraint present and validly proven (no axioms in the chain)")
else:
    print("VERDICT:", f"NOT PROVEN ({st})")
