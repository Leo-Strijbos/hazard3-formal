#!/bin/bash
# reprove_all2.sh <tag> -- MODEL CHANGE protocol, second edition (fix2: mtvec vectored addition).
# Waits for round 38, rotates the log, rebuilds core.aig/all.aig from the re-patched RTL, re-logs the
# axiom, re-proves EVERY lemma below the goal layer (step 0: core kind screen then IC3 1800 s on core,
# never all.aig; others: core pre-screen then all.aig kind), strips NOTHING, then sweeps all goals
# CTI-first and prints CHAIN verdicts.  Chain of custody then rests on the new log alone.
set -uo pipefail
TAG=${1:?tag}; ROUND=$TAG
cd /opt/verif/h3formal
while ! grep -q "ROUND-round38-DONE" /var/tmp/h3loop.log; do sleep 30; done
mv /var/tmp/h3loop.log "/var/tmp/h3loop.log.pre-$TAG"
exec >> /var/tmp/h3loop.log 2>&1
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
export H3_CONFORMANCE=1
NIX="nix develop /opt/verif/ibex#oss-dev --command"
R=results/$ROUND; mkdir -p "$R" build/sel results/icti
KIND_CAP=${KIND_CAP:-600}; GOAL_KIND_CAP=${GOAL_KIND_CAP:-600}; IC3_CAP=${IC3_CAP:-1800}; IC3_PAR=${IC3_PAR:-8}; MEM_PER=20
MAXJOBS=${MAXJOBS:-$(( $(free -g | awk '/Mem:/{print $2}') / MEM_PER ))}
echo "=== MODEL CHANGE $TAG $(date -u '+%F %H:%M'): RTL conformance patch #6 (mtvec vectored entry: base + offset, FINDING_MTVEC_VECTORED_OR.md; user decision 2026-09-20). Old log: /var/tmp/h3loop.log.pre-$TAG. Every lemma re-proved below; nothing stripped. maxjobs=$MAXJOBS ==="
echo "AXIOM CtiWbMulDiv assumed (never attempted, never stripped; user decision 2026-09-19 'the Oxford way'; re-logged after model change $TAG)"
echo "REPROVE CtiWbMulDiv RESULT: AXIOM"
cp thm/hazard3.proof "$R/proof.before"; cp thm/hazard3.proof "/var/tmp/hazard3.proof.pre-$TAG"

rm -rf build/hazard3-rtl; rm -f build/core.aig build/all.aig build/core.ywmap build/all.ywmap
$NIX make build/core.aig > "$R/build-core.log" 2>&1
echo "core build rc=$?  $(head -c 80 build/core.aig | head -1)"
echo "PATCH_MANIFEST: $(grep -c CONFORMANCE build/hazard3-rtl/PATCH_MANIFEST) conformance patches: $(grep CONFORMANCE build/hazard3-rtl/PATCH_MANIFEST | sed 's/CONFORMANCE: //' | cut -d'(' -f1 | tr '\n' ';')"
grep -q "mtvec + {26'h0, vector_sel, 2'h0}" build/hazard3-rtl/hazard3_csr.v && echo "RTL: mtvec addition present in build/hazard3-rtl/hazard3_csr.v" || echo "WARNING: mtvec addition NOT found in patched RTL"
grep -aiE "error:" "$R/build-core.log" | head -3
( $NIX make build/all.aig > "$R/build.log" 2>&1; echo "build rc=$?  $(head -c 80 build/all.aig | head -1)"; grep -aiE "error:" "$R/build.log" | head -3; touch "$R/.allbuilt" ) &
BUILDPID=$!

# lemma inventory from core.ywmap: goals = the layer holding WrapMepc; lemmas = every step below it
GOALSTEP=$(python3 - <<'PY'
import json,re
for x in json.load(open("build/core.ywmap"))["asserts"]:
    m=re.match(r"\$\\top\.Step(\d+)_(.+?)\$",x[0])
    if m and m[2]=="WrapMepc": print(m[1]); break
PY
)
python3 - "$GOALSTEP" <<'PY' > "$R/inventory.txt"
import json,re,sys
g=int(sys.argv[1]); rows=[]
for x in json.load(open("build/core.ywmap"))["asserts"]:
    m=re.match(r"\$\\top\.Step(\d+)_(.+?)\$",x[0])
    if m: rows.append((int(m[1]),m[2]))
