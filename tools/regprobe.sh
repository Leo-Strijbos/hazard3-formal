#!/bin/bash
# regprobe.sh <tag> -- PROBE: k-induction on CtiRegMatchV2_01 alone against the CURRENT all.aig (property must be in the ywmap),
# long cap, ICTI in parallel. Emits "PROBE <P> kind: RESULT: UNSAT" (chain_check3 accepts it) -- never a RESULT line, so it is
# safe beside a running round. Usage: bash /var/tmp/regprobe.sh probe1
set -uo pipefail
TAG=${1:?tag}; P=${2:-CtiRegMatchV2_01}; CAP=${3:-1800}
cd /opt/verif/h3formal
exec >> /var/tmp/h3loop.log 2>&1
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX="nix develop /opt/verif/ibex#oss-dev --command"
R=results/$TAG; mkdir -p "$R" build/sel results/icti
S=$(bash /var/tmp/h3step.sh "$P"); [ -n "$S" ] || { echo "PROBE $P NO-STEP (not in all.ywmap)"; exit 1; }
F=build/sel/$TAG-$P.aig
$NIX build/aig-manip build/all.aig select "$F" build/all.ywmap "$S" "$P" > "$R/$P.sel" 2>&1 || { echo "PROBE $P select failed"; exit 1; }
C=$(head -c 80 "$F"|head -1|awk '{print $8}')
echo "=== PROBE $TAG $(date -u +%H:%M): $P alone, step=$S C=$C cap=${CAP}s ==="
( D=results/icti/$TAG-$P; mkdir -p "$D"; python3 /opt/verif/ablation/aigicti.py "$F" "$D/icti.aag" --k 1 > "$D/aigicti.log" 2>&1 && timeout 900 $NIX rIC3 -e bmc --end 2 --witness "$D/icti.aag" 2>"$D/bmc.err" | sed -n '/^1$/,$p' > "$D/icti.aiw.full"; if [ -s "$D/icti.aiw.full" ]; then awk 'NR==3{print substr($0,1,length($0)-1); next}{print}' "$D/icti.aiw.full" > "$D/icti.aiw"; $NIX build/aig-manip build/all.aig simulate build/all.ywmap build/all.vmap "$D/icti.aiw" "$D/icti.vcd" > "$D/sim.log" 2>&1; python3 /opt/verif/ablation/h3ctirep.py "$D/icti.vcd" "$P" "$D/report.txt" > /dev/null 2>&1; rm -f "$D/icti.aag" "$D/icti.aiw.full"; echo "ICTI $P INDUCTION-CTI k=1 -> $D/report.txt (vcd kept)"; else echo "ICTI $P NO-INDUCTION-CTI k=1"; fi ) &
/usr/bin/time -f "%e" -o "$R/$P.t" timeout $CAP $NIX rIC3 -e kind "$F" > "$R/$P.k.log" 2>&1
echo "PROBE $P kind: $(grep -aoE 'RESULT: [A-Z]+' "$R/$P.k.log"|head -1) t=$(tail -1 "$R/$P.t")s C=$C step=$S depth=$(grep -aoE 'kind depth: [0-9]+' "$R/$P.k.log"|tail -1|grep -oE '[0-9]+')"
wait
echo "PROBE-$TAG-DONE $(date -u +%H:%M)"
