#!/bin/bash
# reproduce.sh -- rebuild the two models from the pinned sources, re-prove every lemma, re-check every goal.
# Expects: the lowRISC Ibex formal tool environment (nix develop <ibex>#oss-dev, commit in spec/PINS.md),
# Hazard3 and the Sail base checked out at the pinned commits, and this repository's harness/ as the
# working tree.  Run time on a 48-core machine: about three hours.  See docs/REPRODUCE.md.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
: "${HAZARD3_ROOT:?set HAZARD3_ROOT to a checkout of Hazard3 at the pinned commit}"
: "${SAIL_RISCV_ROOT:?set SAIL_RISCV_ROOT to a checkout of lowRISC/sail-riscv (branch ibex) at the pinned commit, with spec/*.patch applied}"
cd "$here/harness"
export H3_CONFORMANCE=1
make build/core.aig build/all.aig
# every lemma below the goal layer, nothing stripped, then the goals and the chain verdicts
bash "$here/tools/reprove_all2.sh" reproduce
for g in LoadAddr LoadEn MemNoSecondGranule MemWe NoMem StoreAddr StoreBe StoreEn StoreWData WrapMie WrapMscratch WrapMtvec WrapRegA WrapRegB WrapMcause WrapMstatus WrapMepc WrapPc; do
  echo "$g: $(python3 "$here/tools/chain_check3.py" "$g" | tail -1)"
done
