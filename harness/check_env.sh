#!/bin/sh
# Soundness check for the two-model split (see HAZARD3_HARNESS_PLAN.md).
#
# A lemma proved on build/core.aig may only be assumed on build/all.aig if the
# core sees the same transition relation and the same environment constraints in
# both.  check/h3_core_common.svh is shared textually, which is the structural
# argument; this script is the mechanical one: the set of exposed signal names
# under the core and under the two bus-environment instances must be identical.
#
# vmap lines are "<kind> <index> <offset> <name>".
set -e
cd "$(dirname "$0")"
extract() {
	awk '{print $1, $4}' "$1" \
	  | grep -E ' (cpu\.|ahbl_slave_assumptions_i\.|ahbl_master_props_i\.|h3_|rst_ni$|clk_i$|haddr$|hwrite$|htrans$|hsize$|hburst$|hprot$|hmastlock$|hmaster$|hexcl$|hready$|hresp$|hexokay$|hwdata$|hrdata$|pwrup_|clk_en$|unblock_|fence_|dbg_|irq$|soft_irq$|timer_irq$|mhartid_val$|eco_version$)' \
	  | sort -u
}
extract build/all.vmap  > /tmp/env-all.txt
extract build/core.vmap > /tmp/env-core.txt
N=$(wc -l < /tmp/env-all.txt)
if [ "$N" -lt 1000 ]; then
	echo "check-env: FAIL -- only $N signals matched; the vmap format or the scope names changed"
	exit 1
fi
# Also compare the AIGER headers' L (latches), B (bad states) and C (constraints):
# same state space, same property set, same environment constraints.
hdr() { head -c 80 "$1" | head -1 | awk '{print "L="$4" B="$7" C="$8}'; }
HA=$(hdr build/all.aig); HC=$(hdr build/core.aig)
if [ "$HA" != "$HC" ]; then
	echo "check-env: FAIL -- AIGER headers differ: all.aig $HA vs core.aig $HC"
	exit 1
fi

if diff -q /tmp/env-all.txt /tmp/env-core.txt > /dev/null; then
	echo "check-env: PASS -- $N core/environment signal entries identical, and both models have $HA"
else
	echo "check-env: FAIL -- environments differ:"
	diff /tmp/env-all.txt /tmp/env-core.txt | head -50
	exit 1
fi
