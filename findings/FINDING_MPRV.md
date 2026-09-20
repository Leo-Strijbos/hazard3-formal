# Finding: Hazard3 lets `mstatus.MPRV` be set when U-mode is not implemented

*Status: verified divergence from the RISC-V Sail golden model (machine-checked
counterexample). Fixed locally as a conformance patch and re-verified against
the spec. Not yet reported upstream. Severity: low.*
*Design: Hazard3 @ `8af9929` (RP2350 RISC-V core), configured `U_MODE=0`.*
*Found by: unbounded formal equivalence against the RISC-V Sail specification.*

## The divergence

Privileged spec §3.1.6.3: "MPRV ... If U-mode is not supported, MPRV is
hardwired to 0" (read-only 0, like MPP being fixed at M).

`hdl/hazard3_csr.v:239-244` (mstatus write arm):

```verilog
mstatus_mpie <= wdata_update[7];
mstatus_mie  <= wdata_update[3];
mstatus_mprv <= wdata_update[17];            // <- ungated
if (U_MODE) begin
    mstatus_mpp  <= ... ; mstatus_tw <= ...;  // <- gated
```

The neighbouring U-mode-only fields are gated on `U_MODE`; MPRV is not. With
`U_MODE=0` a `csrrs x0, mstatus, x16` (x16 = 0x20000) sets MPRV=1 and the
bit reads back as 1. It is not inert: `hazard3_csr.v:1531` derives the
effective load/store privilege from `mstatus_mprv`.

## Evidence

Witness `results/cex/round9-WrapMstatus/` (BMC from reset, goal `WrapMstatus`):
after `csrrs x0, mstatus, x16`, DUT `mstatus = 0x00021888`, spec
`mstatus = 0x00201888` (spec set TW instead — see FINDING_SPEC_TW.md for the
spec-side half of this witness).

## The fix (applied via `patch_hazard3_rtl.sh`, `H3_CONFORMANCE=1`)

```verilog
mstatus_mprv <= wdata_update[17] && U_MODE;
```

## Impact

No U-mode means no privilege to translate for, so software cannot observe a
wrong memory access; the visible effect is a WARL field that reads back a value
the spec says is hardwired 0. Conformance, not corruption.

## Simulation reproducer (2026-09-20)

`upstream/repro/mstatus_mprv_no_umode.bin` on Hazard3's CXXRTL testbench: exit 1 (diverges) at
v1.1.1 `8af99293`, exit 0 (agrees with Sail) on the same tree with the conformance
patch applied. Logs in `upstream/repro/out/` and `out-fixed/`.
