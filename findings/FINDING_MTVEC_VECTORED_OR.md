# Finding: Hazard3 vectored interrupt entry uses `base | offset`, the spec uses `base + offset`

*Status: verified divergence from the RISC-V Sail golden model, found 2026-09-20 00:05 UTC by the
interrupt-entry PC agreement rung `CtiIrqPcAgrees` (round 36, BMC refutation at depth 7, witness in
`results/icti/round36-CtiIrqPcAgrees-bmc/report.txt`). Documented Hazard3 design choice. Not yet
reported upstream. Severity: low for aligned vector tables, wrong-address trap entry otherwise.*
*Design: Hazard3 @ the fix1 tree (four earlier conformance fixes applied), config as in
check/h3_core_common.svh (MTVEC_INIT 0, MTVEC_WMASK 0xfffffffd).*

## The divergence

RISC-V privileged spec, mtvec: in Vectored mode "interrupts cause the pc to be set to the address in
the BASE field plus four times the interrupt cause number". BASE must be 4-byte aligned; "the MODE
setting may impose additional alignment constraints on the value in the BASE field" -- a WARL
constraint on the stored value.

Sail (`riscv_sys_regs.sail`, `tvec_addr`): `TV_Vector => base + (zero_extend(cause) << 2)`.

Hazard3 (`hdl/hazard3_csr.v:1464-1468`):

```verilog
assign trap_addr =
    except == EXCEPT_MRET    ? mepc            :
    except == EXCEPT_REFETCH ? debug_dpc_rdata :
    pending_dbg_resume       ? debug_dpc_rdata :
                               mtvec | {26'h0, vector_sel, 2'h0};
```

with `mtvec = mtvec_reg & ~3` and every BASE bit writable (`MTVEC_WMASK = 32'hfffffffd`). Hazard3's
documentation (`doc/sections/csr.adoc`, mtvec) states it: "In Vectored mode, this is _OR'd_ with the
trap offset to calculate the trap entry address, so the table must be aligned to its total size,
rounded up to a power of 2."

So Hazard3 (a) accepts and reads back an unaligned BASE in Vectored mode -- the architecture says an
implementation imposing extra alignment must legalize the write (WARL) so the register never holds a
value outside the constraint -- and (b) computes the target with OR, which differs from BASE + 4*cause
exactly when BASE has bits set in the offset's range.

## Witness (machine-checked, 9 frames)

| frame | event |
|---|---|
| 6 | CSR write sets `mtvec_reg = 0x00000075` (BASE 0x74, MODE Vectored) |
| 7 | machine software interrupt taken (`mcause_irq_num = 3`) |

At frame 7: DUT `m_trap_addr = 0x7c` (0x74 \| 0x0c); Sail `spec_post_pc = 0x80` (0x74 + 0x0c).
The DUT enters the handler 4 bytes early, inside the previous vector slot.

## Impact

None for software that follows Hazard3's documented alignment rule (a 64-byte-aligned table for the
three standard interrupts; larger for the external-interrupt vectors). Any software that sets an
unaligned BASE in Vectored mode -- legal per the ISA if the implementation does not legalize it away --
takes interrupts at the wrong address. Same class as C.ADDI4SPN: a documented departure from what the
golden model does, not a functional bug under Hazard3's own rules.

## Fixes (untested)

Either is architecturally faithful:

1. `mtvec + {26'h0, vector_sel, 2'h0}` -- matches Sail bit-for-bit for every BASE; a 32-bit adder (only
   bits 5:2 plus carry matter, a synthesizer will narrow it).
2. Keep the OR but WARL-legalize: when MODE == Vectored, clear BASE bits [5:2] on write (and in
   `MTVEC_INIT`), so the stored value always satisfies the alignment the OR relies on. Changes what
   software reads back from mtvec.

Option 1 is the smaller change to the proof (no read-back semantics change); the equivalence proof
needs no spec-side change for either.

## Proof consequences

`WrapPc` (and the interrupt half of the pc-tracking rung) cannot hold on the unfixed RTL: the
divergence is reachable at depth 7. Fixing the RTL is a model change: log rotation and a full re-prove
of the ladder, as for fix1 (now faster: v4.1 runner, core pre-screen, ~250 lemmas at ~200 s each with
18 in parallel, plus the 48 step-0 IC3 proofs).

## Fix applied (2026-09-20 05:53 UTC, user decision)

`patch_hazard3_rtl.sh` now carries conformance patch #6: `hazard3_csr.v:1468` becomes
`mtvec + {26'h0, vector_sel, 2'h0}` (option 1 above). The whole ladder is re-proved on the re-patched
model by `/var/tmp/reprove_all2.sh fix2` (log rotated to `/var/tmp/h3loop.log.pre-fix2`); nothing proven
on the pre-fix2 model is claimed afterwards. Still untested in simulation and not reported upstream.

## Simulation reproducer (2026-09-20)

`upstream/repro/mtvec_vectored_unaligned.bin` on Hazard3's CXXRTL testbench: exit 1 (diverges) at
v1.1.1 `8af99293`, exit 0 (agrees with Sail) on the same tree with the conformance
patch applied. Logs in `upstream/repro/out/` and `out-fixed/`.