for s,n in sorted(rows): print(s,n)
PY
STEP0=$(awk '$1==0{print $2}' "$R/inventory.txt")
OTHERS=$(awk -v g="$GOALSTEP" '$1>0 && $1<g && $2!="CtiWbMulDiv"{print $2}' "$R/inventory.txt")
GOALS=$(awk -v g="$GOALSTEP" '$1==g{print $2}' "$R/inventory.txt")
ABOVE=$(awk -v g="$GOALSTEP" '$1>g{print $2}' "$R/inventory.txt")
echo "=== inventory: goal step=$GOALSTEP; step-0 lemmas: $(echo $STEP0|wc -w); higher lemmas: $(echo $OTHERS|wc -w) (+ axiom CtiWbMulDiv); goals: $(echo $GOALS|wc -w); above goals (not re-proved): $(echo $ABOVE) ==="

stepof() { awk -v p="$1" '$2==p{print $1; exit}' "$R/inventory.txt"; }
core_one() {
  local P=$1 S F c; S=$(stepof "$P"); [ -n "$S" ] || { echo "CORE $P not-in-core-ywmap"; return; }
  F=build/sel/$ROUND-core-$P.aig
  $NIX build/aig-manip build/core.aig select "$F" build/core.ywmap "$S" "$P" > "$R/$P.core.sel" 2>&1 || { echo "CORE $P select-refused"; return; }
  [ "$(head -c 80 "$F"|head -1|awk '{print $7}')" = "1" ] || { echo "CORE $P bad-selection"; return; }
  c=$(head -c 80 "$F"|head -1|awk '{print $8}')
  timeout 300 $NIX rIC3 -e bmc --end 15 "$F" > "$R/$P.core.bmc.log" 2>&1
  if grep -qa "counter-example" "$R/$P.core.bmc.log"; then
    if [ "$S" = "0" ]; then echo "CORE $P REFUTED-ON-CORE step=0 (spec-free: REAL on the fixed model -- read it)"; touch "$R/$P.corerefuted"; else echo "CORE $P refuted-on-core (decides nothing; goes to all.aig)"; fi; return; fi
  /usr/bin/time -f "%e" -o "$R/$P.core.t" timeout $KIND_CAP $NIX rIC3 -e kind "$F" > "$R/$P.core.k.log" 2>&1
  if grep -qa "RESULT: UNSAT" "$R/$P.core.k.log"; then
    echo "CORE $P PROVED-ON-CORE t=$(tail -1 "$R/$P.core.t")s C=$c step=$S (transfers to all.aig)"; touch "$R/$P.coreproved"
  else echo "CORE $P not-proved-on-core (step $S: $([ "$S" = "0" ] && echo IC3 next || echo goes to all.aig))"; fi
}
echo "=== core pre-screen of $(echo $STEP0 $OTHERS | wc -w) lemmas $(date -u +%H:%M) ==="
n=0; for P in $STEP0 $OTHERS; do core_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait
echo "=== core pre-screen done $(date -u +%H:%M): $(ls "$R"/*.coreproved 2>/dev/null | wc -l) proved on core ==="

