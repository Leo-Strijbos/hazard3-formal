<!-- Draft issue for https://github.com/lowRISC/sail-riscv, branch `ibex` (bug report). Not yet filed. -->

# legalize_mstatus does not mask TW when U-mode is absent (branch `ibex`)

## Expected behaviour

Privileged spec, mstatus.TW: "When S-mode is not supported, TW is read-only 0"
(there is no lower privilege mode to trap WFI from when U-mode is absent
too). With misa.U clear, a CSR write that sets bit 21 of mstatus should leave
TW at 0.

Upstream riscv/sail-riscv has had this since commit `8de2591` (2025-02-19,
"Update mstatus bits guarded by privilege modes"):

```
TW = if extensionEnabled(Ext_U) then v[TW] else 0b0,
```

## Observed behaviour

On the `ibex` branch (`5fca3f99`, and the revision `81a266b6` pinned by Ibex's
`dv/formal` flake), `legalize_mstatus` in `model/riscv_sys_regs.sail` ends
with

```
if not(haveUsrMode()) then {
  let m = [m with MPRV = 0b0];
  m
} else m
```

It masks MPRV but not TW, so with `haveUsrMode()` false a
`csrrs x0, mstatus, x16` with x16 = 0x200000 leaves TW = 1 and mstatus reads
back as 0x00201888 in our trace.

## Why it matters for this branch

This branch is the reference model for the Ibex formal flow and for our
Hazard3 equivalence proof. In both, the core under test (Ibex and Hazard3)
correctly hardwires TW to 0, so the model is the side that diverges, and an
equivalence proof of mstatus cannot close without a local patch. The patch we
used adds `let m = [m with TW = 0b0];` next to the MPRV line; with U-mode
present it changes nothing.

## Reproduce

Configure the model with misa.U clear (the Ibex flow does this through
`plat_*`/`sys_*` settings), execute `csrrs x0, mstatus, x16` with
x16 = 0x200000, read mstatus: bit 21 is set. The equivalent upstream model
reads it back clear.
