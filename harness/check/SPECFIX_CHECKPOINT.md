# SPECFIX CHECKPOINT — gate 6 items 1 and 2 (Sail specification configuration)

Written 2026-09-16 21:30 UTC, mid-run, because the session is being stopped.
Everything described here is **already written to disk on the box**. Two tmux
jobs (`sweepall`, `ctrlgoals`) were deliberately left running; do not kill them.

**NOTE ON THIS FILE'S LOCATION.** The coordinator asked for
`/opt/verif/hazard3/check/SPECFIX_CHECKPOINT.md`. `/opt/verif/hazard3` is the
pristine Hazard3 RTL checkout and the standing task rule is "never touch
`/opt/verif/hazard3`", so this file is at
**`/opt/verif/h3formal/check/SPECFIX_CHECKPOINT.md`** instead — the *harness's*
`check/` directory, which is the one this work owns. A copy is at
`s3://breaker-artifacts-157975550152/verif/state/SPECFIX_CHECKPOINT.md`.

---

## 0. State of the tree

| Path | State |
|---|---|
| `/opt/verif/h3formal/sail-riscv-h3/` | **local git fork**, 2 commits, working tree clean. `54d9ed6` = lowrisc/sail-riscv `81a266b6` (branch `ibex`, the rev ibex's `flake.lock` pins), verified byte-identical to `$LOWRISC_SAIL_RISCV_SRC/model`. `b96a1ea` = the gate-6 fixes. |
| `/opt/verif/h3formal/spec/sail-riscv-h3.patch` | `git diff HEAD~1 HEAD` of that fork — the whole Sail change, 143 lines |
| `/opt/verif/h3formal/spec/lowrisc-vs-upstream.diff` | `git diff 77bd4d5c 81a266b6` over the 4 relevant model files — **the upstream diff, the artifact this gate turns on** |
| `/opt/verif/h3formal/spec/lowrisc-vs-upstream.log` | the 26 fork commits since the upstream merge-base |
| `/opt/verif/h3formal/spec/stub.sv` | edited (2 new externs, misaligned comment rewritten). **Currently holds the FIXED values.** |
| `/opt/verif/h3formal/Makefile` | `LOWRISC_SAIL_RISCV_SRC := $(CURDIR)/sail-riscv-h3` (line 22) so a plain `make` cannot pick up the unpatched nix-store model |
| `/opt/verif/h3formal/check/peek/h3_abs.svh` | 1 new step-0 wire, 4 new step-1 control wires |
| `/opt/verif/h3formal/thm/hazard3.proof` | `MtvecReservedBitHardwired` in step 0; 4 new step-1 controls |
| `/opt/verif/h3formal/goals_bmc_m.sh` | new: `goals_bmc.sh` with the model name as an argument |

**Models on disk** (`L` latches / `B` bads / `C` constraints):

| file | tag | what it is |
|---|---|---|
| `build/all.aig` | `L4690-B110-C6` | **gate 5's model, unchanged** — the `sweepall` job is proving against this |
| `build/core.aig` | `L4690-B111-C6` | rebuilt, fixed harness, no spec |
| `build/fixall.aig` | `L4690-B111-C6` | **the fixed model** (both fixes). Built, NOT yet measured. |
| `build/ctrl.aig` | `L4690-B111-C6` | **the control model** — identical except `spec/stub.sv` reverted |
| `build/neg.aig` | `L4690-B162-C6` | the 51 negative controls |

**`C = 6` on every one of them, i.e. gate 6 has added no assumption.** `L` is
unchanged at 4690; `B` goes 110 → 111 for the one new step-0 property.

---

## 1. (a) The edits made, with justification and attached test

### Edit 1 — `legalize_tvec`, `sail-riscv-h3/model/riscv_sys_regs.sail`

**What.** Reverted lowRISC's `Mk_Mtvec(v[31..8] @ 0x01)` ("256 byte aligned,
always vectored") to **upstream `riscv/sail-riscv`'s own body**, with a
writable-bit mask in front of it:

```sail
function legalize_tvec(o : Mtvec, v : xlenbits) -> Mtvec = {
 let v = Mk_Mtvec((v & sys_tvec_wmask()) | (o.bits & ~(sys_tvec_wmask())));
 match (trapVectorMode_of_bits(v[Mode])) {   // upstream's body, verbatim
   TV_Direct => v, TV_Vector => v, _ => [v with Mode = o[Mode]]
 }
}
```

`sys_tvec_wmask()` is a new `val` extern beside the fork's other `sys_*`
configuration hooks. **It defaults to all-ones, and at all-ones this function
is bit-for-bit upstream.** Hazard3's policy is one setting of a parameter, not
the body of the function.

**Manual clause.** Privileged spec v1.12 §3.1.7, *Machine Trap-Vector
Base-Address Register*: "The `mtvec` register is an MXLEN-bit **WARL**
read/write register"; BASE "must always be aligned on a 4-byte boundary"; MODE
encodings 0 (Direct) and 1 (Vectored) are defined, "≥2" is Reserved. An
implementation may hardwire BASE bits and may hardwire MODE. Ibex's policy and
Hazard3's are therefore *both* legal, and neither belongs in the model's body.

**Upstream evidence** (`spec/lowrisc-vs-upstream.diff`): upstream's
`legalize_tvec` is already the generic WARL legalizer. lowRISC replaced it.
This is a revert, not new semantics.

**Hazard3's setting** (`spec/stub.sv`): `sail_sys_tvec_wmask = 32'hfffffffd` —
this is **Hazard3's own `MTVEC_WMASK` parameter**, `hdl/hazard3_config.vh:253`,
not overridden in `check/h3_core_common.svh`, used at `hazard3_csr.v:295`. It
is the design's configuration constant transcribed, not a number picked to make
a proof pass.

**Tests attached.**
* *Positive, DUT-side, PROVED:* `MtvecReservedBitHardwired`
  (`cpu.core.csr_u.mtvec_reg[1] == 1'b0`) — **PROVED unbounded, IC3, 10.4 s on
  `build/core.aig`**. States over the *stored* bit (not `pre_mtvec`, whose bit 1
  is the abstraction's literal `1'b0`) that the unwritable bit really is
  hardwired, so "unwritable bits keep their previous value" in the model and
  "unwritable bit reads zero" in the DUT are the same function.
* *Load-bearing controls, all MUST FAIL and all DO* (`./neg_check.sh`,
  model `L4690-B162-C6`): `NegMtvecBaseLowZero` CEX@5 (BASE below bit 8 is
  writable ⇒ **not** 256-byte aligned), `NegMtvecModeNeverVectored` CEX@5,
  `NegMtvecModeNeverCleared` CEX@6 (MODE writable in *both* directions ⇒ not
  the constant `0x1`). Had these proved, Ibex's policy would have described
  Hazard3 and there would have been nothing to fix.
* *Goal-level test (RUNNING/PENDING):* `WrapMtvec` must move from CEX@5 to
  no-shallow-CEX on `build/fixall.aig`.
* *Goal-level control (DONE):* on `build/ctrl.aig` (mask reverted to
  `0xffffffff`) `WrapMtvec` is **still CEX** — so the mask *value* is what is
  doing the work, not the fact that the file was touched.

### Edit 2 — `legalize_mcause`, same file (+ one line in `riscv_insts_zicsr.sail`)

**What.** lowRISC *added* this function; **upstream has none at all** — its
`writeCSR` does `mcause.bits = value`. The Ibex internal-interrupt encoding
(smear bits 30..5 to all-ones when `v[31:30] == 0b11`, else all-zeros) is
replaced by the same writable-bit-mask idiom:

```sail
function legalize_mcause(o : Mcause, v : xlenbits) -> Mcause =
  Mk_Mcause((v & sys_mcause_wmask()) | (o.bits & ~(sys_mcause_wmask())))
```

**At the all-ones default this is the identity, i.e. exactly upstream's
`mcause.bits = value`.** `writeCSR` now passes the old value:
`(0x342, _) => { mcause = legalize_mcause(mcause, value); ... }`.

**Manual clause.** Privileged spec v1.12 §3.1.15, *Machine Cause Register*: the
Exception Code "is a **WARL** field, so it is not guaranteed to hold the value
of an illegal exception code"; the register need only represent the causes the
implementation can itself generate. Hardwiring the upper code bits to zero is
legal; so is full writability.

**Hazard3's setting**: `sail_sys_mcause_wmask = 32'h8000000f`, from
`hazard3_csr.v:371` `{mcause_irq, mcause_code} <= {wdata_update[31],
wdata_update[3:0]}`, with the readback at `:836-842` zero-filling bits 30..4.

**Tests attached.**
* *Control, MUST FAIL, DOES:* `NegMcauseNeverCsrWritten` CEX@5 — `mcause` moves
  for a reason other than trap entry, i.e. `legalize_mcause` is actually
  reached and `WrapMcause` is a statement about it rather than dead code.
* *Existing corroboration:* `AbsMcauseIsRdata` (gate 4, still proving) ties
  `pre_mcause = {irq, 27'h0, code}` to the CSR file's own read-data path, which
  is what says bits 30..4 read as zero in the DUT.
* *Goal-level test (PENDING):* `WrapMcause` CEX → no-shallow-CEX on `fixall`.
* *Goal-level control (DONE):* on `ctrl.aig` (mask `0xffffffff`) `WrapMcause`
  is **still CEX**.

### Edit 3 — restore `check_misaligned` in LOAD and STORE, `riscv_insts_base.sail`

**What.** Put back the two call sites upstream has and lowRISC deleted:

```sail
    Ext_DataAddr_OK(paddr) =>
      if   check_misaligned(paddr, width)
      then { handle_mem_exception(paddr, E_Load_Addr_Align()); RETIRE_FAIL }
      else match width_bytes { ... }        // and E_SAMO_Addr_Align for STORE
```

`check_misaligned` itself is **untouched** — it was already
`not(plat_enable_misaligned_access()) & not(is_aligned(vaddr, width))`. No new
semantics were written; a dead flag was reconnected to the code that was always
meant to read it.

**Manual clause.** Unprivileged spec v2.2 §2.6, *Load and Store Instructions*:
misaligned accesses may be supported, or "the misaligned load and store
instructions … **may** raise a load or store address-misaligned exception".
Support is **optional** — exactly what a platform flag is for. Hazard3's
`EXCEPT_LOAD_ALIGN` / `EXCEPT_STORE_ALIGN` is the architecturally correct
response, not a deviation.

**Upstream evidence.** `git log` names the culprit: `b63cba3c` "Extensively
rework memory" deleted the calls as collateral alongside `translateAddr` /
`mem_write_ea`. That is a much narrower claim than "the fork does not support
this", and it is why the fix is three lines.

**Nothing hard-coded to Hazard3.** `sail_plat_enable_misaligned_access` stays 0
in `stub.sv`; setting it to 1 restores Ibex's splitting exactly.

**Checked that the two notions of "misaligned" coincide.**
`hazard3_core.v:613-616` `x_unaligned_addr` is WORD⇒`|addr[1:0]`,
HWORD⇒`addr[0]`, BYTE⇒never; Sail's `is_aligned` (`riscv_insts_base.sail:306`)
is BYTE⇒true, HALF⇒`vaddr[0]==0`, WORD⇒`vaddr[1:0]==0`. Identical case for
case. Causes line up too: `E_Load_Addr_Align` = 4 = `EXCEPT_LOAD_ALIGN`,
`E_SAMO_Addr_Align` = 6 = `EXCEPT_STORE_ALIGN`. Instruction fetch is untouched
(`altFetch` → `mem_read_i`, which never called `check_misaligned` upstream
either, and a straddling 4-byte fetch is legal with C).

**Tests attached.**
* *Goal-level test (PENDING):* `MemNoSecondGranule` must move from CEX
  (depth 5, `sw x31,-1(x31)`) to no-shallow-CEX on `fixall`; `LoadEn` and
  `StoreEn` should move with it — gate 5 traced all three to this one cause.
* *Goal-level control (DONE for `MemNoSecondGranule`):* on `ctrl.aig`
  (`enable_misaligned_access` back to 1) `MemNoSecondGranule` is **still CEX**.
  `LoadEn` / `StoreEn` on `ctrl` were still running when this was written.

### Edit 4 — harness (not the specification)

`check/peek/h3_abs.svh` + `thm/hazard3.proof`: the one step-0 wire and the four
step-1 control wires above. `Makefile`: the `LOWRISC_SAIL_RISCV_SRC` override.
`goals_bmc_m.sh`: `goals_bmc.sh` parameterised by model name, so a fixed and a
control model can be measured without either overwriting `build/all.aig` while
the other is being read.

---

## 2. (b) Edits considered and REJECTED

1. **Write Hazard3's policy straight into `legalize_tvec`** — the form gate 5's
   own handoff suggested (`Mk_Mtvec(v[31..2] @ 0b0 @ v[0])`). **Rejected:** it
   substitutes Hazard3's preference for Ibex's and proves "Hazard3 matches
   Hazard3". The parameterised form keeps *upstream's* behaviour as the default
   and makes Hazard3's choice a configuration value that a property checks.
2. **Plain revert of `legalize_tvec` to upstream with no mask.** **Rejected:**
   upstream is general in BASE but takes one particular WARL option for a
   reserved MODE write (keep the old MODE) and makes bit 1 writable; Hazard3
   hardwires bit 1 to 0. `WrapMtvec` would still fail, and for a legitimate
   reason. The mask is the minimum needed to express both.
3. **Plain revert of `mcause` to upstream (`mcause.bits = value`).**
   **Rejected:** upstream models full writability, which is one legal WARL
   choice, not the general one. Hazard3 implements 4 code bits. `WrapMcause`
   would still fail.
4. **Transcribing Hazard3's `update_nonconst` into a harness property** to
   "prove the WARL policy". **Rejected as tautological** — it reads the same
   wire the RTL reads and restates the same function; it is gate 2's
   CSR-write-enable trap in another dress. Replaced by the split into
   `MtvecReservedBitHardwired` (the hardwired half, over the stored bit) plus
   the three `NegMtvec*` reachability controls (the writable half) plus
   `WrapMtvec` itself.
5. **Guarding the split inside `checked_mem_read`/`checked_mem_write`** instead
   of calling `check_misaligned` in the clauses. **Rejected:** the clause-level
   call is what upstream does, so it is a revert; the deeper guard would be new
   code, and it would also change instruction fetch, which must keep splitting.
6. **Adding Ibex's `assume(~err_i)`**-style shortcuts anywhere. Not considered
   seriously; gate 5's ghost-dropping stands and is strictly weaker.
7. **Raising sweep parallelism above 4** to finish sooner. **Rejected:** gate
   4's OOM rule (`NoMem`/`MemWe` peak 22-23 GB) and gates 3/5's measured
   contention artefacts on `AhbDphWdataStable`.

---

## 3. (c) Genuine-disagreement list — things NOT edited away

**Empty. No Hazard3 bug found, and nothing was edited that could not be
justified from the architecture.** Both defects were on the specification side
and both fixes are reverts toward upstream.

Two things are *recorded rather than fixed*, and neither is a disagreement
between Hazard3 and RISC-V:

* **Reserved `mtvec.MODE` writes are a legal divergence between two
  implementations, not a bug in either.** Upstream Sail keeps the old MODE;
  Hazard3 forces MODE[1] to 0 so a write of `0b10`/`0b11` reads back as
  `0b00`/`0b01`. Both are WARL-legal. This is *why* the mask exists; it is not
  something to fix in either artifact.
* **Sail has no channel on which to be told a bus access faulted** (gate 5
  §3). Untouched here. It is a limitation of the model's memory interface, not
  a disagreement with the architecture, and the harness handles it by dropping
  the ghost rather than assuming faults away.

Open items that are *not* claims about Hazard3: `WrapPc`, `WrapMepc`,
`WrapMstatus` remain refuted and are ordinary missing invariants (gate 6
item 5, the per-instruction template). They are expected to remain refuted
after these fixes — see §4.

---

## 4. (d) What the two running jobs test, and what confirms/refutes the change

### `sweepall` (tmux session `sweepall`, log `/tmp/sweep_all.log`)

`./sweep.sh all 4 2400` on **`build/all.aig`, model `L4690-B110-C6` — gate 5's
model, deliberately not rebuilt**, so this measures exactly what gate 5 left
behind. Results in `/tmp/proof/all-L4690-B110-C6/*.res` (ignore the `*.bmc.res`
files there, which are gate 5's goal runs).

**What it signs off.** Gate 5 ran its regression on `core.aig` only and leaned
on gate 4's projection argument (every step-0 property depends on the
specification only as free input data, so UNSAT on `core.aig` implies UNSAT on
`all.aig`). Gate 4 flagged that argument as "needs sign-off before being leaned
on". This is that sign-off.

* **CONFIRMS** if the tally is **90 PROVED / 0 CEX**. Progress at 21:30 was
  **61/90 done, all PROVED, no CEX**.
* **REFUTES the projection argument** if any property comes back `CEX` on
  `all.aig` that proved on `core.aig`. That would be serious and would
  invalidate every `core.aig`-only result from gates 4-6.
* **Already observed at 21:45: `AhbAphStable` TIMEOUT at 2401 s / 34.8 GB.**
  This is a gate-1 AHB5 master-contract property (gate 3 measured it at 545 s on
  `all.aig` and recorded that it slows ~1.4x under contention). Nothing in
  gates 4-6 is in its cone. **Re-run it alone** before calling the sweep
  complete: `./prove1.sh all AhbAphStable 5400`. Expect the same for
  `AhbDphWdataStable`.
* A `TIMEOUT` is **not** a refutation. `AhbDphWdataStable` is known
  high-variance under contention (gates 3 and 5 both measured it: proves alone
  in ~1935 s, times out under load). If it times out, re-run it **alone**:
  `./prove1.sh all AhbDphWdataStable 3600`.

### `ctrlgoals` (tmux session `ctrlgoals`, log `/tmp/ctrlgoals.log`)

`./goals_bmc_m.sh ctrl 1 25 900 WrapMtvec WrapMcause MemNoSecondGranule LoadEn
StoreEn` on **`build/ctrl.aig`** — the same harness and the same patched Sail
sources as `fixall.aig`, but with `spec/stub.sv` reverted to
`tvec_wmask = 0xffffffff`, `mcause_wmask = 0xffffffff`,
`enable_misaligned_access = 1`.

**This is the load-bearing control for both fixes.** It shows the *values* in
`stub.sv` are doing the work — not the file having been touched, not the
harness changes, not the rebuild.

* **CONFIRMS** if all five are `CEX`. At 21:30: `WrapMtvec` **CEX**,
  `WrapMcause` **CEX**, `MemNoSecondGranule` **CEX**; `LoadEn` and `StoreEn`
  still running.
* **REFUTES** (i.e. the fix is not what made the difference, and the whole
  diagnosis needs redoing) if any of the five comes back `NO-CEX` on the
  control.

One control build covers both defects because they are on **disjoint paths**:
gate 5's `WrapMtvec` counterexample is a `csrrci` to `0x305` with no memory
operation, and its `MemNoSecondGranule` counterexample is `sw x31,-1(x31)` with
no CSR access.

### What has NOT been measured yet — the missing half

**`build/fixall.aig` is built but not measured.** Nothing yet confirms the
fixes *work*; only that reverting them breaks things. That is the single
outstanding piece of evidence.

---

## 5. (e) The single next action for whoever resumes

**Run the fixed model's goals:**

```
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
cd /opt/verif/h3formal
nix develop /opt/verif/ibex#oss-dev --command bash -c \
  './goals_bmc_m.sh fixall 4 25 900'
```

…but **only once `sweepall` has finished** — `NoMem`/`MemWe` peak at 22-23 GB
each and gate 4's "at most four spec-connected proofs at a time" rule must not
be relaxed on this 123 GB box. Results land in
`/tmp/proof/fixall-L4690-B111-C6/*.bmc.res`. Expect ~50-70 min.

**The verdict to read off it**, against gate 5's nine refutations:

| Goal | gate 5 | expected now | why |
|---|---|---|---|
| `WrapMtvec` | CEX@5 | **no shallow CEX** | fix 1 |
| `WrapMcause` | CEX | **no shallow CEX** | fix 1 |
| `MemNoSecondGranule` | CEX | **no shallow CEX** | fix 2 |
| `LoadEn` | CEX | **no shallow CEX** | fix 2 (same root cause) |
| `StoreEn` | CEX | **no shallow CEX** | fix 2 (same root cause) |
| `WrapPc`, `WrapMepc`, `WrapMstatus` | CEX | **still CEX** | ordinary missing invariants — the per-instruction template, gate 6 item 5. Not a spec-config problem, and no spec edit should make them move. |
| `SpecEnUnreach` | CEX | **still CEX** | gate 5 §3: `mem_read_i` is a PMP/alignment check only, so `MAIN_IFERR` always yields `MAINRES_NOIFERR`. `SpecEnUnreachIdex` is the claimable form. |

**If `WrapMtvec` or `WrapMcause` is still CEX at depth 5, stop** — gate 5's
diagnosis in §8c is wrong and everything built on it needs revisiting. Read the
trace with `./cex.sh`.

Then, in order: (2) `./sweep.sh core 4 2400` — expect **91/91** (the 90 from
gate 5 plus `MtvecReservedBitHardwired`); re-run `AhbDphWdataStable` alone if it
times out. (3) `cp build/fixall.aig build/all.aig` and likewise `.ywmap`/`.vmap`
— or just `make build/all.aig` — then `make check-env` (must PASS) before
anything is reported as final. (4) Fold `/tmp/…` results and the draft in this
file into `BRINGUP.md` as a "Spec configuration fixes" section. (5) Mirror
`spec/`, `check/peek/h3_abs.svh`, `thm/hazard3.proof`, `Makefile`,
`goals_bmc_m.sh` and the patch files to
`/Users/leostrijbos/Desktop/Code/Sandbox/verif/hazard3/`.

### Results already banked (do not re-run)

* **`./neg_check.sh`: 51 / 51 negative controls FAIL as required**, model
  `L4690-B162-C6` — the 47 from gate 5 plus the four new ones
  (`NegMtvecBaseLowZero` 5, `NegMtvecModeNeverVectored` 5,
  `NegMtvecModeNeverCleared` 6, `NegMcauseNeverCsrWritten` 5).
* **`MtvecReservedBitHardwired` PROVED unbounded**, 10.4 s, `core.aig`
  `L4690-B111-C6`.
* **`C = 6` on core / fixall / ctrl / neg** — gate 6 adds **no** assumption.
  The assumption list is unchanged from gate 5's five:
  1. AHB5 slave assumptions, `MAX_BUS_STALL = -1`.
  2. Debug port tied off (`DEBUG_SUPPORT = 0`).
  3. `mhartid_val` / `eco_version` constant (structural, not an `assume`).
  4. Liveness absent by choice.
  5. `MemRdataIsSpecData` (the one `assume`, `C` 5→6 at gate 5).
  The two WARL masks and `plat_enable_misaligned_access` are **configuration of
  the specification, not assumptions about the DUT**: they narrow what the
  *model* does, and each is checked against the DUT by a property rather than
  asserted about it. They belong in the "coverage narrowings, on the record"
  list, not the assumption list.