ic3_one() {   # step-0 straggler: prove1.sh method (rIC3 default engine, core.aig, no constraints)
  local P=$1 F=build/sel/$ROUND-core-$P.aig rc
  /usr/bin/time -f "%e" -o "$R/$P.ic3.t" timeout $IC3_CAP $NIX rIC3 "$F" > "$R/$P.ic3.log" 2>&1; rc=$?
  if [ "$rc" = "20" ] || grep -qa "RESULT: UNSAT" "$R/$P.ic3.log"; then
    echo "REPROVE $P RESULT: UNSAT t=$(tail -1 "$R/$P.ic3.t")s step=0 engine=ic3 model=core (spec-free; proof transfers)"
  elif [ "$rc" = "10" ] || grep -qa "RESULT: SAT" "$R/$P.ic3.log"; then
    echo "REPROVE $P REFUTED-IC3 step=0 (spec-free lemma: REAL on the fixed model -- read it)"
  else echo "REPROVE $P IC3-TIMEOUT-OR-ERR rc=$rc step=0"; fi
}
S0LIST=$(for P in $STEP0; do [ -f "$R/$P.coreproved" ] || [ -f "$R/$P.corerefuted" ] || echo "$P"; done)
echo "=== step-0 IC3 pass ($IC3_CAP s, $IC3_PAR-wide): $(echo $S0LIST | wc -w) stragglers $(date -u +%H:%M) ==="
for P in $STEP0; do [ -f "$R/$P.coreproved" ] && echo "REPROVE $P RESULT: UNSAT t=$(tail -1 "$R/$P.core.t")s C=$(head -c 80 build/sel/$ROUND-core-$P.aig|head -1|awk '{print $8}') step=0 model=core (proof transfers)"; done
n=0; for P in $S0LIST; do ic3_one "$P" & n=$((n+1)); [ $((n % IC3_PAR)) -eq 0 ] && wait; done; wait
echo "=== step-0 done $(date -u +%H:%M): $(for P in $STEP0; do grep -qa "^REPROVE $P RESULT: UNSAT" /var/tmp/h3loop.log && echo x; done | wc -l) of $(echo $STEP0 | wc -w) ==="

wait $BUILDPID; [ -f "$R/.allbuilt" ] || echo "WARNING: all.aig build marker missing"
select_one() { local P=$1 S=$2 F=$3
  $NIX build/aig-manip build/all.aig select "$F" build/all.ywmap "$S" "$P" > "$R/$P.sel" 2>&1 || return 1
  local b; b=$(head -c 80 "$F"|head -1|awk '{print $7}'); SELC=$(head -c 80 "$F"|head -1|awk '{print $8}'); [ "$b" = "1" ]; }
icti_one() { local P=$1 F=$2 K=1 D=results/icti/$ROUND-$P; mkdir -p "$D"
  python3 /opt/verif/ablation/aigicti.py "$F" "$D/icti.aag" --k $K > "$D/aigicti.log" 2>&1 || { echo "ICTI $P aigicti failed"; return; }
  timeout 900 $NIX rIC3 -e bmc --end $((K+1)) --witness "$D/icti.aag" 2>"$D/bmc.err" | sed -n '/^1$/,$p' > "$D/icti.aiw.full"
  if [ ! -s "$D/icti.aiw.full" ]; then echo "ICTI $P NO-INDUCTION-CTI k=$K"; rm -f "$D/icti.aag"; return; fi
  awk -v k="$K" 'NR==3{print substr($0,1,length($0)-k); next}{print}' "$D/icti.aiw.full" > "$D/icti.aiw"
  $NIX build/aig-manip build/all.aig simulate build/all.ywmap build/all.vmap "$D/icti.aiw" "$D/icti.vcd" > "$D/sim.log" 2>&1
  python3 /opt/verif/ablation/h3ctirep.py "$D/icti.vcd" "$P" "$D/report.txt" > /dev/null 2>&1
  echo "ICTI $P INDUCTION-CTI k=$K frames=$(grep -c '^#' "$D/icti.vcd") -> $D/report.txt"; rm -f "$D/icti.aag" "$D/icti.aiw.full"; }
