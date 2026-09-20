#!/usr/bin/env bash
# Patch a *copy* of the Hazard3 RTL for the formal flow, in the same spirit as
# the Ibex flow's `make fusesoc` step. The upstream tree is never modified.
#
# TWO CLASSES OF PATCH, deliberately kept apart:
#
#   TOOL patches   - always applied. No behavioural change; they exist only so
#                    Yosys can read the RTL. A proof of the tool-patched design
#                    is a proof of the shipped design.
#
#   CONFORMANCE    - applied ONLY when H3_CONFORMANCE=1. These DO change
#   patches          behaviour: each one fixes a divergence we found against the
#                    Sail specification. A proof of a conformance-patched design
#                    is NOT a proof of the shipped chip. It is a proof that the
#                    proposed fix closes the divergence.
#
# Every build writes build/hazard3-rtl/PATCH_MANIFEST so a result can always be
# traced to the exact RTL configuration it was produced from. Never report a
# number without it.
set -euo pipefail
dir="$1"
manifest="$dir/PATCH_MANIFEST"
: > "$manifest"

sub() { # sub <file> <old> <new> <label>
    local f="$dir/$1" old="$2" new="$3" label="$4"
    local n; n=$(grep -cF "$old" "$f" || true)
    [ "$n" = "1" ] || { echo "patch_hazard3_rtl: '$label' expected 1 match in $1, found $n" >&2; exit 1; }
    python3 - "$f" "$old" "$new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p).read()
assert s.count(old) == 1
open(p, "w").write(s.replace(old, new))
PY
    echo "$label" >> "$manifest"
}

# ---------------- TOOL patches (always) ----------------
# Verilog-2005 functions are static, so their argument variables are shared
# state. hazard3_csr.v's `update_nonconst` is called from two always blocks,
# which makes yosys-slang emit two drivers and Yosys fail. `automatic` gives
# each call its own locals, which is what the RTL already assumes.
sed -i 's|^function \[|function automatic [|' \
    "$dir/hazard3_csr.v" "$dir/hazard3_instr_decompress.v"
echo "TOOL: function -> function automatic (hazard3_csr.v, hazard3_instr_decompress.v) [no behavioural change]" >> "$manifest"

# ---------------- CONFORMANCE patches (opt-in) ----------------
if [ "${H3_CONFORMANCE:-0}" = "1" ]; then
    # FINDING_C_ADDI4SPN: C.ADDI4SPN's immediate is instr[12:5] and nzuimm==0 is
    # RESERVED. The test `~|instr_in[12:2]` also requires rd'==0, so it catches
    # only 0x0000 and executes the other 7 reserved encodings as `addi rd',x2,0`.
    # `~|instr_in[12:5]` is exactly "nzuimm == 0": still catches 0x0000, and
    # matches how every sibling reserved test in this file is written.
    sub hazard3_instr_decompress.v \
        'invalid   = ~|instr_in[12:2]; // Always-invalid all-zeroes instruction' \
        'invalid   = ~|instr_in[12:5]; // RESERVED if nzuimm == 0 [conformance fix]' \
        'CONFORMANCE: C.ADDI4SPN reserved nzuimm==0 now traps (FINDING_C_ADDI4SPN.md) [BEHAVIOURAL]'

    # FINDING_MPRV: mstatus.MPRV is read-only 0 when U-mode is not implemented
    # (privileged spec 3.1.6.3). The write at :241 is ungated while its
    # neighbours (MPP, MPIE) are gated on U_MODE.
    sub hazard3_csr.v \
        $'\t\t\tmstatus_mprv <= wdata_update[17];' \
        $'\t\t\tmstatus_mprv <= wdata_update[17] && U_MODE; // read-only 0 without U-mode [conformance fix]' \
        'CONFORMANCE: mstatus.MPRV read-only 0 when U_MODE=0 (FINDING_MPRV.md) [BEHAVIOURAL]'

    # FINDING_MEICONTEXT: a write to meicontext (0xBE5) commits mie[3]/mie[7]
    # even when EXTENSION_XH3IRQ=0 makes the CSR undecodable and the
    # instruction traps. The decode at :1248 is gated; the write arm is not.
    sub hazard3_csr.v \
        $'\t\tend else if (wen_m_mode && addr == MEICONTEXT) begin' \
        $'\t\tend else if (wen_m_mode && addr == MEICONTEXT && EXTENSION_XH3IRQ) begin // no side effect when the CSR does not exist [conformance fix]' \
        'CONFORMANCE: meicontext write to mie gated on EXTENSION_XH3IRQ (FINDING_MEICONTEXT.md) [BEHAVIOURAL]'

    # FINDING_FENCE_FIELDS: FENCE's rs1 and rd fields are reserved and "base
    # implementations shall ignore these fields" (unprivileged spec 2.7). The
    # opcode pattern pins them to zero, so e.g. 0xf150020f (fence, rd=x4)
    # raises illegal-instruction instead of retiring as a fence.
    sub rv_opcodes.vh \
        "\`define RVOPC_FENCE       32'b????????????00000000000000001111" \
        "\`define RVOPC_FENCE       32'b?????????????????000?????0001111 // rs1/rd ignored [conformance fix]" \
        'CONFORMANCE: FENCE ignores rs1/rd instead of trapping (FINDING_FENCE_FIELDS.md) [BEHAVIOURAL]'
    sub hazard3_decode.v \
        "\`RVOPC_FENCE:     begin raw_rs2 = X0; raw_fence_d = 1'b1; end  // Note rs1/rd are zero in instruction" \
        "\`RVOPC_FENCE:     begin raw_rs1 = X0; raw_rs2 = X0; raw_rd = X0; raw_fence_d = 1'b1; end  // rs1/rd ignored per ISA [conformance fix]" \
        'CONFORMANCE: FENCE decode forces rs1/rs2/rd to x0 (FINDING_FENCE_FIELDS.md) [BEHAVIOURAL]'

    # FINDING_MTVEC_VECTORED_OR: in Vectored mode the ISA sets pc = BASE + 4*cause
    # (Sail tvec_addr: base + (cause << 2)); Hazard3 ORs the offset into an
    # unconstrained BASE (MTVEC_WMASK leaves BASE[5:2] writable), so an
    # unaligned base sends vectored interrupts to the wrong address.  The
    # addition matches the specification for every BASE (user decision
    # 2026-09-20: fix the RTL and re-prove).
    sub hazard3_csr.v \
        $'\t                           mtvec | {26\'h0, vector_sel, 2\'h0};' \
        $'\t                           mtvec + {26\'h0, vector_sel, 2\'h0}; // BASE + 4*cause per ISA [conformance fix]' \
        'CONFORMANCE: vectored trap entry uses mtvec + offset instead of mtvec | offset (FINDING_MTVEC_VECTORED_OR.md) [BEHAVIOURAL]'
fi

echo "--- PATCH_MANIFEST ---"
cat "$manifest"
