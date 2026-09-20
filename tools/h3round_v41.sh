#!/bin/bash
# h3round_v41.sh <round> <candidates.txt> [targets...]
#
# v4.1 (2026-09-19, user decision "the Oxford way"): AXIOMS.  Names listed in <candidates.txt>.axiom are
#   inserted like any candidate but NEVER attempted and NEVER stripped.  Each one logs
#   "AXIOM <name> assumed ..." (chain_check3.py reads these and reports PROVEN MODULO AXIOMS) and a
#   "RESULT <name> RESULT: AXIOM" line so the round's bookkeeping stays aligned.  The Ibex/Oxford proof
#   did exactly this for the M-type spec-compliance lemma ("Never actually proved, just assumed").
# v4.0 (2026-09-19 evening, built at the user's request after the efficiency review):
#  * ICTI (k=ICTI_K, default 1) still runs IN PARALLEL with kind for every candidate.  The log data
#    (16 lemmas with a k=1 aigicti CTI later proved by kind at depth 1) shows the k=1 CTI does NOT
#    predict kind failure, so v4 does NOT skip kind on CTI-positive candidates.
#  * a strip only invalidates proofs ABOVE the lowest stripped layer (same-layer lemmas are not
#    constraints of each other; lower layers never used the stripped lemma), so only those survivors
#    are re-proved.  Steps are recorded before the strip.
#  * the "no full build" shortcut also fires when every candidate was decided on core (proved or
#    DUT-only failed) and no goal is listed: core proofs transfer, so all.aig is only rebuilt when a
#    non-DUT candidate or a goal needs it.  If a core-proved lemma sits above a DUT-only failure the
#    shortcut is refused (its constraint set changed) and the full path re-proves it.
#  * RESULT lines carry the kind depth; KIND_CAP default 600 s (p90 of proofs was 337 s, max 462 s);
#    MAXJOBS may be set from the environment.
#  * cands files may hold several layers ("/" lines = new layer, h3insert.py) -> one build, many layers.
#
# v3.1 + one soundness fix: a proof on core.aig is relative to the layers
# beneath it exactly like any other proof.  After ANY strip, every
# .coreproved marker is deleted so survivors are genuinely re-proved on the
# post-strip model instead of echoing a stale core result.  (Found 20:45 when
# CtiGhostTracksMscratch 'proved on core' by assuming the still-unproven
# CtiFollowerPostIsDutMscratchV2 beneath it.)
#
# v3 + the core-only PRE-SCREEN (tier 1.3):
#   build/core.aig is the same core + same harness with the Sail spec ABSENT
#   (spec_* are free inputs) and builds in ~1 MINUTE against ~15 for all.aig.
#   Every candidate is first tried there: refute (bmc 15) then kind 400 s.
#   A proof on core.aig TRANSFERS to all.aig unconditionally -- all.aig is
#   core.aig plus constraints on the free spec inputs, and a fact proved under
#   fewer constraints holds under more -- so no lemma needs classifying as
#   DUT-only.  A refutation or timeout on core.aig decides NOTHING (a lemma
#   that mentions the spec is trivially falsifiable there): such candidates
#   simply go on to all.aig as before.  Zero soundness exposure.
#
# v2 + tier-1 throughput changes (2026-09-18 evening):
#  * kind cap 1200 s -> 400 s.  Every proof today landed in 145-230 s; every
#    timeout ran to 1201 s.  Past 400 s a lemma essentially never proves.
#  * a k=1 induction-CTI runs IN PARALLEL with every proof attempt, from the
#    same select file (aigicti.py; no second select).  If the proof times out,
#    the diagnosis is already on disk (results/icti/<round>_<P>) -- no
#    separate extraction step, no idle box.
#  * goals are checked CTI-FIRST: a 3-minute k=1 induction-CTI instead of a
#    20-minute kind.  No CTI -> the goal is 1-inductive given the facts, and a
#    direct kind (600 s) closes it (this is how MemNoSecondGranule closed).
#    CTI -> log GOAL-CTI and move on; the CTI is the next round's material.
# Chain-of-custody discipline unchanged from v2: after any strip, every
# survivor is re-proved on the rebuilt model.
set -uo pipefail
ROUND=${1:?round}; CANDS=${2:?candidates file}; shift 2; TARGETS=("$@")
H3FORMAL=${H3FORMAL:-/opt/verif/h3formal}; IBEX=${IBEX:-/opt/verif/ibex}
TOOLS=${TOOLS:-/opt/verif/ablation}; LOG=${LOG:-"$LOG"}
cd "$H3FORMAL"
exec >> "$LOG" 2>&1
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
export H3_CONFORMANCE=1
NIX="nix develop $IBEX#oss-dev --command"
R=results/$ROUND; mkdir -p "$R" build/sel results/icti
KIND_CAP=${KIND_CAP:-600}; GOAL_KIND_CAP=${GOAL_KIND_CAP:-600}; ICTI_K=${ICTI_K:-1}
MEM_PER=20   # two engines per candidate now (proof + icti)
MAXJOBS=${MAXJOBS:-$(( $(free -g | awk '/Mem:/{print $2}') / MEM_PER ))}
echo "=== ROUND $ROUND (v4.1 icti_k=${ICTI_K:-1} axioms=$( [ -f "$CANDS.axiom" ] && tr '\n' ' ' < "$CANDS.axiom" )) $(date -u +%H:%M)  maxjobs=$MAXJOBS kind_cap=${KIND_CAP}s ==="