reprove_one() { local P=$1 S F; S=$(bash /var/tmp/h3step.sh "$P"); [ -n "$S" ] || { echo "REPROVE $P NO-STEP"; return; }
  if [ -f "$R/$P.coreproved" ]; then echo "REPROVE $P RESULT: UNSAT t=$(tail -1 "$R/$P.core.t")s C=$(head -c 80 build/sel/$ROUND-core-$P.aig|head -1|awk '{print $8}') step=$S model=core (proof transfers)"; return; fi
  F=build/sel/$ROUND-$P.aig
  select_one "$P" "$S" "$F" || { echo "REPROVE $P SELECT-REFUSED-OR-BAD"; return; }
  timeout 300 $NIX rIC3 -e bmc --end 15 "$F" > "$R/$P.bmc.log" 2>&1
  grep -qa "counter-example" "$R/$P.bmc.log" && { echo "REPROVE $P REFUTED $(grep -aoE 'in depth [0-9]+' "$R/$P.bmc.log"|head -1) C=$SELC (after model change -- read it)"; return; }
  /usr/bin/time -f "%e" -o "$R/$P.t" timeout $KIND_CAP $NIX rIC3 -e kind "$F" > "$R/$P.k.log" 2>&1
  echo "REPROVE $P $(grep -aoE 'RESULT: [A-Z]+' "$R/$P.k.log"|head -1) t=$(tail -1 "$R/$P.t" 2>/dev/null)s C=$SELC step=$S depth=$(grep -aoE 'kind depth: [0-9]+' "$R/$P.k.log"|tail -1|grep -oE '[0-9]+')"; }
goal_one() { local P=$1 S F; S=$(bash /var/tmp/h3step.sh "$P"); [ -n "$S" ] || { echo "GOAL $P NO-STEP"; return; }
  F=build/sel/$ROUND-$P.aig
  select_one "$P" "$S" "$F" || { echo "GOAL $P SELECT-REFUSED-OR-BAD"; return; }
  timeout 300 $NIX rIC3 -e bmc --end 15 "$F" > "$R/$P.bmc.log" 2>&1
  grep -qa "counter-example" "$R/$P.bmc.log" && { echo "RESULT $P REFUTED $(grep -aoE 'in depth [0-9]+' "$R/$P.bmc.log"|head -1) C=$SELC (GOAL -- read it)"; return; }
  echo "GOAL-BMC $P no-cex-to-depth $(grep -aoE 'bmc depth: [0-9]+' "$R/$P.bmc.log" | tail -1 | grep -oE '[0-9]+') (cap 300 s, --end 15)"
  local line; line=$(icti_one "$P" "$F"); echo "$line"
  if echo "$line" | grep -q "NO-INDUCTION-CTI"; then
    /usr/bin/time -f "%e" -o "$R/$P.t" timeout $GOAL_KIND_CAP $NIX rIC3 -e kind "$F" > "$R/$P.k.log" 2>&1
    echo "RESULT $P $(grep -aoE 'RESULT: [A-Z]+' "$R/$P.k.log"|head -1) t=$(tail -1 "$R/$P.t" 2>/dev/null)s C=$SELC step=$S (GOAL)"
  else echo "GOAL-CTI $P (not attempted with kind; CTI is next round's material)"; fi; }

echo "=== all.aig pass: $(for P in $OTHERS; do [ -f "$R/$P.coreproved" ] || echo x; done | wc -l) of $(echo $OTHERS|wc -w) higher lemmas not proved on core $(date -u +%H:%M) ==="
n=0; for P in $OTHERS; do reprove_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait
NOTPROVED=$(for P in $STEP0 $OTHERS; do grep -aq "^REPROVE $P RESULT: UNSAT" /var/tmp/h3loop.log || echo "$P"; done)
echo "=== re-prove complete $(date -u +%H:%M): $(( $(echo $STEP0 $OTHERS | wc -w) - $(echo $NOTPROVED | wc -w) )) of $(echo $STEP0 $OTHERS | wc -w) re-proved; NOT re-proved (left in place, NOT stripped): $(echo $NOTPROVED) ==="
echo "=== goals, CTI-first: $(echo $GOALS | wc -w) targets $(date -u +%H:%M) ==="
n=0; for P in $GOALS; do goal_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait
echo "=== chain_check3 on every goal ==="
for P in $GOALS; do echo "CHAIN $P: $(python3 /opt/verif/ablation/chain_check3.py "$P" | grep VERDICT)"; done
echo "ROUND-$ROUND-DONE $(date -u +%H:%M)"
