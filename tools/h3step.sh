#!/bin/bash
# h3step.sh <Property> -- print the step a property lives at, and NOTHING else.
# `nix develop --command` writes its shell banner to STDOUT, so any command
# substitution that captures its output gets the banner too. This has now
# cost three separate bugs (witness extraction, trace rendering, step lookup).
# Reading the ywmap directly with the system python avoids nix entirely.
cd /opt/verif/h3formal
python3 - "$1" <<'PY'
import json, re, sys
want = sys.argv[1]
for x in json.load(open("build/all.ywmap"))["asserts"]:
    m = re.match(r"\$\\top\.Step(\d+)_(.+?)\$", x[0])
    if m and m[2] == want:
        print(m[1]); break
PY