cp thm/hazard3.proof "$R/proof.before"
[ -s "$CANDS" ] && { python3 "$TOOLS"/h3insert.py "$CANDS" || exit 1; }

# ---- core-only pre-screen (proofs transfer; refutations decide nothing) ----
NAMES=$(grep -oE "^[A-Za-z0-9_]+:" "$CANDS" | tr -d ':')
DUTLIST="$CANDS.dut"; isdut() { [ -f "$DUTLIST" ] && grep -qxF "$1" "$DUTLIST"; }
AXLIST="$CANDS.axiom"; isaxiom() { [ -f "$AXLIST" ] && grep -qxF "$1" "$AXLIST"; }
$NIX make build/core.aig > "$R/build-core.log" 2>&1
echo "core build rc=$?  $(head -c 80 build/core.aig | head -1)"
declare -A COREPROVED
core_one() {
  local P=$1 S F c
  S=$(python3 - "$P" <<'PY2'
import json,re,sys
for x in json.load(open("build/core.ywmap"))["asserts"]:
    m=re.match(r"\$\\top\.Step(\d+)_(.+?)\$",x[0])
    if m and m[2]==sys.argv[1]: print(m[1]); break
PY2
); [ -n "$S" ] || { echo "CORE $P not-in-core-ywmap"; return; }
  F=build/sel/$ROUND-core-$P.aig
  $NIX build/aig-manip build/core.aig select "$F" build/core.ywmap "$S" "$P" > "$R/$P.core.sel" 2>&1 || { echo "CORE $P select-refused"; return; }
  [ "$(head -c 80 "$F"|head -1|awk '{print $7}')" = "1" ] || { echo "CORE $P bad-selection"; return; }
  c=$(head -c 80 "$F"|head -1|awk '{print $8}')
  timeout 300 $NIX rIC3 -e bmc --end 15 "$F" > "$R/$P.core.bmc.log" 2>&1
  if grep -qa "counter-example" "$R/$P.core.bmc.log"; then
    if isdut "$P"; then echo "CORE $P REFUTED-ON-CORE (DUT-only: a real CEX, skipping all.aig)"; touch "$R/$P.dutfail"; else echo "CORE $P refuted-on-core (decides nothing; goes to all.aig)"; fi; return; fi
  /usr/bin/time -f "%e" -o "$R/$P.core.t" timeout $KIND_CAP $NIX rIC3 -e kind "$F" > "$R/$P.core.k.log" 2>&1
  if grep -qa "RESULT: UNSAT" "$R/$P.core.k.log"; then
    echo "CORE $P PROVED-ON-CORE t=$(tail -1 "$R/$P.core.t")s C=$c step=$S (transfers to all.aig)"; touch "$R/$P.coreproved"
  elif isdut "$P"; then echo "CORE $P NOT-PROVED-ON-CORE (DUT-only: skipping all.aig, treated as failed)"; touch "$R/$P.dutfail"
  else echo "CORE $P not-proved-on-core (goes to all.aig)"; fi
}
echo "=== core pre-screen of $(echo $NAMES|wc -w) candidates $(date -u +%H:%M) ==="
n=0; for P in $NAMES; do isaxiom "$P" && continue; core_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait
echo "=== core pre-screen done $(date -u +%H:%M): $(ls "$R"/*.coreproved 2>/dev/null | wc -l) proved on core ==="

