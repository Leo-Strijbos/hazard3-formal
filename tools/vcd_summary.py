#!/usr/bin/env python3
"""Compact text summary of an induction-counterexample VCD for a lemma-writing agent.

Prints, for the last N frames, every signal whose value is non-zero in any of
those frames or changes between them, filtered to the interesting hierarchy
(the core, the LSU, the controller, the spec-tracking signals). This keeps a
10k-signal VCD down to a few hundred lines a model can read.

    vcd_summary.py cti.vcd --frames 3 [--grep REGEX] [--max 400]
"""
from __future__ import annotations
import argparse, re, sys
from collections import defaultdict

DEFAULT_GREP = r"(ibex_top_i|u_ibex_core|load_store_unit|controller|id_stage|if_stage|wb_stage|cs_registers|wbexc_|spec_|instr_will_progress|ex_is_|ex_kill|ex_err|has_spec_past|pre_|post_|data_req_o|data_gnt_i|data_rvalid_i|instr_req_o|instr_gnt_i|instr_rvalid_i)"
NOISE = re.compile(r"(\$|_intg|ram_cfg|scramble|alert|crash_dump|_d\b.*_q\b|mem_assume)")


def parse(path: str):
    ids: dict[str, list[str]] = defaultdict(list)
    scope: list[str] = []
    frames: list[dict[str, str]] = []
    cur: dict[str, str] = {}
    with open(path) as f:
        for line in f:
            t = line.split()
            if not t:
                continue
            if t[0] == "$scope":
                scope.append(t[2])
            elif t[0] == "$upscope":
                scope.pop()
            elif t[0] == "$var":
                ids[t[3]].append(".".join(scope + [t[4]]))
            elif t[0].startswith("#"):
                if cur:
                    frames.append(cur)
                cur = dict(frames[-1]) if frames else {}
            elif t[0][0] in "01xzXZ" and len(t) == 1:
                cur[t[0][1:]] = t[0][0]
            elif t[0][0] in "bBrR" and len(t) == 2:
                cur[t[1]] = t[0][1:]
    if cur:
        frames.append(cur)
    return ids, frames


def fmt(v: str) -> str:
    if set(v) <= set("01") and len(v) > 1:
        return hex(int(v, 2))
    return v


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("vcd")
    ap.add_argument("--frames", type=int, default=3)
    ap.add_argument("--grep", default=DEFAULT_GREP)
    ap.add_argument("--max", type=int, default=400)
    a = ap.parse_args()
    ids, frames = parse(a.vcd)
    if not frames:
        print("no frames"); return
    last = frames[-a.frames:]
    pat = re.compile(a.grep)
    rows = []
    for vid, names in ids.items():
        name = min(names, key=len)
        if not pat.search(name) or NOISE.search(name):
            continue
        vals = [fmt(fr.get(vid, "?")) for fr in last]
        nonzero = any(v not in ("0", "0x0", "?") for v in vals)
        changes = len(set(vals)) > 1
        if nonzero or changes:
            rows.append((name, vals, changes))
    rows.sort(key=lambda r: (not r[2], r[0]))
    print(f"# {len(frames)} frames in VCD; showing last {len(last)} (oldest..newest). '*' = changes across frames")
    for name, vals, changes in rows[: a.max]:
        print(f"{'*' if changes else ' '} {name:70s} {' -> '.join(vals)}")
    if len(rows) > a.max:
        print(f"# ... {len(rows) - a.max} more signals omitted (raise --max or narrow --grep)")


if __name__ == "__main__":
    main()
