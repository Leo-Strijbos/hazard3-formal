#!/usr/bin/env python3
"""aigicti.py in.aig out.aag [--k 1]  -- a REAL counterexample-to-induction.

aigcti.py frees every latch and runs plain BMC. The shortest violation is then
a single state that satisfies the constraints and breaks P: a counterexample
to IMPLICATION, not to INDUCTION. It never has to show a frame where P HELD
and then broke, so any lemma with a registered "excuse" flag is satisfied by
that flag being a free latch set to 1. Every depth-0 CTI we read today had
exactly that shape (registers not advancing between the two frames).

A k-induction counterexample is: P holds for k consecutive frames, then fails.
Build that into the model:
    held_1 <= !bad          (reset 0 -- NOT free, or depth 0 would fire again)
    held_i <= held_{i-1}    for i = 2..k
    bad'    = held_k & bad
Then a BMC witness at depth k is a state that satisfied P for k frames and then
broke it. Emitted as ASCII aag (explicit variable numbers, no renumbering);
rIC3 reads .aag directly.

The witness has k extra latch bits at the END of its state line; strip them
before `aig-manip simulate` against the parent .aig (see h3icti.sh).
"""
import sys, argparse

def varint(buf, pos):
    x, sh = 0, 0
    while True:
        b = buf[pos]; pos += 1
        x |= (b & 0x7f) << sh
        if not (b & 0x80): return x, pos
        sh += 7

def read_aig(path):
    f = open(path, "rb")
    hdr = f.readline().split()
    if hdr[0] != b"aig": sys.exit(f"{path}: not binary AIGER")
    n = [int(x) for x in hdr[1:]]
    M, I, L, O, A = n[:5]; B = n[5] if len(n) > 5 else 0; C = n[6] if len(n) > 6 else 0
    latches = [f.readline().split() for _ in range(L)]
    outs = [int(f.readline()) for _ in range(O)]
    bads = [int(f.readline()) for _ in range(B)]
    cons = [int(f.readline()) for _ in range(C)]
    buf = f.read(); pos = 0
    ands = []
    for i in range(A):
        lhs = 2 * (I + L + 1 + i)
        d0, pos = varint(buf, pos); d1, pos = varint(buf, pos)
        r0 = lhs - d0; r1 = r0 - d1
        ands.append((lhs, r0, r1))
    rest = buf[pos:]
    return M, I, L, O, A, B, C, latches, outs, bads, cons, ands, rest

def main():
    p = argparse.ArgumentParser()
    p.add_argument("inp"); p.add_argument("outp")
    p.add_argument("--k", type=int, default=1, help="frames P must hold before breaking (default 1)")
    a = p.parse_args()
    M, I, L, O, A, B, C, latches, outs, bads, cons, ands, rest = read_aig(a.inp)
    if B != 1: sys.exit(f"expected exactly 1 bad (a selection), got {B}")
    bad = bads[0]; k = a.k
    out = []
    # new vars: held_1..held_k at M+1..M+k ; the AND at M+k+1
    held = [2 * (M + 1 + i) for i in range(k)]
    gate = 2 * (M + k + 1)
    Mn, Ln, An = M + k + 1, L + k, A + 1
    out.append(f"aag {Mn} {I} {Ln} {O} {An} 1 {C}")
    for i in range(I): out.append(str(2 * (1 + i)))
    for i, row in enumerate(latches):               # original latches: FREE
        lit = 2 * (I + 1 + i); out.append(f"{lit} {int(row[0])} {lit}")
    out.append(f"{held[0]} {bad ^ 1} 0")            # held_1 <= !bad, reset 0
    for i in range(1, k):
        out.append(f"{held[i]} {held[i-1]} 0")      # held_i <= held_{i-1}, reset 0
    for x in outs: out.append(str(x))
    out.append(str(gate))                           # the ONLY bad
    for x in cons: out.append(str(x))
    for lhs, r0, r1 in ands: out.append(f"{lhs} {r0} {r1}")
    out.append(f"{gate} {held[k-1]} {bad}")         # bad' = held_k & bad
    text = "\n".join(out) + "\n"
    try:
        tail = rest.decode()
        if tail and tail[0] in "ilobc": text += tail   # symbol table / comments carry over
    except UnicodeDecodeError:
        pass
    open(a.outp, "w").write(text)
    print(f"  {a.inp} -> {a.outp}  (k={k})")
    print(f"    latches freed : {L}/{L}   +{k} induction latch(es) reset 0")
    print(f"    bad {bad} -> held&bad = {gate};  constraints={C} (unchanged)")

if __name__ == "__main__":
    main()