TOALL=$(for P in $NAMES; do [ -f "$R/$P.coreproved" ] || [ -f "$R/$P.dutfail" ] || echo "$P"; done)
DUTFAILED=$(for P in $NAMES; do [ -f "$R/$P.dutfail" ] && echo "$P"; done)
corestep() { python3 - "$1" <<'PY4'
import json,re,sys
for x in json.load(open("build/core.ywmap"))["asserts"]:
    m=re.match(r"\$\\top\.Step(\d+)_(.+?)\$",x[0])
    if m and m[2]==sys.argv[1]: print(m[1]); break
PY4
}
SHORTCUT=0
if [ -z "$TOALL" ] && [ -n "$NAMES" ]; then
  NCP=$(ls "$R"/*.coreproved 2>/dev/null | wc -l)
  if [ "$NCP" -eq 0 ] || [ ${#TARGETS[@]} -eq 0 ]; then
    SHORTCUT=1
    if [ -n "$DUTFAILED" ] && [ "$NCP" -gt 0 ]; then   # a core proof above a DUT failure used it as a constraint
      MINDF=$(for P in $DUTFAILED; do corestep "$P"; done | sort -n | head -1)
      for P in $NAMES; do [ -f "$R/$P.coreproved" ] || continue
        [ "$(corestep "$P")" -gt "$MINDF" ] && { echo "=== shortcut refused: $P core-proved above DUT-only failure layer step=$MINDF ==="; SHORTCUT=0; }; done
    fi
  fi
fi
if [ "$SHORTCUT" = 1 ]; then
  echo "=== nothing for all.aig (v4.0 shortcut): $(ls "$R"/*.coreproved 2>/dev/null|wc -l) core-proved (transfer; all.aig/all.ywmap rebuilt next round), $(echo $DUTFAILED|wc -w) DUT-only failed; no full build this round ==="
  for P in $NAMES; do [ -f "$R/$P.coreproved" ] || continue
    S=$(python3 - "$P" <<'PY3'
import json,re,sys
for x in json.load(open("build/core.ywmap"))["asserts"]:
    m=re.match(r"\$\\top\.Step(\d+)_(.+?)\$",x[0])
    if m and m[2]==sys.argv[1]: print(m[1]); break
PY3
)
    echo "RESULT $P RESULT: UNSAT t=$(tail -1 "$R/$P.core.t")s C=$(head -c 80 build/sel/$ROUND-core-$P.aig|head -1|awk '{print $8}') step=$S model=core (proof transfers)"; done
  if [ -n "$DUTFAILED" ]; then echo "=== removing $(echo $DUTFAILED|wc -w) DUT-only failures: $(echo $DUTFAILED) ==="; python3 "$TOOLS"/h3insert.py --remove $DUTFAILED || exit 1; fi
  echo "ROUND-$ROUND-DONE $(date -u +%H:%M)"; exit 0
fi
$NIX make build/all.aig > "$R/build.log" 2>&1
echo "build rc=$?  $(head -c 80 build/all.aig | head -1)"
grep -aiE "error:" "$R/build.log" | head -3

select_one() {   # -> sets SELF, SELC; returns 1 on refusal/bad selection
  local P=$1 S=$2 F=$3
  $NIX build/aig-manip build/all.aig select "$F" build/all.ywmap "$S" "$P" > "$R/$P.sel" 2>&1 || return 1
  local b; b=$(head -c 80 "$F"|head -1|awk '{print $7}'); SELC=$(head -c 80 "$F"|head -1|awk '{print $8}')
  [ "$b" = "1" ]
}
icti_one() {     # k-induction CTI from an existing select file; ICTI lines only (k = ICTI_K)
  local P=$1 F=$2 K=$ICTI_K D=results/icti/$ROUND-$P; mkdir -p "$D"
  python3 "$TOOLS"/aigicti.py "$F" "$D/icti.aag" --k $K > "$D/aigicti.log" 2>&1 || { echo "ICTI $P aigicti failed"; return; }
  timeout 900 $NIX rIC3 -e bmc --end $((K+1)) --witness "$D/icti.aag" 2>"$D/bmc.err" | sed -n '/^1$/,$p' > "$D/icti.aiw.full"
  if [ ! -s "$D/icti.aiw.full" ]; then echo "ICTI $P NO-INDUCTION-CTI k=$K"; return; fi
  awk -v k="$K" 'NR==3{print substr($0,1,length($0)-k); next}{print}' "$D/icti.aiw.full" > "$D/icti.aiw"
  $NIX build/aig-manip build/all.aig simulate build/all.ywmap build/all.vmap "$D/icti.aiw" "$D/icti.vcd" > "$D/sim.log" 2>&1
  python3 "$TOOLS"/h3ctirep.py "$D/icti.vcd" "$P" "$D/report.txt" > /dev/null 2>&1
  echo "ICTI $P INDUCTION-CTI k=$K frames=$(grep -c '^#' "$D/icti.vcd") -> $D/report.txt"
  rm -f "$D/icti.aag" "$D/icti.aiw.full"   # v3.9: drop the AIG (~150 MB), KEEP icti.vcd for h3frames (v3.8 deleted it and round 29 lost its CTI detail)
}
prove_one() {
  local P=$1 S F
  [ -f "$R/$P.dutfail" ] && { echo "RESULT $P SKIPPED (DUT-only, failed on core)"; return; }
  S=$(bash "$TOOLS"/h3step.sh "$P"); [ -n "$S" ] || { echo "RESULT $P NO-STEP"; return; }
  if isaxiom "$P"; then
    echo "AXIOM $P assumed (never attempted, never stripped; user decision 2026-09-19 'the Oxford way') step=$S"
    echo "RESULT $P RESULT: AXIOM step=$S"; return
  fi
  if [ -f "$R/$P.coreproved" ]; then
    echo "RESULT $P RESULT: UNSAT t=$(tail -1 "$R/$P.core.t")s C=$(head -c 80 build/sel/$ROUND-core-$P.aig|head -1|awk '{print $8}') step=$S model=core (proof transfers)"; return
  fi
  F=build/sel/$ROUND-$P.aig
  select_one "$P" "$S" "$F" || { echo "RESULT $P SELECT-REFUSED-OR-BAD"; return; }
  timeout 300 $NIX rIC3 -e bmc --end 15 "$F" > "$R/$P.bmc.log" 2>&1
  grep -qa "counter-example" "$R/$P.bmc.log" && { echo "RESULT $P REFUTED $(grep -aoE 'in depth [0-9]+' "$R/$P.bmc.log"|head -1) C=$SELC"; return; }
  icti_one "$P" "$F" &          # diagnosis in parallel with the proof (v4.0: never skipped, never gates kind)
  local ip=$!
  /usr/bin/time -f "%e" -o "$R/$P.t" timeout $KIND_CAP $NIX rIC3 -e kind "$F" > "$R/$P.k.log" 2>&1
  echo "RESULT $P $(grep -aoE 'RESULT: [A-Z]+' "$R/$P.k.log"|head -1) t=$(tail -1 "$R/$P.t" 2>/dev/null)s C=$SELC step=$S depth=$(grep -aoE 'kind depth: [0-9]+' "$R/$P.k.log"|tail -1|grep -oE '[0-9]+')"
  wait $ip
}
goal_one() {     # CTI-first: 3 min diagnosis before any 20-minute proof attempt
  local P=$1 S F
  S=$(bash "$TOOLS"/h3step.sh "$P"); [ -n "$S" ] || { echo "GOAL $P NO-STEP"; return; }
  F=build/sel/$ROUND-$P.aig
  select_one "$P" "$S" "$F" || { echo "GOAL $P SELECT-REFUSED-OR-BAD"; return; }
  timeout 300 $NIX rIC3 -e bmc --end 15 "$F" > "$R/$P.bmc.log" 2>&1
  grep -qa "counter-example" "$R/$P.bmc.log" && { echo "RESULT $P REFUTED $(grep -aoE 'in depth [0-9]+' "$R/$P.bmc.log"|head -1) C=$SELC (GOAL — read it)"; return; }
  echo "GOAL-BMC $P no-cex-to-depth $(grep -aoE 'bmc depth: [0-9]+' "$R/$P.bmc.log" | tail -1 | grep -oE '[0-9]+') (cap 300 s, --end 15)"
  local line; line=$(icti_one "$P" "$F"); echo "$line"
  if echo "$line" | grep -q "NO-INDUCTION-CTI"; then
    /usr/bin/time -f "%e" -o "$R/$P.t" timeout $GOAL_KIND_CAP $NIX rIC3 -e kind "$F" > "$R/$P.k.log" 2>&1
    echo "RESULT $P $(grep -aoE 'RESULT: [A-Z]+' "$R/$P.k.log"|head -1) t=$(tail -1 "$R/$P.t" 2>/dev/null)s C=$SELC step=$S (GOAL)"
  else
    echo "GOAL-CTI $P (not attempted with kind; CTI is next round's material)"
  fi
}

N=$(echo "$NAMES" | wc -w)
echo "=== proving $N candidates, $MAXJOBS at a time $(date -u +%H:%M) ==="
n=0; for P in $NAMES; do prove_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait

declare -A STEPOF; for P in $NAMES; do STEPOF[$P]=$(bash "$TOOLS"/h3step.sh "$P"); done
FAILED=$(grep -aE "^RESULT " "$LOG" | tail -n "$N" | grep -vaE "RESULT: (UNSAT|AXIOM)" | awk '{print $2}')
if [ -n "$FAILED" ]; then
  echo "=== removing $(echo "$FAILED"|wc -w) unproven: $(echo $FAILED) ==="
  python3 "$TOOLS"/h3insert.py --remove $FAILED || exit 1
  rm -f "$R"/*.coreproved          # core proofs were relative to the pre-strip layers
  python3 "$TOOLS"/ywstrip.py build/all.ywmap $FAILED > "$R/ywstrip.log" 2>&1
  echo "ywstrip rc=$?  $(cat "$R/ywstrip.log")  (no rebuild: retired in all.ywmap, real make next round)"
  # v4.0: a strip only invalidates proofs ABOVE the lowest stripped layer (same-layer lemmas are not
  # constraints of each other; lower layers never used the stripped lemma).  Steps were read before ywstrip.
  MINFAIL=$(for P in $FAILED; do echo "${STEPOF[$P]:-9999}"; done | sort -n | head -1)
  SURV=$(for P in $NAMES; do echo "$FAILED" | grep -qw "$P" && continue; [ "${STEPOF[$P]:-0}" -gt "${MINFAIL:-9999}" ] && echo "$P"; done)
  NS=$(echo $SURV | wc -w)
  echo "=== strip: lowest stripped layer step=$MINFAIL; $NS survivor(s) above it need re-proof ==="
  if [ "$NS" -gt 0 ]; then
    echo "=== re-proving $NS survivors on the post-strip model $(date -u +%H:%M) ==="
    n=0; for P in $SURV; do prove_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait
    FAILED2=$(grep -aE "^RESULT " "$LOG" | tail -n "$NS" | grep -vaE "RESULT: (UNSAT|AXIOM)" | awk '{print $2}')
    if [ -n "$FAILED2" ]; then
      echo "=== survivors that did NOT re-prove, removing: $(echo $FAILED2) ==="
      python3 "$TOOLS"/h3insert.py --remove $FAILED2 || exit 1
      rm -f "$R"/*.coreproved
      python3 "$TOOLS"/ywstrip.py build/all.ywmap $FAILED2 > "$R/ywstrip2.log" 2>&1
      echo "ywstrip2 rc=$?  $(cat "$R/ywstrip2.log")"
    fi
  fi
fi

NEWPROVED=$(for P in $NAMES; do grep -aE "^RESULT $P RESULT: UNSAT" "$LOG" | tail -1 | grep -q . && echo "$P"; done | wc -w)
if [ ${#TARGETS[@]} -gt 0 ] && [ -n "$NAMES" ] && [ "$NEWPROVED" -eq 0 ]; then echo "=== goals skipped (v3.5): no candidate proved this round, constraint set unchanged ==="; TARGETS=(); fi
if [ ${#TARGETS[@]} -gt 0 ]; then
  echo "=== goals, CTI-first: $((${#TARGETS[@]})) targets $(date -u +%H:%M) ==="
  n=0; for P in "${TARGETS[@]}"; do goal_one "$P" & n=$((n+1)); [ $((n % MAXJOBS)) -eq 0 ] && wait; done; wait
fi
echo "ROUND-$ROUND-DONE $(date -u +%H:%M)"
