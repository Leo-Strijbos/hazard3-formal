# Finding (spec side): Sail lets `mstatus.TW` be set when U-mode is absent

*Status: spec-model bug in the pinned sail-riscv fork (lowrisc/sail-riscv
81a266b6, branch ibex). Fixed locally as commit "Gate 8" in
`sail-riscv-h3`. Hazard3 is correct here.*

## The divergence

Privileged spec §3.1.6.5: "TW ... When S-mode is not supported [and U-mode is
not supported], TW is read-only 0" — the field exists only to trap WFI from a
lower privilege, and with M-only there is none.

`model/riscv_sys_regs.sail`, `legalize_mstatus`, ends with:

```sail
if not(haveUsrMode()) then { let m = [m with MPRV = 0b0]; m } else m
```

It masks MPRV but not TW. Our harness passes `misa = 0x40801104` (U clear), so
`haveUsrMode()` is false and the model has been told there is no U-mode, yet a
`csrrs mstatus, x16` with bit 21 set leaves TW=1.

Hazard3 (`hazard3_csr.v:243-244`) gates `mstatus_tw` on `U_MODE` — correct.

## Evidence

Witness `results/cex/round9-WrapMstatus/`: spec `mstatus = 0x00201888`
(TW set), DUT `0x00021888` (MPRV set — the DUT half is FINDING_MPRV.md).

## The fix

```sail
if not(haveUsrMode()) then {
  let m = [m with MPRV = 0b0];
  let m = [m with TW = 0b0];
  m
} else m
```

Same shape as the existing MPRV masking. Setting a hypothetical U-mode
reproduces upstream behaviour bit-for-bit, so this generalises the model rather
than bending it toward Hazard3.
