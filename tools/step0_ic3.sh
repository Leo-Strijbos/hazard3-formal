#!/bin/bash
# step0_ic3.sh -- re-establish the step-0 (spec-free, gate-1/2/3) lemmas that
# did not re-prove under kind/400s in fix1, using the ORIGINAL method from
# prove1.sh: rIC3 default (IC3) engine, 1800 s, core.aig, no constraints.
# Step-0 lemmas mention nothing spec-side, so a core result is decisive and a
# core proof transfers.  Emits REPROVE lines chain_check3 understands.
set -uo pipefail
cd /opt/verif/h3formal
exec >> /var/tmp/h3loop.log 2>&1
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
NIX="nix develop /opt/verif/ibex#oss-dev --command"
R=results/fix1; PAR=${PAR:-4}
while ! grep -q "core pre-screen done" /var/tmp/h3loop.log; do sleep 30; done
LIST=$(for P in $(grep -a "^CORE .* not-proved-on-core\|^CORE .* refuted-on-core" /var/tmp/h3loop.log | awk '{print $2}' | sort -u); do
  grep -qa "^REPROVE $P RESULT: UNSAT" /var/tmp/h3loop.log && continue
  [ "$(bash /var/tmp/h3step.sh "$P")" = "0" ] && echo "$P"; done)
echo "=== step-0 IC3 pass (prove1.sh method: rIC3 default engine, 1800 s, core.aig, no constraints), $PAR-wide: $(echo $LIST | wc -w) lemmas $(date -u +%H:%M): $(echo $LIST) ==="
ic3_one() {
  local P=$1 F=build/sel/fix1-core-$P.aig rc
  [ -f "$F" ] || $NIX build/aig-manip build/core.aig select "$F" build/core.ywmap 0 "$P" > "$R/$P.core.sel" 2>&1
  /usr/bin/time -f "%e" -o "$R/$P.ic3.t" timeout 1800 $NIX rIC3 "$F" > "$R/$P.ic3.log" 2>&1; rc=$?
  if [ "$rc" = "20" ] || grep -qa "RESULT: UNSAT" "$R/$P.ic3.log"; then
    echo "REPROVE $P RESULT: UNSAT t=$(tail -1 "$R/$P.ic3.t")s step=0 engine=ic3 model=core (spec-free; proof transfers)"
  elif [ "$rc" = "10" ] || grep -qa "RESULT: SAT" "$R/$P.ic3.log"; then
    echo "REPROVE $P REFUTED-IC3 step=0 (spec-free lemma: REAL on the fixed model -- read it)"
  else echo "REPROVE $P IC3-TIMEOUT-OR-ERR rc=$rc step=0"; fi
}
n=0; for P in $LIST; do ic3_one "$P" & n=$((n+1)); [ $((n % PAR)) -eq 0 ] && wait; done; wait
echo "=== step-0 IC3 pass done $(date -u +%H:%M): $(for P in $LIST; do grep -qa "^REPROVE $P RESULT: UNSAT" /var/tmp/h3loop.log && echo x; done | wc -l) of $(echo $LIST | wc -w) proved ==="
echo "STEP0-IC3-DONE"
