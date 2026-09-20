#!/bin/bash
# coreicti.sh <round> <Prop> -- k=1 induction CTI of a DUT-only candidate on core.aig from its existing core select file
set -uo pipefail
ROUND=$1; P=$2; cd /opt/verif/h3formal
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX="nix develop /opt/verif/ibex#oss-dev --command"
F=build/sel/$ROUND-core-$P.aig; D=results/icti/$ROUND-core-$P; mkdir -p "$D"
python3 /opt/verif/ablation/aigicti.py "$F" "$D/icti.aag" --k 1 > "$D/aigicti.log" 2>&1 || { echo "COREICTI $P aigicti failed" >> /var/tmp/h3loop.log; exit 1; }
timeout 900 $NIX rIC3 -e bmc --end 2 --witness "$D/icti.aag" 2>"$D/bmc.err" | sed -n '/^1$/,$p' > "$D/icti.aiw.full"
[ -s "$D/icti.aiw.full" ] || { echo "COREICTI $P NO-INDUCTION-CTI k=1" >> /var/tmp/h3loop.log; exit 0; }
awk 'NR==3{print substr($0,1,length($0)-1); next}{print}' "$D/icti.aiw.full" > "$D/icti.aiw"
$NIX build/aig-manip build/core.aig simulate build/core.ywmap build/core.vmap "$D/icti.aiw" "$D/icti.vcd" > "$D/sim.log" 2>&1
python3 /opt/verif/ablation/h3ctirep.py "$D/icti.vcd" "$P" "$D/report.txt" > /dev/null 2>&1
echo "COREICTI $P INDUCTION-CTI k=1 frames=$(grep -c '^#' "$D/icti.vcd") -> $D/report.txt" >> /var/tmp/h3loop.log
rm -f "$D/icti.aag" "$D/icti.aiw.full"
