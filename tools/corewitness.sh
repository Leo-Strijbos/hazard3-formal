#!/bin/bash
# corewitness.sh <round> <Prop> <depth> -- BMC witness of a DUT-only candidate refuted on core.aig, from its core select file
set -uo pipefail
ROUND=$1; P=$2; DEPTH=$3; cd /opt/verif/h3formal
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX="nix develop /opt/verif/ibex#oss-dev --command"
F=build/sel/$ROUND-core-$P.aig; D=results/icti/$ROUND-core-$P-bmc; mkdir -p "$D"
timeout 900 $NIX rIC3 -e bmc --end $((DEPTH+1)) --witness "$F" 2>"$D/bmc.err" | sed -n '/^1$/,$p' > "$D/cex.aiw"
[ -s "$D/cex.aiw" ] || { echo "COREWITNESS $P none" >> /var/tmp/h3loop.log; exit 1; }
$NIX build/aig-manip build/core.aig simulate build/core.ywmap build/core.vmap "$D/cex.aiw" "$D/cex.vcd" > "$D/sim.log" 2>&1
python3 /opt/verif/ablation/h3ctirep.py "$D/cex.vcd" "$P" "$D/report.txt" > /dev/null 2>&1
echo "COREWITNESS $P frames=$(grep -c '^#' "$D/cex.vcd") -> $D/report.txt" >> /var/tmp/h3loop.log
