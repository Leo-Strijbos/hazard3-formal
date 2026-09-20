#!/usr/bin/env python3
"""Flatten multi-element ywmap paths to the single-element form aig-manip expects.

yosys' write_aiger ywmap records a signal's hierarchical path as a JSON array.
The monolithic build (build_h3.ys) has slang elaborate the Sail model straight
into `top`, so every path is a singleton and aig-manip's

    pub struct YWWire { pub input: usize, pub offset: usize, pub path: [String; 1] }

deserialises it.  The split build (build_h3_fast.ys) reads the cached
build/spec.il as its own module and `flatten`s it, which makes yosys emit
two-element paths such as ["\\spec_api_i", "\\regs_i"] -- and serde then fails
the whole file with a misleading "trailing characters" error.

Joining the elements with "." reproduces exactly the name the monolithic build
produces, so this is a format fixup, not a semantic change.
"""
import json, sys

path = sys.argv[1]
d = json.load(open(path))
n = 0
for key in ("inputs", "seqs", "inits"):
    for w in d.get(key, []):
        p = w.get("path")
        if isinstance(p, list) and len(p) > 1:
            w["path"] = [".".join(s.lstrip("\\") if i else s for i, s in enumerate(p))]
            n += 1
for key in ("asserts", "assumes"):
    lst = d.get(key, [])
    for i, p in enumerate(lst):
        if isinstance(p, list) and len(p) > 1:
            lst[i] = [".".join(s.lstrip("\\") if j else s for j, s in enumerate(p))]
            n += 1
if n:
    json.dump(d, open(path, "w"))
print(f"fix_ywmap: {path}: joined {n} multi-element paths")
