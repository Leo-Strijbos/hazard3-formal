# Hazard3 formal bring-up

Status: **two models, a real bus environment, the free-signal question settled, an
abstraction function prototyped on `mepc`, and 26 proved properties.**

`/opt/verif/h3formal` builds two AIGER models of the same Hazard3 core in the same
environment:

| | `build/core.aig` (**model A**) | `build/all.aig` (**model B**) |
|---|---|---|
| contents | core + AHB5 bus environment | core + AHB5 bus environment + Sail reference model |
| top level | `check/h3_core_top.sv` | `check/h3_top.sv` |
| properties | `thm/hazard3.proof` (identical set) | `thm/hazard3.proof` (identical set) |
| build | `make build/core.aig` | `make build/all.aig` |

Both include `check/h3_core_common.svh` — the core, the bus environment and all
property support wires — *textually and identically*. That is the mechanism that
makes a core-only lemma proved on A meaningful on B. `make check-env` checks it
mechanically.

`check/peek/h3_abs.svh` is the abstraction function, so far covering one register
(`mepc`). There is still no pipeline follower, no IRQ environment and no
connection between the core and the spec.

---

## How to rebuild

```sh
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
cd /opt/verif/h3formal
nix develop /opt/verif/ibex#oss-dev --command bash -c 'make build/core.aig'   # ~35 s
nix develop /opt/verif/ibex#oss-dev --command bash -c 'make build/all.aig'    # ~16 min
```

First time only (already done on this box, all cached in `build/`):

```sh
nix develop /opt/verif/ibex#oss-dev --command bash -c 'make build/yosys_formal.so build/aig-manip'
nix develop /opt/verif/ibex#oss-dev --command bash -c 'make build/spec.il'    # ~7 min, stage A
```

`build/ibexspec.sv` (the Sail model compiled to SystemVerilog) is **not** rebuilt: it is
correct for Hazard3 as-is (same RV32IMC+Zicsr ISA) and takes ~20 min to regenerate.
`build/spec.il` is the lowered form of it, cached so that a harness edit does not repeat
the expensive `proc`/`opt_muxtree_2` of the specification.

**Iterate on `build/core.aig`.** A harness edit costs 35 s there and 16 min on
`build/all.aig`, and (see "Does the small model pay?") the two solve at the same speed,
so there is no reason to wait for the big one until the property set is settled.

## How to prove

```sh
./prove1.sh core FetchAligned          # one property, one model
./sweep.sh  core 4 1800                # every step-0 property, 4 at a time, 1800 s each
./sweep.sh  all  4 3600
```

Both write `/tmp/proof/<model>-<prop>.{sel,log,time,res}`. Under the hood:

```sh
build/aig-manip build/core.aig select build/sel.aig build/core.ywmap 0 FetchAligned
rIC3 build/sel.aig
```

Exit code 20 = UNSAT = proved, 10 = SAT = counterexample. `aig-manip select` *deletes*
every other property in the same step, so each property is proved in isolation.

To turn a counterexample into a waveform:

```sh
rIC3 -e bmc --witness build/sel/core-Foo.aig > /tmp/cex.aiw     # strip the RESULT: line
build/aig-manip build/core.aig simulate build/core.ywmap build/core.vmap /tmp/cex.aiw /tmp/cex.vcd
python3 vcdtab.py /tmp/cex.vcd top.htrans,top.hready,top.hresp,top.hwdata
```

---

## The bus environment

`check/h3_core_common.svh` instantiates Hazard3's own AHB-Lite slave assumptions
**verbatim** from `hazard3/test/formal/common/ahbl_slave_assumptions.v`, wired exactly as
the core's author wires them in `hazard3/test/formal/bus_compliance_1port/tb.v:159-179`
(note `dst_hready_resp` and `dst_hready` both come from the single `hready`: one slave, no
HREADY mux). Nothing in `/opt/verif/hazard3` is modified.

```
MAX_BUS_STALL = -1   -- stalls are UNBOUNDED
```

Leave it that way. Any value `>= 0` is a fairness assumption that weakens every proof made
against the model, and none of the 20 properties needed it.

The companion `ahbl_master_assertions.v` is the harness self-check, and it is
**transcribed** rather than instantiated, into `check/h3_ahbl_master_props.sv`. Two
changes, no others:

1. Each `assert(X)` becomes a combinational output `ok_*` (the implication
   *guard → body*), so psgen can name it. Raw `assert()` cells cannot be used: every
   AIGER bad state must carry a psgen `StepN_Name` label, and `aig-manip select` asserts
   a 1:1 correspondence between bads and ywmap entries.
2. `$past`/`$stable` become explicit `past_*` registers, because an output has to be
   combinational.

The original line numbers are quoted against each property in that file.

`sbus_assumptions.v` is **not** used, and the debug port is tied off instead — see
"Surprises" 8 and 9.

### Environment summary

| core input | in the model |
|---|---|
| `hready`, `hresp` | free, constrained by `ahbl_slave_assumptions` |
| `hrdata`, `hexokay` | free, unconstrained (data, not protocol; `EXTENSION_A=0`) |
| `irq`, `soft_irq`, `timer_irq` | free — the IRQ environment is a later gate |
| `fence_rdy`, `unblock_in`, `pwrup_ack` | free |
| `mhartid_val`, `eco_version` | **arbitrary but constant** — sampled once at reset, no `assume` (gate 2) |
| all `dbg_*` | **tied to 0** (`DEBUG_SUPPORT=0`, no debug module attached) |

---

## The properties

`thm/hazard3.proof`. **Forty-one in step 0**, all proved on both models;
**thirteen** in the commented-out step 1, all of which must fail.  (Twenty-six
and four of those are gates 1-2; the rest arrived with gate 3's commit point --
see "Gate 3: the commit point" below for what each one says and why.)

### Step 0 — the AHB5 master contract (gate 1)

| Property | Statement | Original |
|---|---|---|
| `AhbAphAligned` | transfer is naturally aligned | `ahbl_master_assertions.v:63` |
| `AhbAphSize` | `HSIZE` fits the bus width | `:65` |
| `AhbAphStable` | a stalled, non-errored request is held unchanged | `:67-77` |
| `AhbSeqAfterActive` | `SEQ` only follows an active transfer | `:79-80` |
| `AhbSeqAddr` | `SEQ` address is sequential | `:83-84` |
| `AhbExclNoPipeline` | exclusive transfers are not pipelined | `:86-87` |
| `AhbDphWdataStable` | write data held for the whole write data phase | `:93-94` |

| `AhbDphExclReserved` | exclusive write needs a prior `HEXOKAY` read | `:96-97` |

All eight hold. With Hazard3's own slave assumptions in place, the core never violates the
AHB5 master contract.

### Step 0 — core-only lemmas (gate 2)

Every one mentions only signals inside `cpu`. Most restate an assertion the core's author
wrote under `` `ifdef HAZARD3_ASSERTIONS ``, which this flow does *not* compile.

| Property | Statement | RTL |
|---|---|---|
| `Trivial` | `1'b1` | — |
| `FetchAligned` | `frontend.fetch_addr[1:0] == 0` | `hazard3_frontend.v:326-350` |
| `PendingFetchesBound` | at most 2 fetches in flight | `hazard3_frontend.v:447` |
| `FlushLePending` | `ctr_flush_pending <= pending_fetches` | `hazard3_frontend.v:446` |
| `DataVldHasPending` | fetch data only arrives for an issued fetch | `hazard3_frontend.v:448` |
| `CirVldBounded` | `cir_vld <= 2` | `hazard3_frontend.v:674` |
| `BypassSel1Legal` | `x_rs1_select_regs_xm_mw` ∈ {000,001,010,100} | `hazard3_core.v:536-543` |
| `BypassSel2Legal` | ditto for rs2 | `hazard3_core.v:536-543` |
| `BusDphMutex` | at most one of `bus_active_dph_{i,d,s}` | `hazard3_cpu_1port.v:228-248` |
| `PowerStateAwake` | `power_ctrl.state == S_AWAKE` (`EXTENSION_XH3POWER=0`) | `hazard3_csr.v:497-505`, `hazard3_power_ctrl.v:85` |
| `MuldivBusyHasOp` | `x_stall_muldiv -> d_aluop == ALUOP_MULDIV` | `hazard3_core.v:892` |
| `DcsrDebugBitsZero` | `dcsr.{step,ebreakm,ebreaku}` are 0 (`DEBUG_SUPPORT=0`) | `hazard3_csr.v:684-688` |

`DataVldHasPending` is the only one that genuinely depends on the bus environment
(`mem_data_vld` is `bus_active_dph_i && hready`).

### Step 0 — the abstraction function and the tie-off regression (gate 2)

| Property | Statement | Notes |
|---|---|---|
| `AmoPhaseZero` | `cpu.core.x_amo_phase == 0` | was step 1 (SAT at depth 1) until the gate-2 tie-off |
| `DebugModeZero` | `!cpu.core.csr_u.debug_mode` | ditto; **this one was not inert** |
| `CsrIrqAlias` | `cpu.core.csr_u.irq{,_software,_timer}` are the top-level inputs | flattening sanity check |
| `MepcStableBetweenCommits` | `pre_mepc` unchanged on non-commit cycles | `check/peek/h3_abs.svh` |
| `MepcChangeHasCause` | `pre_mepc` moves only for a trap entry or a retiring CSR write to `0x341` | ditto |
| `MepcAligned` | `pre_mepc[0] == 0` | ditto |

### Step 0 — the commit point (gate 3)

`check/peek/h3_commit.svh`.  Full justification in "Gate 3: the commit point".

| Property | Statement |
|---|---|
| `XAdvanceIsNoStall` | `\|df_cir_use == !(x_stall \|\| d_starved)` (uop / lspair terms dead here) |
| `NoRefetchException` | `EXCEPT_REFETCH` is unreachable in this configuration |
| `XProgressMatchesMonitor` | our pipe-register form of "a real instruction enters M" == the monitor's |
| `MValidAgreesRvfi` | `h3_m_valid == cpu.core.rvfm_m_valid` |
| `RetireAgreesRvfiValid` | `rvfi_valid == $past(h3_retire)` — agreement with the core author's definition |
| `RvfiTrapExcludesMret` | a retiring MRET is reported valid and **not** trapped |
| `RegWriteAtRetire` | the register file is written only on a retire cycle |
| `PcChangeHasCommit` | the architectural PC moves only after an X→M handoff or a trap handshake |
| `PcChangeHasArchCommit` | …and REFETCH is not needed in that list |
| `McauseChangeHasCause` | `mcause` moves only for a trap **entry** or a retiring write to `0x342` |
| `MstatusMieChangeHasCause` | `mstatus.MIE` moves only for a trap entry, an MRET, or a retiring write to `0x300` |
| `ExceptionSuppressesWrite` | an exception trap suppresses the M instruction's register write |
| `ExceptionTrapRetires` | an exception trap coincides with the M→W crossing of the instruction that raised it |
| `TrapExitRetires` | an MRET commits its effects on the cycle it retires |
| `TrapKindsPartition` | a trap handshake is exactly one of entry / exit / refetch |

### Step 1 — properties that must FAIL

Commented out by default, so `make` yields a model in which every property is provable.
Uncomment the block, rebuild, then `aig-manip ... select ... 1 <Name>` and
`rIC3 -e bmc`, expecting `RESULT: SAT`.

* `NegControl` — non-vacuity: `~fetch_addr[2]`. Proves `rst_ni` really does deassert, so
  the `disable iff (~rst_ni)` properties are not vacuous.
* `NegMepcNeverMoves`, `NegMepcOnlyTrap`, `NegMepcOnlyCsr` — the non-vacuity controls for
  `MepcChangeHasCause`; each is that property with one term deleted.
* `NegNeverRetire`, `NegNeverRvfiValid`, `NegNeverRegWrite`, `NegNeverTrapEntry`,
  `NegNeverIrqTrap`, `NegNeverExcTrap`, `NegNeverTrapExit` — gate 3's non-vacuity
  controls, one per commit event.
* `NegRetireTrapExclusive` — retire and trap entry are **not** mutually exclusive.
* `NegNestedTrapAssume` — the RVFI monitor did not drag in riscv-formal's
  "no nested exceptions" assumption.

  See "Gate 3: the commit point" for the depths and for what each failure buys.

`./neg_check.sh` runs all four against a throwaway `build/neg.aig` and puts the shipped
models back; measured `rIC3 -e bmc` results:

```
NegControl        -> RESULT: SAT, counter-example at depth 3
NegMepcNeverMoves -> RESULT: SAT, counter-example at depth 5
NegMepcOnlyTrap   -> RESULT: SAT, counter-example at depth 5
NegMepcOnlyCsr    -> RESULT: SAT, counter-example at depth 7
```

`AmoPhaseZero` and `DebugModeZero` used to live here, failing at depth 1 — the signature
of a register with no next-state function. Gate 2 fixed the model; they are step-0
properties now. See "Free state" below.

## Free state: registers that `setundef -undriven -anyseq` makes into free inputs

> **RESOLVED AT GATE 2 — see "Gate 2: free signals and the abstraction function".**
> The four `cpu.*` registers below are now driven to their inert constants by
> `h3_tieoff_undriven.ys`, and `mhartid_val`/`eco_version` are sampled once at
> reset. No assumption was added. The section below is kept because it explains
> the mechanism, which will bite again the next time a parameter is changed:
> **run `./probe_undriven.sh` after every configuration change.**

**This is the most important thing in this document for whoever writes the next gate.**

Hazard3 disables configuration-dependent logic with `else if (PARAMETER)` rather than with
`generate`. When the parameter is 0, the register's update branch is constant-false,
yosys leaves the register with *no driver at all*, and `setundef -undriven -anyseq` in the
build script then turns it into a **free signal the solver may choose afresh every cycle**
— not a constant, and not even a latch. `build/core.vmap` shows it: such a signal has
`wire`/`output` entries but no `latch` and no `init`.

The complete list for this configuration (from `./probe_undriven.sh`, which runs the build
up to `setundef` and then `check`):

| Undriven wire | Why | Intended? |
|---|---|---|
| `cpu.core.x_amo_phase` [3] | `EXTENSION_A=0` kills the update guard, `hazard3_core.v:645` | **no** |
| `cpu.core.csr_u.debug_mode` | `else if (DEBUG_SUPPORT)`, `hazard3_csr.v:165` | **no** |
| `cpu.core.csr_u.dbg_req_resume_prev` | `else if (DEBUG_SUPPORT)`, `hazard3_csr.v:1321` | **no** |
| `cpu.core.csr_u.pending_dbg_resume_prev` | ditto | **no** |
| `cpu.core.fence_rdy`, `csr_u.irq{,_software,_timer}`, `frontend.mem_data`, `power_ctrl.pwrup_ack`, `power_ctrl.block_wakeup_req_pulse`, `mhartid_val`, `eco_version`, `ahbl_master_props_i.src_h{ready,resp,exokay}` | genuine free top-level inputs | yes |

`AmoPhaseZero` and `DebugModeZero` in step 1 are the mechanical record of the first two.

Both are *currently* harmless — almost every consumer is separately gated by
`|EXTENSION_A` / `DEBUG_SUPPORT` — with one exception worth checking before it bites:
`hazard3_core.v:967` reads `debug_mode` **ungated**

```verilog
assign x_loadstore_pmp_fail = x_loadstore_pmp_badperm && x_memop_vld && !debug_mode;
```

which is only safe because `PMP_REGIONS=0` forces `x_loadstore_pmp_badperm` to 0.

The Ibex harness handles exactly this with an assumption
(`check/top.sv:188`, `NotDebug: assume property (!...debug_mode & !debug_req_i)`). The
Hazard3 equivalent would be `assume(!cpu.core.csr_u.debug_mode)`. It is **not** added here,
because adding an assumption is a soundness decision that should be taken deliberately and
recorded, not slipped in during a bring-up gate.

Note the contrast with Ibex, where `dcsr_step`/`dcsr_ebreakm`/`dcsr_ebreaku` were the free
bits the solver exploited: **Hazard3's are hard constants** (`DcsrDebugBitsZero` proves in
10.7 s), because their write data is masked with `{3{|DEBUG_SUPPORT}}` rather than their
write branch being removed. The hole moved one level up, to `debug_mode` itself.

---

## Negative control for the bus environment

To check that the slave assumptions actually constrain something, `make_broken.py` writes
two deliberately broken copies into `build/broken-*/` (the originals are never touched) and
`./build_broken.sh <name>` rebuilds the core-only model against them.

### break1 — delete the "correct two-phase error response" rule → **caught**

`AhbDphWdataStable` fails, CEX at BMC depth 10:

```
   t | htrans | hwrite | hready | hresp | hwdata
   7 |     10 |      1 |      1 |     0 |  ...   <- write address phase accepted
   8 |     10 |      0 |      0 |     1 |  01540640  <- first error cycle (legal)
   9 |     10 |      0 |      0 |     0 |  01540640  <- ILLEGAL: hresp dropped mid-error
  10 |     10 |      0 |      0 |     1 |  c0000c82  <- hwdata changed, dphase still open
```

At t=8 the core sees `core_dph_err_d = bus_active_dph_d && hresp`, takes the bus fault and
releases the store — but the slave never terminated the transfer (`hready` is still 0), so
at t=10 the master changes `HWDATA` in the middle of its own write data phase. This is
precisely the behaviour `hazard3_cpu_1port.v:328-330` says the core relies on the two-phase
error response for. Assumption restored; the property proves again in 212 s.

### break2 — delete the "idle slave holds HREADY high, HRESP low" rule → not caught, but visible

No property fails: the core filters spurious responses through its own
`bus_active_dph_*` tracking. What *does* change is dramatic, and worth recording, because
it shows which assumptions carry the coupling between bus and core. rIC3's constraint cone:

| | `Trivial` on the good model | on break2 |
|---|---|---|
| clauses after simplification | 1 127 621 → 286 152 | 64 → 31 |
| wall time | 10.2 s | 1.5 s |

Those two `assume`s are the only ones that make `hready`/`hresp` depend on core state at
all; without them the whole design drops out of the constraint cone.

---

## Does the small model pay? (gate 2 measurement)

Each property proved alone, rIC3, four concurrent single-threaded jobs, 16 vCPU / 123 GB.

| Property | A `core.aig` time | A mem | B `all.aig` time | B mem | verdict |
|---|---|---|---|---|---|
| `Trivial` | 9.4 s | 1.35 GB | 11.4 s | 2.34 GB | both PROVED |
| `AhbAphAligned` | 44.0 s | 1.36 GB | 56.4 s | 2.35 GB | both PROVED |
| `AhbAphSize` | 9.7 s | 1.35 GB | 11.1 s | 2.34 GB | both PROVED |
| `AhbAphStable` | 545.3 s | 2.65 GB | 706.4 s | 3.83 GB | both PROVED |
| `AhbSeqAfterActive` | 9.5 s | 1.35 GB | 11.1 s | 2.34 GB | both PROVED |
| `AhbSeqAddr` | 10.0 s | 1.36 GB | 11.7 s | 2.35 GB | both PROVED |
| `AhbExclNoPipeline` | 9.6 s | 1.36 GB | 11.1 s | 2.34 GB | both PROVED |
| `AhbDphWdataStable` | 184.7 s | 1.36 GB | 178.2 s | 2.34 GB | both PROVED |
| `AhbDphExclReserved` | 9.6 s | 1.35 GB | 11.0 s | 2.34 GB | both PROVED |
| `FetchAligned` | 9.7 s | 1.35 GB | 10.9 s | 2.34 GB | both PROVED |
| `PendingFetchesBound` | 10.2 s | 1.36 GB | 11.3 s | 2.34 GB | both PROVED |
| `FlushLePending` | 10.0 s | 1.35 GB | 12.0 s | 2.35 GB | both PROVED |
| `DataVldHasPending` | 9.9 s | 1.35 GB | 11.8 s | 2.34 GB | both PROVED |
| `CirVldBounded` | 9.6 s | 1.35 GB | 10.8 s | 2.34 GB | both PROVED |
| `BypassSel1Legal` | 9.2 s | 1.35 GB | 10.8 s | 2.34 GB | both PROVED |
| `BypassSel2Legal` | 9.2 s | 1.35 GB | 10.7 s | 2.34 GB | both PROVED |
| `BusDphMutex` | 9.3 s | 1.35 GB | 10.8 s | 2.34 GB | both PROVED |
| `PowerStateAwake` | 11.5 s | 1.35 GB | 11.9 s | 2.34 GB | both PROVED |
| `MuldivBusyHasOp` | 9.6 s | 1.35 GB | 11.4 s | 2.34 GB | both PROVED |
| `DcsrDebugBitsZero` | 9.3 s | 1.35 GB | 10.3 s | 2.34 GB | both PROVED |
| **total** | **939 s** | | **1131 s** | | |
| `AmoPhaseZero` (step 1) | 10.5 s | 1.36 GB | 11.8 s | 2.34 GB | both CEX |

**Every verdict agrees.** No property proves on one model and not the other.

### Build cost

| | model A `core.aig` | model B `all.aig` |
|---|---|---|
| build wall | **0:35** | 15:46 (+ 7:13 one-off for `build/spec.il`) |
| build peak RSS | **2.10 GB** | 31.53 GB (16.14 GB for `build/spec.il`) |
| AIGER `M I L O A B C` | `655564 34407 2034 10097 619123 20 5` | `12452582 1847882 2034 59184 10602666 20 5` |
| file size | 2.5 MB | 45 MB |

### Verdict: **no, not 10x on solving. The plan reverts to one model for proofs — but keep model A as the development model.**

Summed over the twenty properties, model A takes **939 s** and model B **1131 s**: model A is
**1.20x** faster. Peak memory is 2.65 GB against 3.83 GB (**1.45x**) on the worst property and
1.35 GB against 2.34 GB (**1.73x**) on a typical one. Nowhere near 10x, on either axis.
On the second-most expensive property, `AhbDphWdataStable`, model B is 4% **faster**.

The reason is worth writing down, because it invalidates the premise the two-model idea
rested on. rIC3 discards the specification *before it builds a transition system at all*:

```
core.aig, FetchAligned:  origin ts has 634737 vars, 34189 inputs, 2034 latches, 1139061 clauses
all.aig,  FetchAligned:  origin ts has 634737 vars, 34189 inputs, 2034 latches, 1139061 clauses
```

Identical. The 10.6 M AND gates of the Sail interpreter are structurally unreachable from a
core-only property's cone and from the five bus constraints, so the AIGER reader drops
them. The entire cost of carrying the specification is parsing a 45 MB file instead of a
2.5 MB one: about 2 seconds and about 1 GB of peak RSS, flat, per property. That is a
constant, not a multiplier — which is why the gap *shrinks* in relative terms on the
expensive properties (`AhbDphWdataStable` is actually 11% **faster** on the full model).

The Ibex experience that motivated the split ("5-30 GB and minutes per property") is
therefore not about carrying the interpreter; it is about Ibex's harness having the spec
*connected* to the core, which puts the interpreter inside the cone of every property.
That will become true here too once the abstraction function and follower land. **Re-run
this measurement at that point** — the answer may legitimately flip, and it will flip for
a different reason than the plan assumed.

What model A *does* buy, and it is not small: **27x on build time and 15x on build
memory**. `check/h3_core_common.svh` edit → 35 s instead of 16 minutes. That changes
harness development from batch to interactive, which was the actual goal. Keep both
models; use A to develop and B to prove.

### Soundness check

A lemma proved on A is only usable on B if the core's environment is identical in both.

* **Structural:** there is one environment file. `check/h3_core_common.svh` contains the
  reset, every core input, the `hazard3_cpu_1port` instance and its 33 parameters, the
  `ahbl_slave_assumptions` instance (`MAX_BUS_STALL = -1`), the `h3_ahbl_master_props`
  instance and every property support wire. `check/h3_top.sv` and
  `check/h3_core_top.sv` each `` `include `` it and add nothing core-side; the only
  difference between the two files is the `spec_api` instance.
* **Mechanical:** `make check-env` (`./check_env.sh`) compares the exposed signal names
  under `cpu.*`, `ahbl_slave_assumptions_i.*`, `ahbl_master_props_i.*` and the top-level
  bus/IRQ/debug wires in `build/all.vmap` and `build/core.vmap`, and fails if they differ.
* **Observed:** both models report `L = 2034` latches, `B = 20` bad states and
  `C = 5` constraints, and rIC3 reports byte-identical `origin ts` statistics.

**Differences found: none.** The only signals present in B and absent from A are
`spec_api_i.*` and the `spec_*` wires in `check/h3_top.sv`, none of which is connected to
the core, to the bus or to any property.

---

## What was added / changed, and why

Everything is in `/opt/verif/h3formal`. **Nothing in `/opt/verif/hazard3` was modified.**

### New files

| File | Purpose |
|---|---|
| `check/h3_core_common.svh` | The core and its environment. Included identically by both tops. |
| `check/h3_core_top.sv` | Model A top: `` `include `` the common file + the psgen properties. |
| `check/h3_top.sv` | Model B top: the same, plus the `spec_api` instance. |
| `check/h3_ahbl_master_props.sv` | AHB5 master contract, transcribed from Hazard3's `ahbl_master_assertions.v`. |
| `build_h3_core.ys` | Yosys script for model A. |
| `check_env.sh` | The mechanical soundness check (`make check-env`). |
| `fix_ywmap.py` | ywmap format fixup, see Surprises 10. |
| `prove1.sh`, `sweep.sh` | Prove one property / every property, with time and peak RSS. |
| `make_broken.py`, `build_broken.sh` | Gate-1 negative control. |
| `probe_undriven.sh` | Lists the wires `setundef -undriven -anyseq` will make free. |
| `check/peek/h3_abs.svh` | The abstraction function (gate 2). `pre_mepc` + the commit-point wires. |
| `h3_tieoff_undriven.ys` | Drives the four configured-away registers to their inert constants, before `setundef`. Run by all three Hazard3 build scripts. |
| `patch_hazard3_rtl.sh` | Patches the *copy* of the Hazard3 RTL in `build/hazard3-rtl`. |

### Makefile

* `AHBL_SLAVE_ASSUMPTIONS ?= $(HAZARD3_ROOT)/test/formal/common/ahbl_slave_assumptions.v`
  — override it to point at a broken copy for the negative control.
* `H3_HARNESS_SRCS` — the shared core/environment sources, a dependency of every model.
* `build/core.aig`, `build/build_h3_core.ys`, `.PHONY: core`, `.PHONY: check-env`.
* `build/all.aig` and `build/mono-all.aig` now run `fix_ywmap.py` after yosys.
* The split build (stage A `build/spec.il` + stage B) predates this work and is unchanged.
  A pristine copy of the original Ibex Makefile is at `Makefile.ibex.orig`.

### Target configuration

Set explicitly on the `hazard3_cpu_1port` instance in `check/h3_core_common.svh`:

```
RESET_VECTOR=0, MTVEC_INIT=0,
EXTENSION_A=0,  <-- defaults to 1 upstream, must be zeroed
EXTENSION_C=1, EXTENSION_M=1, EXTENSION_E=0,
EXTENSION_ZB*=0, EXTENSION_ZC*=0, EXTENSION_ZIFENCEI=0, EXTENSION_ZILSD=0,
EXTENSION_XH3BEXTM/XH3IRQ/XH3PMPM/XH3POWER=0,
CSR_M_MANDATORY=1, CSR_M_TRAP=1, CSR_COUNTER=0,
U_MODE=0, PMP_REGIONS=0, DEBUG_SUPPORT=0, BREAKPOINT_TRIGGERS=0,
NUM_IRQS=1, IRQ_PRIORITY_BITS=0,
REDUCED_BYPASS=0, MULDIV_UNROLL=1, MUL_FAST=0, MUL_FASTER=0, MULH_FAST=0,
FAST_BRANCHCMP=1, BRANCH_PREDICTOR=0, RESET_REGFILE=0
```

All parameter names verified against `hdl/hazard3_config.vh`.

---

## Surprises / things that bit

1. **Verilog-2005 static functions cause "Found multiple drivers".**
   `hazard3_csr.v`'s `update_nonconst` is a plain (static) Verilog function called from two
   different `always` blocks. Its argument variables are therefore one piece of shared state
   with two drivers, and yosys aborts in `write_smt2`.
   Fix: `patch_hazard3_rtl.sh` rewrites `function [` to `function automatic [` in the copy
   of `hazard3_csr.v` and `hazard3_instr_decompress.v` (4 functions). **This is the only RTL
   change**, and it is applied to a copy.

2. **`-DYOSYS` leaves `` `default_nettype none `` in force.**
   Every Hazard3 file ends with `` `ifndef YOSYS / `default_nettype wire / `endif ``, and
   the flow passes `-DYOSYS`. With `--single-unit` the `none` setting leaks into whatever is
   compiled after the Hazard3 files. Handled by listing the Hazard3 filelist *last* in
   `read_slang` and putting `` `default_nettype wire `` at the top of both tops and of
   `check/h3_ahbl_master_props.sv`.

3. **yosys-slang segfaults on `always assume(expr);`** — a bare `always` with an immediate
   assumption and no event control. That is the only construct in
   `hazard3/test/formal/common/sbus_assumptions.v` (lines 29, 30, 33), which is why that
   file is not used here. `$past` and `$stable` in ordinary procedural code are fine, which
   is why `ahbl_slave_assumptions.v` *can* be instantiated verbatim. No error message; exit
   139 from the SLANG frontend.

4. **Async reset was a non-issue.** Hazard3 uses `always @(posedge clk or negedge rst_n)`
   throughout. The Ibex trick of `initial rst_ni = 1'b0; always @(posedge clk_i) rst_ni = 1'b1;`
   plus `dffunmap` works fine. (But see "Free state" for what happens when the *non*-reset
   branch is configured away.)

5. **yosys-slang flattens.** It elaborates the whole hierarchy into one `top` module, which
   is why signals are named `cpu.core.frontend.fetch_addr` and why `build_h3_core.ys` needs
   no `flatten`. `build_h3_fast.ys`'s `flatten` exists only to merge in the separately-read
   `build/spec.il`.

6. **`opt_muxtree_2` is the wall-clock bottleneck of the full build**, and it is there for
   the Sail model, not the core. This is the whole reason model A builds in 35 s.

7. **The split build did not speed up model B.** Stage B alone took 15:41, about what the
   monolithic build took, despite `build/spec.il` being cached. Caching stage A saves the
   7:13 of specification lowering only if stage B is not itself dominated by re-optimising
   the merged design. Worth revisiting; it is why the "iterate on model A" advice above
   matters.

8. **`hazard3_cpu_1port` arbitrates the debug system bus with no `DEBUG_SUPPORT` guard**
   (`hdl/hazard3_cpu_1port.v:232`). Leaving `dbg_sbus_*` free therefore puts a completely
   unconstrained *second* master on the AHB port, and `AhbAphAligned`/`AhbDphWdataStable`
   fail immediately for reasons that have nothing to do with the core (the address, size and
   write data are free inputs). With `DEBUG_SUPPORT=0` there is no debug module, so the
   port is tied off in `check/h3_core_common.svh`. The alternative would have been the
   author's `sbus_assumptions.v` — see Surprises 3.

9. **`hexcl`/`hexokay` exist even with `EXTENSION_A=0`.** `hexcl` is driven to 0 by the
   arbiter, `hexokay` is left free and unconstrained; `AhbExclNoPipeline` and
   `AhbDphExclReserved` prove anyway.

10. **`aig-manip` cannot parse the split build's ywmap.** `YWWire.path` is typed
    `[String; 1]`, but `flatten` makes yosys emit two-element paths such as
    `["\\spec_api_i", "\\regs_i"]`, and serde reports it as a misleading
    `"trailing characters"` error at an unrelated line. `fix_ywmap.py` joins multi-element
    paths with `.`, which reproduces exactly the name the monolithic build produces. The
    monolithic build never hit this because slang elaborates `spec_api` straight into `top`.

11. **Iteration cost.** psgen-only edits (proof text) are ~1 s plus the model rebuild.
    `check/h3_core_common.svh` edits are 35 s on model A, 16 min on model B.

---

---

## Gate 2: free signals and the abstraction function

Two things landed here. The first is a soundness decision about the free
signals gate 1 found; the second is the abstraction function itself, prototyped
on `mepc`.

### Part 1 — the free signals: what was decided, and why

Gate 1 found that `setundef -undriven -anyseq` turns four *registers* into free
signals the solver re-chooses every cycle. An audit of every read site in the
configured design produced this verdict:

| Signal | Genuinely inert? | Decision |
|---|---|---|
| `cpu.core.csr_u.debug_mode` | **NO** | (c) drive to 0 in the build script |
| `cpu.core.x_amo_phase` [3] | yes | (c) drive to 0 in the build script |
| `cpu.core.csr_u.dbg_req_resume_prev` | yes (once `debug_mode` is 0) | (c) drive to 0 |
| `cpu.core.csr_u.pending_dbg_resume_prev` | yes (once `debug_mode` is 0) | (c) drive to 0 |
| `mhartid_val` [32] | n/a — genuine input | (c) arbitrary but **constant**, in SystemVerilog |
| `eco_version` [4] | n/a — genuine input | (c) arbitrary but **constant**, in SystemVerilog |

**Nothing was assumed.** Option (b), an `assume`, was not used for any of them.

#### Why driving them is a modelling fix and not an assumption

Take `debug_mode` (`hdl/hazard3_csr.v:162-168`):

```verilog
always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        debug_mode <= 1'b0;
    end else if (DEBUG_SUPPORT) begin      // <-- 0 in this configuration
        debug_mode <= (debug_mode && !exit_debug_mode) || enter_debug_mode;
    end
end
```

With `DEBUG_SUPPORT = 0` there is no `else` branch at all, so in Verilog the
flop holds its reset value 0 for ever. **Constant 0 is what this RTL means.** A
free signal is not a weaker model of this design, it is a model of a *different*
design. Restoring the constant removes a modelling error; it does not remove a
behaviour the design can exhibit. The same argument covers the other three:
each has a reset value and a non-reset branch that the configuration makes
unreachable.

Hazard3's author writes exactly this tie-off by hand elsewhere in the same file
— `hdl/hazard3_csr.v:210-221` for `!CSR_M_TRAP`, `:252-257` for `!U_MODE`, with
the comment *"Explicit tie-off when unimplemented ... so that flops are
constant-propagated away"*. These four registers are the ones that were missed.
Belt and braces for `debug_mode`: even if the `DEBUG_SUPPORT` guard on the
update branch were removed, the only term that can set it, `enter_debug_mode`,
is independently constant 0 through the `|DEBUG_SUPPORT &&` factor at
`hdl/hazard3_csr.v:1394`.

#### `debug_mode` was NOT inert, and gate 1's reason was the wrong one

BRINGUP's gate-1 note said `debug_mode` was harmless-but-for
`hazard3_core.v:967` (`x_loadstore_pmp_fail`). **That line is not a read at
all** in this configuration: it lives inside
`generate if (PMP_REGIONS > 0) begin: have_pmp` (`hdl/hazard3_core.v:963-964`)
and is elaborated away; the `no_pmp` branch ties `x_loadstore_pmp_fail` to
`1'b0` at `:1001`. The claim was true by accident.

The real picture is worse. Of the reads of `debug_mode`, **seventeen carry no
`DEBUG_SUPPORT` factor**, and several are functionally live here:

| Site | What a stuck-1 `debug_mode` would do |
|---|---|
| `hazard3_csr.v:1484`, `:1490` | **block every IRQ trap entry** (`!debug_mode && irq_active` — live because `CSR_M_TRAP=1`) |
| `hazard3_csr.v:701` | `debug_dpc_wen` on a CSR write to `DPC` → `hazard3_decode.v:210-211` **overwrites the architectural PC** |
| `hazard3_decode.v:212` | `pc <= pc` — **freezes the PC** |
| `hazard3_frontend.v:592` | clears `fetch_data_vld` — **stalls instruction delivery** |
| `hazard3_csr.v:1443` | spurious WFI wakeup |
| `hazard3_csr.v:1401`, `:1405`, `:705` | drives `dbg_instr_caught_*`, `dbg_data0_wen` out of the core |

So `debug_mode` is *not* protected by parameter gating. It is zero only because
the flop is never written — which is precisely the fact `setundef` destroys.
Had this been left free, the first `mepc` property would have been unprovable
(the solver holds `debug_mode` high and no trap ever enters) and the cause
would have looked like a core bug.

`x_amo_phase`, by contrast, **is** genuinely inert: every synthesizable read is
multiplied by `|EXTENSION_A`, directly or through `d_memop_is_amo`
(`hazard3_core.v:422`). Option (a), leave it free and prove around it, would
have been sound. It is tied off anyway, because it costs nothing and removes
three free bits from the model.

#### How the tie-off is done

`h3_tieoff_undriven.ys`, run by `script h3_tieoff_undriven.ys` from
**all three** Hazard3 build scripts (`build_h3_core.ys`, `build_h3_fast.ys`,
`build_h3.ys`) immediately before `setundef -undriven -anyseq`, so the two
models cannot drift apart:

```
cd top
connect -set \cpu.core.csr_u.debug_mode 1'b0
connect -set \cpu.core.x_amo_phase 3'b000
connect -set \cpu.core.csr_u.dbg_req_resume_prev 1'b0
connect -set \cpu.core.csr_u.pending_dbg_resume_prev 1'b0
cd ..
```

**Do not replace this with `setundef -undriven -zero <selection>`.** `setundef`'s
`-undriven` mode iterates every wire of every selected *module* and ignores
wire-level selection. With one module (yosys-slang flattens everything into
`top`) it zeroes `hready`, `hresp`, `hrdata` and `irq` as well, and you get a
model in which the bus never responds. Measured: the undriven-wire count goes
from 77 to 0 and no error is printed.

The regression test is mechanical: `AmoPhaseZero` and `DebugModeZero` have
**moved from step 1 (must fail) to step 0 (must prove)**. They were SAT at BMC
depth 1 before; they now prove in 10.3 s each. If a future build-script change
loses the tie-off, they fail.

#### `mhartid_val` and `eco_version`

These are genuine inputs, not registers, and they are **live**: each has exactly
one reader and both are read-only CSR fields —
`hdl/hazard3_csr.v:770` (`MHARTID`) and `:401` (`MIMPID[7:4]`). Free every
cycle, two reads of `mhartid` in the same program could return different
values; no instantiation behaves that way and the specification has one
`mhartid`.

Fixed in `check/h3_core_common.svh` **without an assumption**, structurally: the
value is sampled from a free wire during the reset cycle and held for ever
after.

```verilog
always @ (posedge clk_i) begin
    mhartid_val <= rst_ni ? mhartid_val : h3_mhartid_free;
    eco_version <= rst_ni ? eco_version : h3_eco_version_free;
end
```

The solver still chooses the hart ID — the theorem is "for every hart ID", not
"for hart 0" — but it must choose once. Because the constancy is structural
rather than an `assume`, it cannot be silently dropped, and it does not appear
in the proof's constraint list where it would have to be read as a weakening.
It **is** listed below as an environment modelling statement, because it does
narrow the modelled environment.

#### A flattening landmine, checked and cleared

`./probe_undriven.sh` also reports `cpu.core.csr_u.irq`, `..._software`,
`..._timer` (and `cpu.core.fence_rdy`, `cpu.core.frontend.mem_data`) as
"used but has no driver". If those were *separate* free signals rather than
alias wires for the top-level inputs, then every future constraint on `irq`
would silently miss the CSR file, and gate 4 onwards would be unsound in a way
nothing would reveal. New step-0 property `CsrIrqAlias`:

```verilog
assign h3_irq_alias_ok = (cpu.core.csr_u.irq == irq) && ... ;
```

**It proves** (10.0 s). They are aliases; the "undriven" report is an artefact of
`check` running before `opt_clean` resolves the alias chain. Nothing to fix.

### Part 2 — the abstraction function, prototyped on `mepc`

`check/peek/h3_abs.svh`. **Design (b) — compare pre-state only — was chosen, and
it works.**

#### Why not (a) or (c)

Ibex's `check/peek/abs.sv` builds a post-state as
`post_mepc = CSR.mepc_en ? CSR.mepc_d : pre_mepc`, because `ibex_cs_registers`
exposes a `_d`/`_en` next-state pair for every CSR. `hazard3_csr.v` exposes
neither: `mepc` is written from inside one
`always @(posedge clk or negedge rst_n)` block (`:304-321`) and **neither the
next value nor the write enable exists as a named wire**. Option (a) would mean
copying

```verilog
mepc <= trapreg_update_enter        ? mepc_in      & MEPC_MASK
      : (wen_m_mode && addr == MEPC) ? wdata_update & MEPC_MASK : mepc;
```

into the harness. Rejected for the reason the plan gives: the copy contains the
same bug as the original, so the bug is invisible. Option (c), sampling one
cycle after retire, needs a stall-free window that this pipeline does not
guarantee — `m_stall` can hold for an unbounded number of cycles with
`MAX_BUS_STALL = -1`.

Option (b) needs none of that:

```verilog
assign pre_mepc = cpu.core.csr_u.mepc;
```

There is no re-encoding either, unlike Ibex's `mstatus`/`mcause`: Hazard3 stores
`mepc` as a flat XLEN word, already masked to `MEPC_MASK`.

#### The commit points

Provisional — gate 3 owns the real definition — but sound for these properties
and justified from the RTL:

```verilog
assign h3_xm_retire     = |cpu.core.df_cir_use;
assign h3_trap_entry    = cpu.core.m_trap_enter_vld && cpu.core.m_trap_enter_rdy;
assign h3_x_writes_mepc = cpu.core.d_csr_wen && (cpu.core.fd_cir[31:20] == 12'h341);
```

* `|df_cir_use` is the X→M handoff. `hazard3_decode.v:142-146` gives
  `df_cir_use = (d_starved || d_stall) ? 0 : (fd_cir_is_32bit ? 2 : 1)` and
  `:140` gives `d_stall = x_stall || d_starved || ...`, so `|df_cir_use` already
  implies `!x_stall && !d_starved`. It is the same signal
  `hazard3_rvfi_monitor.vh` uses to fill `rvfm_m_valid`, and the same one
  `hazard3_core.v:1134` uses for the `minstret` counter.
* `trap_enter_vld && trap_enter_rdy` is the contract stated in
  `hazard3_csr.v:68`: *"Once trap_enter_vld && _rdy, mepc_in is copied to mepc"*.
* `fd_cir[31:20]` is **instruction decode**, not the CSR file's write logic:
  `hazard3_core.v:1182` wires `csr_u.addr` to exactly this field, and
  `d_csr_wen` is the decoder's bit (`hazard3_decode.v:506-511`, forced to 0 for
  an invalid or starved slot at `:565`). What is deliberately *not* read is
  `wen`/`wen_m_mode`, the CSR file's own enable — using that would have made the
  check below tautological.

#### What was proved

Three new step-0 properties, all on `build/core.aig`:

| Property | Statement | Result |
|---|---|---|
| `MepcStableBetweenCommits` | on any cycle that was not a commit point, `pre_mepc` is unchanged | **PROVED** 9.6 s, 1.42 GB |
| `MepcChangeHasCause` | `pre_mepc` moves only if the previous cycle was a trap entry, or the retirement of a CSR instruction naming `0x341` | **PROVED** 9.5 s, 1.42 GB |
| `MepcAligned` | `pre_mepc[0] == 0` (`MEPC_MASK`, `hazard3_csr.v:303`) | **PROVED** 10.1 s, 1.42 GB |

**These are not bounded checks.** `prove1.sh` runs rIC3's default engine (IC3/PDR)
and returns UNSAT, which is an unbounded proof over all reachable states of the
model. The gate asked for a bounded check; the property turned out to be cheap
enough to close outright, which is a stronger result and costs the same 10 s.
For the record, the bounded check was run too — `rIC3 -e bmc --end 30` on each of
the three reaches bound 30 and stops with no counterexample — but the IC3 result
subsumes it.

#### Non-vacuity: three controls, all of which must fail

A proof that `mepc` only changes for the right reasons is worthless if `mepc`
never changes. Each control is `MepcChangeHasCause` with one term deleted, in
step 1 of `thm/hazard3.proof`, run by `./neg_check.sh`:

```
NegControl        -> RESULT: SAT, counter-example at depth 3
NegMepcNeverMoves -> RESULT: SAT, counter-example at depth 5
NegMepcOnlyTrap   -> RESULT: SAT, counter-example at depth 5
NegMepcOnlyCsr    -> RESULT: SAT, counter-example at depth 7
```

* `NegMepcNeverMoves` SAT at depth 5 → `mepc` does move; the abstraction is
  exercised.
* `NegMepcOnlyTrap` SAT at depth 5 → there is a trace where `mepc` moves and the
  cause is *not* a trap, i.e. the CSR-write disjunct is load-bearing.
* `NegMepcOnlyCsr` SAT at depth 7 → and a trace where the cause is *not* a CSR
  write, i.e. the trap disjunct is load-bearing.

Both disjuncts of `MepcChangeHasCause` are necessary and both paths are
reachable. The property is not vacuous.

#### What this does and does not establish

**Does:**
* `pre_mepc` is stable between commit points (requirement (i)) — this is exactly
  what the gate-4 ghost mechanism needs in order to carry the specification's
  answer from one comparison point to the next.
* `pre_mepc` changes only at a commit point whose instruction architecturally
  writes `mepc` (requirement (ii)).
* Neither statement duplicates the design's write logic (requirement (iii)): the
  harness reads the register and the instruction, never the write enable and
  never the write data.
* Unbounded, over the whole reachable state space of the configured model.

**Does not:**
* Say anything about the **value** `mepc` takes. "Changes at the right time" is
  proved; "changes to the right value" is the specification comparison, gate 5.
  That asymmetry is the point of design (b): the value is never reconstructed in
  the harness, so it can only be checked against Sail.
* Survive a change to the commit-point definition. `h3_xm_retire` is provisional.
  If gate 3's predicate differs from `|df_cir_use`, these three properties must
  be re-proved against it — they are cheap, so that is a 30 s cost.
* Generalise to the other CSRs by itself. `mepc` was the easy one (see below).

#### Verdict on the gate

**PASS.** Design (b) achieves (i), (ii) and (iii) on `mepc`, unbounded, in 10 s
a property, with all three non-vacuity controls failing as required.

#### Measurements

Each property proved alone, rIC3 default engine (IC3), six concurrent jobs.

| Property | A `core.aig` | A mem | B `all.aig` | B mem |
|---|---|---|---|---|
| `AmoPhaseZero` | 10.3 s | 1.42 GB | 12.7 s | 2.46 GB |
| `DebugModeZero` | 10.3 s | 1.42 GB | 12.8 s | 2.46 GB |
| `CsrIrqAlias` | 10.0 s | 1.42 GB | 12.8 s | 2.46 GB |
| `MepcStableBetweenCommits` | 9.6 s | 1.42 GB | 12.8 s | 2.46 GB |
| `MepcChangeHasCause` | 9.5 s | 1.42 GB | 12.5 s | 2.46 GB |
| `MepcAligned` | 10.1 s | 1.42 GB | 12.6 s | 2.46 GB |
| `rIC3 -e bmc --end 30` on the three `Mepc*` | reached bound 30, no CEX | | | |

Whole step-0 sweep after the change: **26/26 PROVED on `build/core.aig`**. The two
expensive bus properties drifted up with the extra 72 latches:
`AhbAphStable` 545 s → 569 s, `AhbDphWdataStable` 185 s → 258 s. Nothing else moved.

Model sizes and cost:

| | before gate 2 | after gate 2 |
|---|---|---|
| `core.aig` `M I L O A B C` | `655564 34407 2034 10097 619123 20 5` | `655938 34404 2106 10213 619428 26 5` |
| `core.aig` build | 0:35 | 0:38, 2.05 GB |
| `all.aig` build | 15:46 | **9:08** |
| `make check-env` | PASS | **PASS** — 2210 entries identical, both models `L=2106 B=26 C=5` |

The +72 latches are the harness's own: 32 for `h3_past_pre_mepc`, 32 + 4 for the
sampled `mhartid_val`/`eco_version`, 4 for the past-flag bits. The `all.aig` build
came in at 9:08 rather than the 15:46 recorded at gate 1; nothing was done to make
that happen, so treat it as noise on a shared box rather than a result.

### The assumption list after gate 2

Unchanged from gate 1 apart from one addition. Nothing in this gate added an
`assume`.

1. **AHB5 slave behaviour.** `hazard3/test/formal/common/ahbl_slave_assumptions.v`,
   instantiated verbatim, `MAX_BUS_STALL = -1` (no fairness bound). Written by the
   core's author, cross-checked by the eight master-contract properties.
2. **The debug port is tied off**, justified by `DEBUG_SUPPORT = 0`: there is no
   debug module in this configuration, and `hazard3_cpu_1port.v:232` grants the
   debug system bus with no `DEBUG_SUPPORT` guard, so leaving it free would put a
   second unconstrained master on the port.
3. **NEW (gate 2): `mhartid_val` and `eco_version` are constant.** Arbitrary, but
   chosen once and held. This is an *environment modelling* statement — they are
   strap ports, not protocol or data signals — and it is implemented structurally
   rather than as an `assume`, but it does narrow the modelled environment and is
   therefore listed.

Explicitly **not** on the list, and why:

* The four tie-offs in `h3_tieoff_undriven.ys`. These restore the value the RTL
  itself holds; a free signal there models a different design. Argued in full
  above.
* Any `NotDebug`-style assumption. Ibex needs one (`check/top.sv:188`) because its
  `debug_mode` is a live register reachable from `debug_req_i`. Hazard3's is not
  reachable at all in this configuration, so the honest fix is the model, not an
  assumption.
* Liveness. Still absent by choice (plan §6). The result remains "if Hazard3
  retires an instruction, it retires it correctly".

### What gate 3 needs to know

> **SUPERSEDED by "Gate 3: the commit point" below, which was written after
> doing the work.  Two of the five points here turned out to be wrong: (2)
> attributes the `EXCEPT_REFETCH`/`EXCEPT_MRET` exclusions to `rvfi_valid` when
> they are on `rvfi_trap`, and (4) generalises "no writeback skew" from the CSR
> file to the whole architectural state, which the register file contradicts.
> Kept verbatim because the corrections are only legible against it.**

Gate 3 defines the commit point at the X→M handoff and asserts agreement with
`rvfi_valid`.

1. **The provisional commit point is `|cpu.core.df_cir_use`,** and the three `Mepc*`
   properties are stated against it. If gate 3's predicate differs, re-prove them —
   10 s each, so there is no excuse not to.
2. **`rvfi_valid` is two registers behind that.** `hazard3_rvfi_monitor.vh` says
   *"We consider instructions to retire as they cross the M/W pipe register"*, and
   builds `rvfm_m_valid <= |df_cir_use && !(m_trap_enter_vld && m_trap_enter_rdy)`
   under `if (!x_stall)`, then `rvfi_valid_r <= rvfm_m_valid && !m_stall`. So the
   agreement assertion is between our X→M trigger and `rvfi_valid` **delayed by the
   M-stage occupancy**, not a same-cycle equality. Note the monitor *excludes* the
   instruction squashed by a trap (`&& !(m_trap_enter_vld && m_trap_enter_rdy)`)
   and excludes `EXCEPT_REFETCH`/`EXCEPT_MRET` from `rvfm_m_take_exception`; our
   trigger must make the same choices or the assertion will fire for a definitional
   reason.
3. **Trap entry is a separate commit event from instruction retire.** `mepc` proves
   it: `NegMepcOnlyCsr` and `NegMepcOnlyTrap` both fail, so neither event subsumes
   the other. A single retire predicate will not cover both. Ibex handles this with
   `wbexc_handling_irq` and the `use_curr_dut`/`use_curr_spec` selects in
   `check/peek/compare_helper.sv`; the same shape is needed here.
4. **CSR side effects happen exactly at the X→M handoff.** `hazard3_core.v:1186`
   gives `wen = d_csr_wen && !m_csr_access_mask` and `:1146` gives
   `m_csr_access_mask = m_trap_enter_soon || fd_cir_break_any || x_stall`, so a CSR
   write lands on precisely the cycle its instruction leaves X. That is a genuinely
   convenient fact: unlike Ibex, there is no writeback-stage skew to model.
5. **`m_mode` is a constant.** With `U_MODE = 0`, `hazard3_csr.v:252-257` assigns
   `m_mode <= 1'b1` unconditionally every cycle, so `wen_m_mode == wen` and the
   privilege mux is dead. Do not port Ibex's `pre_priv`/`post_priv`.

### What gate 4 (the follower) needs to know

The abstraction has to grow to the rest of the architectural state. `mepc` was the
easy one; the others are not all like it.

* **`mtval` does not exist.** `hazard3_csr.v:844-846`: `MTVAL` decodes, and the
  read data comment is *"Hardwired to 0"*. There is no register. The plan's
  estimate of a six-register ghost set is therefore **five**: `mstatus`, `mie`,
  `mcause`, `mtvec`, `mscratch`, plus `mepc`.
* **`mstatus` must be assembled**, like Ibex's struct: Hazard3 stores it as five
  separate bits, `mstatus_mpie`/`mstatus_mie`/`mstatus_mpp`/`mstatus_mprv`/
  `mstatus_tw` (`hazard3_csr.v:188-192`). With `U_MODE = 0`, `mstatus_mpp` is
  constant 1 (`:256`) and `mstatus_tw` constant 0 (`:244`, `&& U_MODE`).
* **`mcause` must be widened**, like Ibex's `widenMCause`: Hazard3 stores
  `{mcause_irq, mcause_code[3:0]}` (`:354-355`) and zero-fills the middle on read
  (`:838-840`).
* **`mtvec`, `mscratch`, `mie` are flat words** and come across like `mepc`.
* Every one of them is written from the same `trapreg_update_*` /
  `wen_m_mode && addr == X` pattern, so the `MepcStableBetweenCommits` /
  `MepcChangeHasCause` pair generalises verbatim — change the register and the CSR
  address, keep the commit-point wires. That is the real evidence that design (b)
  scales: the per-register cost is two lines.
* **`RESET_REGFILE = 0` still stands.** The register file has no reset value;
  assume equality with the spec at reset, which is the honest weaker assumption
  (plan §7).

---

## Gate 3: the commit point (2026-09-16) — PASS, unbounded

Files: `check/peek/h3_commit.svh` (the definition), `check/peek/h3_abs.svh`
(retargeted onto it), `thm/hazard3.proof` (15 new step-0 properties, 9 new
step-1 controls), `build_h3*.ys` (`-DHAZARD3_RVFI_STANDALONE`).

### The finding that shaped the definition

**Hazard3 does not commit an instruction's architectural effects on a single
cycle.** Two different pipeline boundaries are involved, and no one cycle
covers both:

| Architectural state | Written when | RTL |
|---|---|---|
| CSR file (`mepc`, `mcause`, `mstatus`, `mtvec`, `mscratch`, `mie`) | the instruction leaves **X** | `csr_u.wen = d_csr_wen && !m_csr_access_mask`, `hazard3_core.v:1186`, and `m_csr_access_mask ⊇ x_stall`, `:1146` |
| architectural PC (`decode_u.pc`) | the instruction leaves **X**, or a redirect is accepted | `hazard3_decode.v:206-227` |
| register file | the instruction leaves **M** | `m_reg_wen = |xm_rd && !m_bus_stall && xm_except == EXCEPT_NONE`, `hazard3_core.v:1509-1510`, wired to the regfile write port at `:1577-1579` |
| store data on the bus | the instruction leaves **M** | `m_bus_stall` is the "data phase still in flight" term, `:1387` |
| `mepc`/`mcause`/`mstatus`, PC | trap entry | `trapreg_update_enter`, `hazard3_csr.v:181` |

This **corrects gate 2's note 4**, which said "CSR side effects happen exactly
at the X→M handoff … unlike Ibex, there is no writeback-stage skew to model".
The first half is right and the conclusion is wrong: the *register file* has
exactly the writeback skew Ibex has. Hazard3's X→M and M→W boundaries map 1:1
onto Ibex's ID/EX→WB and WB→retire, so Ibex's two-point structure (`spec_en`
at ID/EX, comparison at `wbexc_finishing`) ports across unchanged rather than
simplifying away.

### The definition

`check/peek/h3_commit.svh`. Four events; the first three are architectural,
the fourth is explicitly not.

| Wire | Meaning | Definition | Justification |
|---|---|---|---|
| `h3_x_advance` | X→M handoff; CSR write and PC advance land here. Ibex's `instr_will_progress`. | `\|cpu.core.df_cir_use` | `hazard3_decode.v:142-144`; `df_cir_use` is "the decoder consumed the CIR this cycle" |
| `h3_retire` | **the retire event**: M→W crossing; regfile and memory land here, instruction can no longer be squashed. Ibex's `wbexc_finishing`. | `h3_m_valid && !cpu.core.m_stall` | `hazard3_rvfi_monitor.vh:12` ("we consider instructions to retire as they cross the M/W pipe register"); `hazard3_core.v:1391, 1509` |
| `h3_trap_entry` | **the trap-entry event**: `mepc`/`mcause`/`mstatus.{mie,mpie}` written, PC → `mtvec`. Covers exceptions *and* interrupts. | handshake `&& xm_except ∉ {MRET, REFETCH}` | `hazard3_csr.v:181` `trapreg_update_enter`, verbatim |
| `h3_trap_exit` | MRET: `mstatus.mie ← mpie`, `mpie ← 1`, PC → `mepc`. Architectural, **not** a trap. | handshake `&& xm_except == MRET` | `hazard3_csr.v:182` `trapreg_update_exit` |
| `h3_refetch` | microarchitectural re-fetch. **Not** a commit event. | handshake `&& xm_except == REFETCH` | excluded from both `trapreg_update_*` at `hazard3_csr.v:181-182` |

`h3_m_valid` is the one piece of state the harness has to add: Hazard3 has no
`xm_valid` register (`xm_rd`, `xm_memop`, `xm_except` are all zeroed on a
bubble at `hazard3_core.v:1282-1288`, but a real instruction can legitimately
carry those same values), so M-stage occupancy must be *followed*, exactly as
Ibex follows it with `wbexc_exists`. Its update condition is taken from the
X/M pipe register's own bubble condition (`hazard3_core.v:1264` load on
`!m_stall`, `:1280` bubble on `x_stall || d_starved || m_trap_enter_soon`) —
deliberately **not** from the monitor, so that the agreement assertion below
has content.

Nothing in any definition reads a CSR write-enable (`wen`, `wen_m_mode`,
`trapreg_update*` as signals) or the regfile write port. Those appear only on
the *left* of the coverage obligations. That is the tautology gate 2 flagged,
and it is still avoided.

The Ibex-shaped hooks gate 4 will attach to are also here: `h3_spec_en`
(`h3_x_progress || (h3_trap_entry && h3_trap_is_irq)` — Ibex's
`wbexc_handling_irq | instr_will_progress`), `h3_cmp_en`, `h3_use_curr_dut`,
`h3_use_curr_spec`.

### `EXCEPT_MRET` and `EXCEPT_REFETCH`: the decision

**MRET is architectural, but it is not a trap.** It is an ordinary RV32
instruction (`hazard3_decode.v:517` decodes `RVOPC_MRET` into
`d_except = EXCEPT_MRET`) that Hazard3 routes down the exception channel purely
to reuse the `f_jump_req`/`trap_enter` handshake for its PC redirect. The CSR
file itself makes the distinction: `hazard3_csr.v:182` gives MRET its own
`trapreg_update_exit`, which writes only `mstatus.{mie,mpie}` and leaves `mepc`
and `mcause` alone. So:

* MRET **retires as an instruction** — `hazard3_core.v:1127-1134` counts it in
  `x_instr_ret` via `x_except_counts_as_retire`, and the monitor raises
  `rvfi_valid` for it. `TrapExitRetires` proves `h3_trap_exit → h3_retire`.
* MRET is **not** a trap-entry commit event. Including it would ask the
  specification to take a trap the architecture says did not happen, and would
  let `mepc` appear to "have a cause" to change when it cannot.
  `McauseChangeHasCause` is stated *without* a trap-exit term and proves, which
  is the negative half of the decision; `MstatusMieChangeHasCause` needs the
  trap-exit term and is the positive half.

**REFETCH is purely microarchitectural and is not a commit event.**
`hazard3_csr.v:181-182` exclude it from *both* `trapreg_update_enter` and
`trapreg_update_exit`, so it writes no CSR at all, and `:1462-1466` sends its
redirect to `debug_dpc_rdata`, which `hazard3_decode.v:186` aliases to the
architectural `pc` itself — the author's comment says "we're relying on the
aliasing of dpc and pc … the intent is to fetch the sequentially-next
instruction again". It is the pipeline saying *the CSR write I just retired
invalidated the instructions I have already fetched*. The CSR instruction that
raised it retires normally at its own X→M handoff and its write commits;
nothing architectural moves.

In *this* configuration it is additionally **unreachable**, twice over, and
`NoRefetchException` proves it: `hazard3_csr.v:1275-1281` makes
`write_is_fetch_ordered` a disjunction of four terms each multiplied by
`PMP_REGIONS > 0` or `DEBUG_SUPPORT > 0` (both 0 here), and the other producer,
`hazard3_decode.v:514` (`FENCE.I`), is guarded by `EXTENSION_ZIFENCEI` (also 0).
`PcChangeHasArchCommit` is the discriminating test: it allows only the two
architectural redirects, and it proves.

### Agreement with the core author's monitor

`hdl/hazard3_rvfi_monitor.vh` is now **compiled into both models, verbatim**.
It needs no transcription and no harness-written boilerplate: Hazard3 already
ships the switch for using the RVFI port outside riscv-formal.
`-DHAZARD3_RVFI_STANDALONE` makes `hazard3_core.v:6-8` and
`hazard3_cpu_1port.v:10-12` include `hdl/hazard3_rvfi_standalone_defs.vh`,
which defines `RISCV_FORMAL` and the `` `RVFI_OUTPUTS ``/`` `RVFI_CONN `` port
macros. (riscv-formal's own `checks/rvfi_macros.vh` is *not* on this box —
`hazard3/test/formal/riscv-formal` is an unpopulated submodule directory — so a
first attempt wrote those two macros by hand; that file was deleted once the
author's own copy was found. Worth remembering: look for the vendor's
standalone-defs file before writing port boilerplate.)

Two assertions, both proved:

* `MValidAgreesRvfi` — `h3_m_valid == cpu.core.rvfm_m_valid`.
* `RetireAgreesRvfiValid` — `rvfi_valid == $past(h3_retire)`.

**The delay is one register from `h3_retire`, two from the X→M handoff.**
`rvfm_m_valid` is the first (`hazard3_rvfi_monitor.vh:54-61`), `rvfi_valid_r`
the second (`:62`). Gate 2's "two registers behind" was measured from
`|df_cir_use` and is consistent.

**`RetireAgreesRvfiValid` holds with NO exclusions, which corrects gate 2's
note 2.** That note said the monitor "excludes the trap-squashed instruction
and `EXCEPT_REFETCH`/`EXCEPT_MRET`", implying all three exclusions sit on
`rvfi_valid`. They do not:

* the trap-squash exclusion (`&& !(m_trap_enter_vld && m_trap_enter_rdy)`,
  `:57`) *is* on `rvfi_valid`, and our `h3_x_progress` reproduces it from the
  pipe register's bubble condition instead. `XProgressMatchesMonitor` proves
  the two forms equal — not a syntactic identity: it needs
  `|df_cir_use → (m_trap_enter_soon ↔ trap handshake)`, which comes from the
  two halves of `x_stall_on_trap` (`hazard3_core.v:414-415`) killing
  `df_cir_use` in every other case.
* the `EXCEPT_REFETCH`/`EXCEPT_MRET` exclusions (`:28-32`) are on
  `rvfm_m_take_exception`, which `:69` registers into **`rvfi_trap`**, not
  `rvfi_valid`. A retiring MRET is reported *valid and not trapped*.
  `RvfiTrapExcludesMret` proves that.

So the definition written by the core's author and the definition derived here
from the pipe registers are the same definition. That is the cross-check gate 3
was for, and it passed without weakening.

### Mutual exclusion: they are **not** exclusive, and must not be

`NegRetireTrapExclusive` (`!(h3_retire && h3_trap_entry)`) **fails at BMC depth
5**, as required. Two architectural reasons, both in the RTL:

* **Interrupt.** `hazard3_core.v:1504-1507`: *"Interrupt entry does not prevent
  writeback, because the interrupt is notionally inserted in between the
  instruction in M and the instruction in X."* The M instruction retires and
  the trap is entered on the same cycle, with `mepc` taking the **X**
  instruction's PC (`:1400`).
* **Exception.** `m_stall` (`:1391-1392`) holds the excepting instruction in M
  until the handshake goes through, so the handshake cycle *is* its M→W
  crossing. `ExceptionTrapRetires` proves `h3_trap_entry && !irq → h3_retire`.

What *is* exclusive is the effect, not the event: an exception replaces the
instruction in M, so it suppresses that instruction's register write.
`ExceptionSuppressesWrite` proves it.

Consequence for gate 4: an **interrupt** is an instruction-less commit event
and needs its own spec query (`h3_spec_en`'s second disjunct); an **exception**
never is, and must be handled as part of the retiring instruction.

### Coverage: what changes, and where

All unbounded (rIC3 IC3, UNSAT), on both models.

| Property | Statement |
|---|---|
| `RegWriteAtRetire` | `m_reg_wen → h3_retire` — the register file is written only on a retire cycle |
| `PcChangeHasCommit` | `decode_u.pc` moves only after an X→M handoff or a trap handshake |
| `PcChangeHasArchCommit` | …only after an X→M handoff, a trap entry or an MRET (REFETCH excluded) |
| `MepcStableBetweenCommits` | `mepc` does not move on a non-commit cycle |
| `MepcChangeHasCause` | `mepc` moves only for a trap **entry** or a retiring CSR write to `0x341` |
| `MepcAligned` | `mepc[0] == 0` |
| `McauseChangeHasCause` | `mcause` moves only for a trap **entry** or a retiring CSR write to `0x342` — no MRET term |
| `MstatusMieChangeHasCause` | `mstatus.MIE` moves only for a trap entry, an MRET, or a retiring CSR write to `0x300` |

`RegWriteAtRetire` is the one the X→M handoff alone could not have discharged,
and it is why the definition needs two pipeline boundaries.

The pattern generalises to the rest of the gate-4 ghost set verbatim — change
the register and the CSR address, keep the commit wires. `mie` is the one to
watch: it has a **second** write path, `wen_m_mode && addr == MEICONTEXT`
(`hazard3_csr.v:335-341`), so its cause list needs two addresses, not one.

### Results

41 step-0 properties (26 from gates 1-2, 15 new), rIC3's IC3 engine, **UNSAT =
proved unbounded**, not a bounded check. Times are wall clock, `prove1.sh`.

Gate-3 properties, both models:

| Property | core.aig | all.aig |
|---|---|---|
| `XAdvanceIsNoStall` | 19.0 s | 12.4 s |
| `NoRefetchException` | 19.4 s | 14.0 s |
| `XProgressMatchesMonitor` | 19.2 s | 14.1 s |
| `MValidAgreesRvfi` | 18.3 s | 15.6 s |
| `RetireAgreesRvfiValid` | 18.6 s | 15.4 s |
| `RvfiTrapExcludesMret` | 17.2 s | 14.6 s |
| `RegWriteAtRetire` | 19.1 s | 14.4 s |
| `PcChangeHasCommit` | 18.2 s | 13.2 s |
| `PcChangeHasArchCommit` | 17.0 s | 13.1 s |
| `McauseChangeHasCause` | 11.0 s | 12.0 s |
| `MstatusMieChangeHasCause` | 10.4 s | 11.9 s |
| `ExceptionSuppressesWrite` | 11.1 s | 12.2 s |
| `ExceptionTrapRetires` | **200.7 s** | 86.0 s |
| `TrapExitRetires` | 12.7 s | 12.3 s |
| `TrapKindsPartition` | 13.3 s | 11.9 s |

`ExceptionTrapRetires` is the only gate-3 property that is not seconds. It is
also the deepest: it has to rule out every way an exception handshake could
complete with stage M empty.

Gate 2 re-proved against the **final** commit definition (narrowed trap event):

| Property | gate 2 (core/all) | gate 3 (core/all) |
|---|---|---|
| `MepcStableBetweenCommits` | 9.6 s / 12.8 s | 15.2 s / 20.9 s |
| `MepcChangeHasCause` | 9.5 s / 12.5 s | 15.6 s / 19.4 s |
| `MepcAligned` | 10.1 s / 12.6 s | 18.5 s / 12.2 s |

All three still prove, with a **strictly stronger** trap guard. No finding
against the commit point.

The remaining 23 gate-1/gate-2 properties all re-prove in 11-22 s on both
models, with two exceptions, and both are the known-slow **bus** properties from
gate 1. **Both prove on both final models**; what varies wildly is how long they
take:

| Property | run 1 (L=2731) core / all | run 2 (L=2732) core / all | run 3, idle machine, L=2732 core / all |
|---|---|---|---|
| `AhbAphStable` | PROVED 518.9 s / 648.8 s | PROVED 719.7 s / 711.7 s | — |
| `AhbDphWdataStable` | PROVED 202.0 s / 186.4 s | TIMEOUT at 1800 s / (killed) | **PROVED 1746.4 s / 2735.9 s** |

So the final tally is **41 / 41 on both models, all unbounded**.

`AhbDphWdataStable` is a solver-variance problem, not a regression: it has now
proved four times out of five attempts across the two models — 202 s, 186 s,
1746 s, 2736 s — and the one failure was a 1800 s *timeout*, never a
counterexample. Two things explain the spread: rIC3 runs a portfolio across
threads, and run 2 was executed with the `core` and `all` sweeps **concurrently**,
eight rIC3 processes on sixteen vCPUs, which halves the portfolio width each
solver gets (`AhbAphStable` slowed 1.4x in the same run).

**Nothing in gate 3 can affect these two.** They mention only `top`'s AHB5 bus
wires; the commit point, the follower flop and the RVFI monitor are all
downstream of the core and outside their cone of influence. Practical advice:
prove them one at a time on an idle machine, budget an hour, and never run two
sweeps at once.

### Negative controls -- all 13 fail, as required

`./neg_check.sh`, `rIC3 -e bmc` against a throwaway `build/neg.aig`:

| Control | Depth | What its failure establishes |
|---|---|---|
| `NegControl` | 3 | `rst_ni` really deasserts |
| `NegMepcNeverMoves` | 5 | `mepc` is exercised |
| `NegMepcOnlyTrap` | 5 | the CSR-write disjunct is live |
| `NegMepcOnlyCsr` | 7 | the trap disjunct is live |
| `NegNeverRetire` | 5 | instructions do cross M/W |
| `NegNeverRvfiValid` | 6 | the author's monitor reports retirements too, so `RetireAgreesRvfiValid` is not `0 == 0` |
| `NegNeverRegWrite` | 5 | the register file is written |
| `NegNeverTrapEntry` | 5 | traps are entered |
| `NegNeverIrqTrap` | 6 | **interrupts** are taken — the instruction-less commit event is live |
| `NegNeverExcTrap` | 5 | **exceptions** are taken |
| `NegNeverTrapExit` | 5 | MRET retires — the MRET decision is exercised |
| `NegRetireTrapExclusive` | 5 | retire and trap entry **co-occur**: the two-event structure is necessary |
| `NegNestedTrapAssume` | 5 | the riscv-formal "no nested exceptions" assumption is **not** in the model |

### Supporting lemmas

| Property | Statement |
|---|---|
| `XAdvanceIsNoStall` | `\|df_cir_use == !(x_stall \|\| d_starved)` — the uop and load/store-pair terms of `d_stall` are dead in this configuration, so `\|df_cir_use` really is two of the three terms of the X/M bubble condition |
| `NoRefetchException` | `x_except != REFETCH && xm_except != REFETCH` |
| `XProgressMatchesMonitor` | our pipe-register form equals the monitor's form |
| `TrapKindsPartition` | a trap handshake is exactly one of entry / exit / refetch |

### Did enabling the monitor add an assumption?

**No**, and there are two independent checks.

1. **Structural.** Assumptions become AIGER constraints. The header's `C` field
   is **5 before and after**, and `check_env.sh` compares it across both models
   on every build. (`L` went 2034 → 2732 and `B` 20 → 41; the latches are the
   monitor's ~580 plus the harness's follower and history registers, and the
   bad states are the 15 new step-0 properties.)
2. **Behavioural.** `hazard3_csr.v:1554-1555` would
   `assume(except == EXCEPT_NONE || except == EXCEPT_MRET)` whenever `in_trap`,
   which makes nested traps unreachable and would gut every exception-entry
   property; `:1570-1571` would assume IRQs are never deasserted. Both sit
   inside `` `ifdef RISCV_FORMAL ``, which the new define *does* set — but that
   block is nested inside `` `ifdef HAZARD3_ASSERTIONS `` (`:1537`), which this
   flow does not define. `NegNestedTrapAssume` is the first assumption's body
   over its own guard (`in_trap` reproduced in the harness from `:1542-1547`);
   it is a step-1 property and **fails at depth 5**, so the assumption is
   genuinely absent.

The monitor's own `` `ifdef RISCV_FORMAL_FAIRNESS `` block (`:374-386`) contains
an `assume` bounding sleep duration. `hazard3_rvfi_standalone_defs.vh` does not
define it and neither do we — it is exactly the liveness fairness constraint
the plan deliberately does without. The one non-synthesisable `assert(!m_stall)`
at `:329-332` is inside `` `ifndef HAZARD3_RVFI_STANDALONE ``, so the define
removes it; that matters mechanically too, since a live `$assert` cell would add
a bad-state output and shift the property indices.

### The assumption list after gate 3

**Unchanged from gate 2. Nothing in this gate added an `assume`.**

1. **AHB5 slave behaviour.** `ahbl_slave_assumptions.v` instantiated verbatim,
   `MAX_BUS_STALL = -1` (no fairness bound).
2. **The debug port is tied off**, justified by `DEBUG_SUPPORT = 0`.
3. **`mhartid_val` and `eco_version` are constant** — arbitrary, chosen once and
   held; structural, not an `assume`, but listed because it narrows the
   environment.
4. **Liveness absent by choice.** The result remains "if Hazard3 retires an
   instruction, it retires it correctly".

Explicitly **not** on the list, and why:

* The four tie-offs in `h3_tieoff_undriven.ys` (gate 2's argument, unchanged).
  `./probe_undriven.sh` was re-run after enabling the monitor and reports the
  **same 16 wires** as gate 2 — the monitor introduces no new undriven register.
* `-DHAZARD3_RVFI_STANDALONE`. It adds observation logic only; see the two
  checks above. If either check ever fails it becomes assumptions 5 and 6.

### No Hazard3 bug found

Everything in this gate was harness and modelling. The one thing that looked
like it might be a discrepancy — the monitor "excluding MRET" while our retire
event includes it — was a misreading in gate 2's hand-off note, not a
disagreement between the two definitions.

### What gate 4 (the follower, reduced ghost set) needs to know

1. **Query the spec at `h3_spec_en`, compare at `h3_cmp_en`.** They are
   different cycles. Ibex does the same thing and `check/peek/follower.sv`'s
   `wbexc_post_*` / `wbexc_dut_post_*` snapshot pattern ports across directly.
2. **The DUT's CSR post-state must be snapshotted at the X→M handoff**, because
   by the time the instruction retires, the *next* instruction's CSR write may
   already have landed. The register file must **not** be snapshotted: compare
   the write port (`m_reg_wen` / `xm_rd` / `m_result`) live at `h3_retire`,
   which is what `h3_reg_write` is for and what Ibex does at
   `check/peek/compare_helper.sv:38-43`. Do not reconstruct the bypass network
   — `hazard3_rvfi_monitor.vh:223-224` says why, in the author's words.
3. **Interrupts need an instruction-less spec query; exceptions do not.** See
   "Mutual exclusion" above.
4. **MRET is a retiring instruction whose effects land on its retire cycle**, so
   `h3_use_curr_dut` must include `h3_trap_exit` as well as `h3_trap_entry`.
5. **`mtval` does not exist** (gate 2). Ghost set is `mstatus`, `mie`, `mcause`,
   `mtvec`, `mscratch`, `mepc`.
6. **`mie` has two write addresses** (`MIE` and `MEICONTEXT`) — see "Coverage".
7. **`rvfi_pc_rdata`/`rvfi_pc_wdata`/`rvfi_rd_*`/`rvfi_mem_*` are now in the
   model for free**, and are a second opinion on every later comparison. They
   cost 698 latches, no constraints, and ~0 s of build time (38 s vs 37 s for
   `core.aig`, unchanged for `all.aig`).

---

## Gate 4: the abstraction, the follower and the ghost (2026-09-16)

Three deliverables, in the order they depend on each other:

| File | What it is | Lines |
|---|---|---|
| `check/peek/h3_abs.svh` | the abstraction, grown from `mepc` alone to the whole architectural state | 34 KB |
| `check/peek/h3_follower.svh` | the follower and the ghost | 29 KB |
| `check/h3_top.sv` | the Sail `spec_api` instance, **connected** | — |

Before this gate every input of `spec_api_i` was free, so the Sail model was
structurally unreachable from every property and `build/all.aig` said exactly
what `build/core.aig` said. It now reads the core's architectural state.

### 1. The abstraction: what it covers

Design (b) throughout — **pre-state only, read directly, never reconstructed**.
Gate 2 predicted the per-register cost would be "two lines"; measured, it is one
`assign` plus two obligations, and the `assign` is a re-encoding of stored bits,
never a re-implementation of a write.

| Architectural state | How it is read | Ghosted? |
|---|---|---|
| `mepc` | `csr_u.mepc` — flat, already MEPC_MASKed | yes |
| `mscratch` | `csr_u.mscratch` — flat | yes |
| `mie` | `csr_u.mie` — flat, reserved bits held 0 by MIE_WMASK | yes |
| `mtvec` | `{mtvec_reg[31:2], 1'b0, mtvec_reg[0]}` — BASE + WARL'd bit 1 + MODE | yes |
| `mcause` | `{mcause_irq, 27'h0, mcause_code}` — Ibex's `widenMCause` | yes |
| `mstatus` | five separate bits packed to `mie=3, mpie=7, mpp=12:11, mprv=17, tw=21` | yes |
| architectural PC | `decode_u.pc` | yes |
| next PC | `pre_pc + (fd_cir_raw[1:0]==2'b11 ? 4 : 2)` — decoded in the harness | input |
| register file | `mem[i]`, with the in-flight write-port write forwarded | yes (32 ghosts) |
| `mip` | `csr_u.mip` — read-only in this implementation | input |
| `misa`, `mvendorid`, `marchid`, `mimpid`, `mhartid`, `mconfigptr` | restated from the configuration, then **proved** equal to the CSR file's read data | input |

**The new check that gate 2 did not have.** Each re-encoding is restated
independently in the harness and then proved equal to the design's own read-data
path (`hazard3_csr.v:740-745`, a pure combinational case on `addr`, evaluated
whether or not a read is enabled — so conditioning on the address alone is
enough and nothing reads a read-*enable*). `AbsMstatusIsRdata`,
`AbsMcauseIsRdata` and `AbsMtvecIsRdata` are the sharp ones: they are what turn
"mstatus is assembled correctly" from a claim about the code into a theorem.
`AbsMisaIsRdata` and `AbsIdsAreRdata` do the same for the constants handed to
the specification, so a configuration drift fails the proof instead of silently
mis-specifying. Ibex reads `` `CSR.MISA_VALUE `` hierarchically instead;
restating and proving is strictly better.

#### What the abstraction cannot reach, and why

1. **`mtval` does not exist.** `hazard3_csr.v:844-846` — MTVAL decodes, so
   accessing it is legal and does not trap, but there is no register and the
   read comment is *"Hardwired to 0"*. Read-only-zero `mtval` is architecturally
   permitted; the Sail model nevertheless writes exception-specific information
   into it. So **`mtval` is not ghosted and not compared**: the specification is
   handed constant 0 as its `mtval` pre-state on every query (which is exactly
   what the DUT would return, so reads agree) and its `mtval` post-state is
   discarded. `AbsMtvalIsZero` proves the constant is the design's behaviour.
   This narrows what the proof covers and is listed as such below.

2. **`mcounteren` is three real flops that can never be set** — every write is
   masked with `|CSR_COUNTER && |U_MODE`, both 0 (`hazard3_csr.v:643-647`). Same
   treatment as `mtval`; `AbsMcounterenIsZero` proves the constancy.

3. **PMP and `mseccfg` have no registers** (`PMP_REGIONS = 0`) while Sail's
   `stub.sv` reports `pmp_count = 4`. The specification is handed a
   permanently-empty PMP, which in M-mode grants every access — the DUT's
   behaviour. The *CSR-legality* divergence (the DUT raises illegal on
   `pmpcfg*`/`pmpaddr*`/`mseccfg`, Sail does not) is handled by the uncheckable
   list below, not by pretending it is not there.

4. **Privilege is not state.** `U_MODE = 0` ties `m_mode` to 1
   (`hazard3_csr.v:255-257`), so there is no `pre_priv`/`post_priv` pair to port.
   `MModeIsM` proves it rather than assuming it.

5. **`mimpid` cannot be a constant** because it carries `eco_version`, which is
   arbitrary-but-constant by the gate-2 device. It is read from
   `csr_u.mimpid_rdata`.

#### The register file, and why it needs exactly one level of forwarding

`hazard3_regfile_1w2r.v:66-74` has one write port and **two registered read
ports**. The registered reads are why `hazard3_core.v:369-374` keeps
`mw_result` as a write→read bypass — but none of that is architectural: `mem`
*is* the architectural register file, and the only committed write it does not
yet contain is the one on the write port this cycle. So

```
pre_regs[i] = (m_reg_wen && xm_rd == i) ? m_result : mem[i]
```

which is exactly the shape of Ibex's `abs.sv:19-22`. The three-way bypass mux at
`hazard3_core.v:574-582` is **never read by the harness** —
`hazard3_rvfi_monitor.vh:223-224` says why in the author's words, and the single
write port forwarded here is the same pair of signals the comparison itself uses
at `h3_retire`, so no new trusted logic is introduced.

`RegChangeHasWrite` proves the forwarding is right: the probed register's
architectural value changes only on a cycle where the write port is writing it,
and note the cause is the *current* cycle, not the past one — the value moves
when the write port asserts and then **stays put** when the write lands in `mem`
at that same edge. That it stays put is half of what the property proves.
Together with gate 3's `RegWriteAtRetire` this is the register-file half of the
commit point, which gate 3 could only state about the write port.

**`h3_reg_probe` is an arbitrary-but-constant register index** — a free wire
sampled during reset and held, the same device as `mhartid_val`. So the
obligation is "for every register index" and costs 32 bits of history instead of
1024. The solver still chooses the register; it just cannot change its mind
mid-trace.

#### The uncheckable-CSR list is an allowlist, not Ibex's denylist

Ibex denylists the CSRs where it and Sail disagree (`check/top.sv:470-486`).
Hazard3 needs an allowlist, because divergence runs in **both** directions:

* Hazard3 implements a custom CSR space Sail has never heard of
  (`meiea`/`meipa`/`meifa`/`meipra`/`meinext`/`meicontext`, `msleep`, `h3misa`,
  `pmpcfgm0`) — the DUT accepts, Sail raises illegal;
* `CSR_COUNTER = 0` turns the counter block off in the DUT while Sail keeps it
  on, and `PMP_REGIONS = 0` does the same for `pmpcfg`/`pmpaddr`/`mseccfg` — the
  DUT raises illegal, Sail accepts.

Enumerating what *agrees* is the honest way round. The allowlist is
`mstatus, mstatush, misa, mie, mtvec, mcounteren, mscratch, mepc, mcause, mtval,
mip` plus the five read-only identification CSRs; everything else drops
`h3_has_ghost`. Over-clearing costs coverage, never soundness, and
`NegNoUncheckableCsr` is the control that the clearing path is reachable at all.
**Gate 5 must re-audit this list against the Sail model's CSR legality
directly** — it was derived from the Hazard3 side.

**Note the one register that is checkable here and is not in Ibex: `mie`.** Ibex
marks it uncheckable because Ibex has fast interrupts Sail cannot model. Hazard3
with `EXTENSION_XH3IRQ = 0` and `NUM_IRQS = 1` has exactly `meie`/`mtie`/`msie`,
which `MieReservedZero` proves.

### 2. The follower

`check/peek/h3_follower.svh` holds two distinct things, and Ibex has both:

* **the follower** (`h3_fol_*`), per instruction, loaded at the X→M handoff and
  cleared at retirement — Ibex's `wbexc_*`;
* **the ghost** (`h3_ghost_*`), architectural, updated on *every* query including
  the instruction-less interrupt query, never cleared — Ibex's `spec_past_*`, and
  what gate 5's `Wrap` will be stated over.

The follower carries: occupancy, PC, next-PC, instruction bits, destination
register, "left X with an exception", "left X with a fetch fault", which of the
three questions the specification was asked, and the specification's answer —
`int_err`, register write enable/address/data, the post-state of all six ghosted
CSRs and the PC, and the memory operation (enable, address, write data, byte
enables, and whether a second granule was requested).

#### Four ways it differs from Ibex's `check/peek/follower.sv`

1. **It is smaller, because the commit point is simpler.** Ibex's follower
   carries `ex_has_branched_q`, `wbexc_csr_pipe_flush`, `wbexc_is_wfi`,
   `wbexc_compressed_illegal` and a second-granule memory bundle, all of which
   exist to paper over Ibex's controller FSM, its CSR pipe flush, and its
   misaligned-access splitting. Hazard3 traps misaligned accesses instead of
   splitting them, routes its pipeline flush through the same trap handshake as
   everything else, and decompresses in the frontend. None of that ports.

2. **It carries no DUT post-state**, because design (b) means there is none to
   snapshot. Gate 3's note said to snapshot the DUT's CSR post-state at the X→M
   handoff; under design (b) that turns out to be **unnecessary**, and
   `XProgressEmptiesM` is why:

   > `h3_x_progress → !x_stall` (`XAdvanceIsNoStall`), `x_stall ⊇ m_stall`
   > (`hazard3_core.v:477`), so `h3_x_progress → !m_stall`, and if M is occupied
   > it retires on that same cycle.

   A CSR write needs `h3_x_progress` (`csr_u.wen` is masked by `x_stall` and
   `m_trap_enter_soon`, `:1145-1146`), so it can only land on a cycle where the
   instruction in M retires simultaneously. **During the retire cycle the CSR
   file still holds the retiring instruction's post-state.** Gate 5 therefore
   compares against `pre_*`, one query later, in place of the snapshot Ibex
   takes. In Ibex the same fact is part of the *definition* of
   `instr_will_progress`; here it is a theorem about the stall logic, and it is
   proved.

3. **Occupancy is derived twice and then proved equal.** `h3_m_valid`
   (gate 3) follows the X/M pipe register's own bubble condition; `h3_fol_valid`
   is set and cleared by the follower's own events, as Ibex does with
   `wbexc_exists`. `FollowerMatchesMValid` is the obligation — Ibex's
   `ValidExists`.

4. **The interrupt query can coincide with a retirement.** Ibex proves
   `NoFinishingIRQ` (`wbexc_exists |-> ~wbexc_handling_irq`): its `IRQ_TAKEN`
   cycle has nothing in WB. In Hazard3 that lemma is **false**, deliberately —
   `hazard3_core.v:1504-1507`, *"Interrupt entry does not prevent writeback,
   because the interrupt is notionally inserted in between the instruction in M
   and the instruction in X"*, which gate 3 measured as
   `NegRetireTrapExclusive`. So the ghost can be updated by an interrupt query on
   the same cycle the follower is cleared by a retirement, and the ghost-carry
   obligations have to survive that. They do, because both sides are registers:
   on the coincident cycle the ghost still holds the pre-interrupt value, and on
   the next cycle the follower is empty. This was the design risk going in and
   it is the one that did not bite.

#### What the follower deliberately does not do

The register file is **not** snapshotted. Its write port
(`h3_reg_write`/`xm_rd`/`m_result`) is compared live at `h3_retire`, which is
where Ibex compares it too (`compare_helper.sv:38-43`). Snapshotting it would
mean predicting the write, which means modelling the bypass network.

#### The specification interface, and the two-model split

The `spec_*` boundary wires are **driven** by `spec_api_i` in `build/all.aig` and
**undriven — hence free** in `build/core.aig`. That is what lets the identical
property set be built into both models, which `make check-env` requires (same L,
same B, same C). A follower-integrity property does not mention them and means
the same thing in both; a ghost-carry property is developed against a free
specification on `core.aig` — which is the *harder* case, since a free signal may
change every cycle — and becomes a statement about Sail on `all.aig`.

These are the only harness signals that deliberately do **not** carry the `h3_`
prefix: `check_env.sh` keys its comparison on that prefix, and these are not part
of the core's environment.

### 3. Connecting the specification

`check/h3_top.sv`. Mode selection is the three-way split gate 3 identified:

```
h3_spec_mode = (h3_trap_entry && h3_trap_is_irq) ? MAIN_IRQ
             : h3_x_fetch_err                    ? MAIN_IFERR
             :                                     MAIN_IDEX
```

encoded in plain bits inside the shared harness (`t_MainMode` exists only in
`all.aig`) and converted in the top.

Three wiring decisions worth recording:

* **`insn_bits` comes from `fd_cir_raw`, not `fd_cir`.**
  `hazard3_frontend.v:51` documents `cir_raw` as *"Unexpanded instruction data"*
  while `cir` is the post-decompression form. Handing the expanded form to a
  specification that decompresses for itself would compare Hazard3's
  decompressor against nothing. The upper half is masked off for a compressed
  instruction, matching `hazard3_rvfi_monitor.vh:58` exactly — which is what
  makes `FollowerInstrMatchesMonitor` a same-value equality.

* **`pre_pc` needs no case split.** Ibex's is
  `wbexc_handling_irq ? pc_if : pc_id`. Hazard3's `m_exception_return_addr`
  (`hazard3_core.v:1400-1404`) is `d_pc` walked back over the M instruction for
  an exception and taken verbatim for an interrupt, so the interrupt's return
  address *is* the X instruction's PC. `IrqReturnIsPrePc` and
  `FollowerPcIsExceptionReturn` prove both halves — and gate 5 needs both to
  compare `mepc`.

* **`spec/stub.sv`: `sail_plat_enable_misaligned_access` 1 → 0.** Hazard3 traps
  misaligned loads and stores (`hazard3_core.v:647`, `x_unaligned_addr`) rather
  than splitting them, which is also why `check/peek/alt_lsu.sv` is not ported.
  Left at 1 the Sail model would *allow* the misaligned access and produce a
  memory operation where the DUT produces a trap — a divergence caused by a
  platform-configuration flag rather than by the core. This is plan section 8's
  "flip stub.sv's misaligned-split flag to 0". `sail_sys_pmp_count` is left at 4
  deliberately: with every `pmpcfg` zero and the hart in M-mode, Sail grants
  every access, which is what `PMP_REGIONS = 0` does.

### 4. A build change: `--no-implicit-memories`

`yosys-slang` rejects a hierarchical read of a memory variable:

```
check/peek/h3_abs.svh:225:29: error: unsupported operation on a memory variable
        cpu.core.m_result : cpu.core.regs.real_dualport_noreset.mem[gi];
```

so the abstraction could not read the register file at all. Three ways out were
considered; the one taken is `read_slang --no-implicit-memories`, added to all
three build scripts (`build_h3_core.ys`, `build_h3_fast.ys`, `build_h3.ys` — they
must agree or `make check-env` fails). It makes slang lower `mem` to plain flops
instead of inferring a memory; `memory_map -formal` was going to do that two
passes later anyway, so the model is the same one.

The rejected alternative was patching a peek port into
`hazard3_regfile_1w2r.v` via `patch_hazard3_rtl.sh`. It would have worked, but it
adds harness-visible taps to the DUT source, and a build-script flag that changes
no source is the smaller change.

### 5. Results

**87 step-0 properties** (41 from gates 1-3, 46 new), rIC3's IC3 engine,
**UNSAT = proved unbounded**, not a bounded check.

Both models: `L = 4657` latches (up from 2034 — 1024 ghost registers, 32
known-bits, 7x32 ghost CSRs, the follower's bundle, and 7x32 bits of one-cycle
history), `B = 87`, **`C = 5`, unchanged, so gate 4 added no assumption to
either model.** `make check-env`: PASS, 2869 core/environment signal entries
identical.

#### Traceability of the numbers

`/tmp/proof` is shared scratch, and gate 3's and gate 4's runs were both writing
untagged `core-<Prop>.res` files into it against *different* models — so a result
could silently be another agent's, against another model. `prove1.sh` and
`sweep.sh` now write to `/tmp/proof/<model>-L<latches>-B<bads>-C<constraints>/`,
with a `<model>-latest` symlink, and print the tag on every line;
`neg_check.sh` / `neg_check_all.sh` print it too. Gate 3's untagged files were
moved to `/tmp/proof/archive-untagged/` rather than deleted.

**Every number in this section is from `L4657-B87-C5`**, the gate-4 model, unless
it says otherwise.

#### The gate-1/2/3 property set, re-proved on the gate-4 model

This matters for a reason beyond regression: gate 4 adds 2,623 latches of
observational state, and if any of it had introduced an `assume`, a
previously-honest property could have gone vacuous. Three checks say it did not.

* **`C = 5` AIGER constraints** on both models, before and after — `make
  check-env` enforces the equality, and the number is the same one gate 3
  recorded at `L = 2732`.
* **All 41 gate-1/2/3 properties re-prove** on the gate-4 model: 41/41 on
  `core.aig` and 41/41 on `all.aig`, including both known-slow bus properties.
* **All 13 gate-1/2/3 negative controls still fail**, at the same BMC depths
  gate 3 recorded (3, 5, 5, 7, 5, 6, 5, 5, 6, 5, 5, 5, 8).

`NegNestedTrapAssume` is the sharpest of those: it is the body of the
riscv-formal "no nested exceptions" assumption, and it still produces a
counterexample at depth 8, so that assumption is still not in the model.



#### `build/core.aig` (`L4657-B87-C5`): **87 / 87 PROVED**

Median about 11 s; the whole sweep is ~25 minutes at `-P 10`. The two
known-slow **gate-1 bus** properties both proved this time — `AhbAphStable` in
522 s and `AhbDphWdataStable` in 217 s, which is its fastest run yet and its
sixth proof out of seven attempts. The slowest new property is
`FollowerPcIsExceptionReturn` at 102 s: it has to relate
`m_exception_return_addr`'s PC walk-back to the follower's snapshot across every
stall.

#### `build/all.aig` (`L4657-B87-C5`): **87 / 87 PROVED**

— but one of them needed a rerun on its own, and the reason is the most
interesting number in this gate.

Seventy-eight properties prove on the full model in 12-35 s, i.e. the gate-0
conclusion still holds for everything whose cone is the core. The **nine
ghost-carry properties** behave completely differently, because they are the
first properties in this harness whose cone contains the Sail interpreter:

| Property | core.aig | all.aig | peak RSS on all.aig |
|---|---|---|---|
| `GhostMatchesFollowerMtvec` | 15.7 s | **1023 s** | 14.8 GB |
| `GhostMatchesFollowerMie` | ~12 s | **1042 s** | 15.0 GB |
| `GhostMatchesFollowerMepc` | ~12 s | **1096 s** | 16.1 GB |
| `GhostMatchesFollowerMcause` | ~12 s | **1144 s** | 16.1 GB |
| `GhostMatchesFollowerMstatus` | ~12 s | **1162 s** | 16.1 GB |
| `GhostMatchesFollowerPc` | ~12 s | **1266 s** | 17.1 GB |
| `GhostMatchesFollowerMscratch` | ~12 s | **1399 s** | 15.5 GB |
| `GhostX0Unknown` | ~12 s | **945 s** | 15.3 GB |
| `GhostRegMatchesFollower` | ~12 s | **4595 s**, rerun alone | 21.7 GB |

Roughly **80x slower and 1000x more memory**. rIC3 reports, for a ghost property
on `all.aig`:

```
origin ts has 7938047 vars, 836590 inputs, 4657 latches, 12453847 clauses
```

against 634,737 vars / 34,189 inputs / 1,139,061 clauses for a core-only property
on either model. **This is the flip the plan predicted**, and it is now measured:
*"Re-measure once the spec is actually connected to the core. Today the spec
instance has free inputs, so it is unreachable from every property. Once
Wrap/Load/Store tie it to the core it will be inside their cones and the answer
may legitimately flip."*

`GhostRegMatchesFollower` was killed by the OOM killer (`rc=137`) at 61 s in the
sweep, because eight of these were running concurrently on a 123 GB machine at
15-20 GB each. Rerun alone on an idle machine it **proves in 4595 s at 21.7 GB**.
That is an operational lesson, not a property failure: **at most four
spec-connected proofs at a time, and watch RSS.**

**The core.aig proofs of those nine are not a weaker substitute — they are
strictly stronger, and here is the argument.** In `core.aig` the `spec_*` wires
are free inputs; in `all.aig` they are a function of core state. The two models
share the core's transition relation byte-for-byte
(`check/h3_core_common.svh`, and `make check-env` checks it mechanically), and
the follower and ghost latches have identical update functions in both,
depending on `spec_*` only as data. So every `all.aig` trace projects to a
`core.aig` trace — take the free inputs to be whatever the specification
produced — and `core.aig` admits strictly more. A property over those signals
that is UNSAT on `core.aig` is therefore UNSAT on `all.aig` — which all nine
confirm empirically, at between 60x and 300x the cost.

This **extends gate 0's two-model rule** from "a property mentioning only core
signals means the same thing in both models" to "a property whose only
dependence on the specification is as *free input data* is proved more strongly
on `core.aig`". It is a soundness argument and should be signed off before being
leaned on; its mechanical precondition is the one `check_env.sh` already
enforces.

It does **not** extend to gate 5's goals. `Wrap`, `Load`, `Store` and `NoMem`
say the specification's value is *correct*, which is vacuously false when the
specification's outputs are free. Those must be proved on `all.aig` — and the
table above says that will be the expensive part of the project.

#### Negative controls: 36 / 36 fail, as required

`./neg_check.sh` against a throwaway `build/neg.aig` (`L4657-B123-C5` — note
`C = 5` here too). Every one produced a BMC counterexample; the 13 gate-1/2/3
controls are unchanged, at the same depths gate 3 recorded.

| Control | Depth | What its failure establishes |
|---|---|---|
| `NegMscratchNeverMoves` | 5 | `mscratch` is exercised |
| `NegMtvecNeverMoves` | 5 | `mtvec` is exercised |
| `NegMieNeverMoves` | 5 | `mie` is exercised |
| `NegMcauseNeverMoves` | 5 | `mcause` is exercised |
| `NegMstatusNeverMoves` | 5 | `mstatus` is exercised |
| `NegMstatusNoTrapExit` | 6 | the **trap-exit** term of `MstatusChangeHasCause` is load-bearing — the MRET decision, over the whole register |
| `NegRegProbeNeverMoves` | 5 | the probed register really is written, so `RegChangeHasWrite` is not vacuous |
| `NegNoUncheckableCsr` | 4 | an uncheckable CSR access is reachable, so the ghost's clearing path is not dead code |
| `NegFollowerNeverValid` | 5 | **the follower does hold an instruction** — without this every 4d/4e obligation is vacuous |
| `NegFollowerNeverExcepts` | 5 | it holds an excepting instruction too |
| `NegFollowerNeverWritesReg` | 5 | the specification writes a register for an in-flight instruction |
| `NegFollowerExceptExact` | 6 | **a finding, not a control** — see below |
| `NegHasGhostNever` | 5 | the ghost becomes valid |
| `NegGhostRegNeverKnown` | 5 | the ghost register file is written |
| `NegGhost{Pc,Mstatus,Mie,Mcause,Mtvec,Mscratch,Mepc}AlwaysZero` | 5 each | **each ghost register actually changes** |
| `NegNeverIferrQuery` | 5 | the specification is asked `MAIN_IFERR` |
| `NegNeverIrqQuery` | 6 | the specification is asked `MAIN_IRQ` |

#### The spec-connected negative controls: 12 / 12 fail, as required

`neg_check.sh` builds its throwaway model from `build_h3_core.ys`, where the
`spec_*` wires are free — so for a control like "this ghost register is always
zero" the counterexample the solver finds is just "pick a non-zero free input".
That establishes the ghost's *update path* is live; it does not establish that
the **Sail model** drives it. The distinction matters for the deliverable "each
ghost register actually changes sometimes", so there is a second script.

**`./neg_check_all.sh`** (new) builds `build/negall.aig` from `build_h3_fast.ys`
— core *plus* the connected specification, `L4657-B123-C5` — and re-runs the
twelve spec-dependent controls against it. All twelve produce a BMC
counterexample:

| Control | Depth | What its failure establishes, on the CONNECTED model |
|---|---|---|
| `NegHasGhostNever` | 5 | the ghost becomes valid |
| `NegGhostRegNeverKnown` | 5 | the Sail model writes a register the ghost records |
| `NegFollowerNeverWritesReg` | 5 | ... for an instruction in flight |
| `NegGhostPcAlwaysZero` | 5 | **the Sail model drives the ghost PC non-zero** |
| `NegGhostMstatusAlwaysZero` | 5 | ... ghost `mstatus` |
| `NegGhostMieAlwaysZero` | 5 | ... ghost `mie` |
| `NegGhostMcauseAlwaysZero` | 5 | ... ghost `mcause` |
| `NegGhostMtvecAlwaysZero` | 5 | ... ghost `mtvec` |
| `NegGhostMscratchAlwaysZero` | 5 | ... ghost `mscratch` |
| `NegGhostMepcAlwaysZero` | 5 | ... ghost `mepc` |
| `NegNeverIrqQuery` | 6 | the specification is really asked `MAIN_IRQ` |
| `NegNeverIferrQuery` | 5 | ... and `MAIN_IFERR` |

Independently, the structural evidence that the specification is connected at
all is the cone measurement above: before gate 4 no property's transition system
contained the interpreter, and now nine do.

#### The one thing `NegFollowerExceptExact` says

It is in the must-fail list because the fact it denies is *true and important*:
an instruction can leave X with `xm_except == EXCEPT_NONE` and acquire an
exception later, in M, from a data-phase bus fault
(`hazard3_core.v:1290-1296`, the first phase of the two-phase AHB5 error
response, written while `m_stall` is high). The specification was asked its
question at the X→M handoff and knows nothing about it, so for that instruction
the follower's recorded answer is simply wrong. BMC finds it at depth 6. This is
Hazard3's analogue of Ibex's `wbexc_err`, and it is the one real gap gate 5 has
to close — see section 7.

### 6. The assumption list after gate 4

Unchanged from gate 3 in substance. `C = 5` AIGER constraints before and after,
which is the mechanical check that nothing was added.

1. **AHB5 slave assumptions**, `MAX_BUS_STALL = -1` (stalls unbounded).
2. **Debug port tied off**, justified by `DEBUG_SUPPORT = 0`. *(signed off at gate 1)*
3. **`mhartid_val` / `eco_version` constant** — an environment modelling
   statement, listed because it narrows the environment even though it is
   structural rather than an `assume`.
4. **Liveness absent by choice.**

Gate 4 adds **no `assume`**, but it does add four things that narrow what the
result *covers*, and they belong on the record next to the assumptions even
though they are not assumptions:

5. **`mtval` is not compared.** Hazard3 hardwires it to 0 (architecturally
   permitted); the Sail model writes exception-specific information. The
   specification is fed constant 0 and its `mtval` output is discarded. Nothing
   about `mtval` is proved.
6. **`mcounteren` is not compared**, for the same reason (permanently 0 in this
   configuration).
7. **PMP and `mseccfg` are not compared.** The specification is given an empty
   4-region PMP, which grants everything in M-mode; the DUT has no PMP at all.
8. **CSR accesses outside the allowlist drop the ghost**, so nothing downstream
   is proved about an instruction stream that touches Hazard3's custom CSRs, the
   counter block, PMP, debug or trigger CSRs. This *weakens* coverage; it cannot
   make a false statement true.

Also, as a modelling change rather than an assumption:

9. **`spec/stub.sv`'s `sail_plat_enable_misaligned_access` is 0**, matching
   Hazard3's misaligned-access trap. `spec/stub.sv.orig-gate4` is the untouched
   copy.
10. **`read_slang --no-implicit-memories`** in all three build scripts, so the
    register file lowers to flops and the abstraction can read it. The model is
    the same one `memory_map -formal` produced before.

And, still outstanding from the plan and not introduced here:

11. **Register-file equality at reset.** `RESET_REGFILE = 0`, so the file has no
    initial value. Nothing in gate 4 assumes one — `h3_ghost_has_reg` tracks
    "written since the trace began", which is the honest guard — but gate 5's
    `Wrap` will need the DUT and the specification to *start* equal, and that is
    where the assumption lands.

### 7. What gate 5 (Wrap, Load, Store, NoMem) needs to know

1. **`Wrap` is `h3_spec_en && h3_has_ghost |-> pre_<x> == h3_ghost_<x>`** for the
   six CSRs and the PC, plus the two register lanes
   `h3_ghost_has_reg[d_rs1] |-> pre_regs_cut[d_rs1] == h3_ghost_regs[d_rs1]` (and
   `d_rs2`). All the machinery is in place; none of it is proved yet, and it will
   need lemmas.

2. **There is no `csrs_match` to write, and that is deliberate.** Under design
   (b) the per-instruction CSR comparison *is* `Wrap`: `XProgressEmptiesM` proves
   the CSR file still holds the retiring instruction's post-state during its
   retire cycle, so the DUT's post-state is read as the *next* query's pre-state
   rather than snapshotted. Do not try to rebuild Ibex's
   `wbexc_dut_post_*` / `use_curr_dut` machinery — there is no `post_*` to build
   it from, and `h3_use_curr_dut` / `h3_use_curr_spec` (placed at gate 3) are
   consequently **unused**. Delete them or repurpose them, but do not assume they
   mean what Ibex's do.

3. **The register write and the memory operation are compared live at
   `h3_retire`**, against `h3_fol_spec_wX*` / `h3_fol_spec_mem_*`. Ibex's
   `addr_match` / `data_match` port across directly with
   `h3_fol_spec_real_write` in place of `spec_real_write`.

4. **THE ONE REAL GAP: M-stage exceptions.** `NegFollowerExceptExact` measures it.
   An instruction can leave X with `xm_except == EXCEPT_NONE` and acquire an
   exception *later*, in M, from a data-phase bus fault —
   `hazard3_core.v:1290-1296` writes `xm_except` while `m_stall` is high, on the
   first phase of the two-phase AHB5 error response. The specification was asked
   its question at the X→M handoff and knows nothing about it, so the follower's
   recorded answer is simply wrong for that instruction. This is Hazard3's
   analogue of Ibex's `wbexc_err`, and Ibex's answer is to tell the specification
   about the memory response before it answers: `spec_mem_read_fst_rdata_i` is
   left **free** in `check/h3_top.sv` precisely so that gate 5 can constrain it
   from a `check/peek/mem.sv` analogue. Do that before attempting `Load`.

5. **`MAIN_IFERR` has the same problem, one level up.** The Sail fetch goes
   through `altFetch` → `mem_read_i(Execute(), PC, size)`, which with an empty
   PMP and an aligned PC always succeeds — so asking the specification for
   `MAIN_IFERR` today yields `MAINRES_NOIFERR` and an internal error. The
   instruction-fetch response has to be plumbed the same way as the data
   response. `NegNeverIferrQuery` says the mode is reachable in the DUT.

6. **Memory comparison must be split across the AHB5 address and data phases**
   (plan section 1): compare address/control at the address phase and latch the
   write-data comparison one cycle. The follower already records the
   specification's address, write data and byte enables at query time, which is
   one cycle *before* Hazard3's address phase for a load/store leaving X — check
   the phase relationship before writing the property.

7. **`h3_fol_spec_mem_snd` must never assert.** Hazard3 traps misaligned
   accesses, and `stub.sv` now tells Sail the platform does not support them, so
   the second granule should be dead. State it as a property; if it fails,
   something about the alignment configuration is wrong rather than the core.

8. **Re-measure the two-model split.** The plan flagged this exact moment: with
   the specification connected, a property that mentions a ghost register now has
   the 10.6 M-gate interpreter inside its cone, and the gate-0 measurement (the
   two models solve identically) may legitimately flip. The gate-4 numbers below
   are the first data point.

9. **`h3_x_csr_checkable` was derived from the Hazard3 side only.** Re-audit it
   against the Sail model's own CSR legality before relying on `Wrap`.

---

# Gate 5: the correctness goals (2026-09-16)

Everything before this gate was machinery. This is the claim.

Four properties are stated — `Wrap`, `Load`, `Store`, `NoMem` — which are Ibex's
five (`dv/formal/README.md`, "Top Level Goals") minus liveness. They live in
`check/peek/h3_goals.svh` and below the `GATE 5 GOALS` marker in
`thm/hazard3.proof`. The supporting machinery they needed is
`check/peek/h3_mem.svh` (new, the Hazard3 analogue of Ibex's
`check/peek/mem.sv`) plus three additions to `check/peek/h3_follower.svh`.

## 1. What the four goals establish, and what liveness would add

Ibex's README gives the composition. Define
`Spec : S x I -> S`, `SpecOut : S x I -> O`, `H3 : A x I -> A`,
`H3Out : A x I -> O` and `abs : A -> S`. Then

* `Load` / `Store` / `NoMem` prove `SpecOut(abs(a), i) == H3Out(a, i)` — the
  memory operation Hazard3 performs for a given micro-architectural state is the
  one the specification performs for the corresponding architectural state.
  These need **no** ghost guard: the specification is fed `abs(a)` directly, so
  the comparison is pointwise.
* `Wrap` proves `Spec(abs(a), i) == abs(H3(a, i))` — one step of the
  specification and one step of Hazard3 land in the same architectural state.
  By induction, `Spec^n(abs(a0), I) == abs(H3^n(a0, I))`, and composing with the
  memory result gives
  `SpecOut(Spec^n(abs(a0), I), i) == H3Out(H3^n(a0, I), i)`
  — the nth memory operation agrees, for every n.

**What liveness would add, and therefore what is missing.** `Live` proves that a
comparison point keeps happening: `always (##[0:N] spec_en)`. Without it the
induction above is over *the queries that occur*, not over time. Precisely:

* **What our four goals establish.** For every n: *if* Hazard3 performs an nth
  specification query, then at that query its architectural state (the six CSRs,
  the PC and every register the specification has written) equals the state the
  Sail model reaches after n steps from the same start, and every memory
  operation it issued on the way is the one the Sail model issued.
* **What they do not establish.** That an nth query ever happens. A Hazard3 that
  deadlocked — stalled for ever on a bus that never responds, or wedged in its
  pipeline control — would satisfy all four vacuously from that point on. The
  honest form of the claim is therefore **conditional on instructions continuing
  to retire**. It is the same caveat Oxford's default flow carries, because
  `Live` is commented out there by default and only ever converged with
  `TIME_LIMIT = 1`; this harness has `MAX_BUS_STALL = -1`, so the bound `Live`
  needs does not even exist here.

Two further narrowings are specific to this port and are *not* consequences of
dropping liveness. They are in the assumption list in section 6, and they are
handled by dropping the ghost rather than by assuming anything:

* an instruction that takes a **data-phase bus fault** is not compared, nor is
  the trap it causes;
* an instruction that takes an **instruction-fetch bus fault** is not compared,
  nor is the trap it causes.

Both are because the Sail model has no channel on which to be told about a bus
error — see section 3, which is the central finding of this gate.

## 2. `check/peek/h3_mem.svh` — and the one place AHB5 makes this *easier*

Ibex's `check/peek/mem.sv` is 136 lines. The Hazard3 analogue is about 60 lines
of substance, and almost all of the difference is one design decision of
Hazard3's: **misaligned accesses trap instead of splitting into two beats.** That
deletes the first/second granule, the early/late response distinction, the
outstanding-response counter and all three `alt_lsu` instances. `MemNoSecondGranule`
states the consequence as a property rather than assuming it, and
`spec_mem_read_snd_rdata_i` is tied to 0 rather than left free so that a
violation shows up there rather than being absorbed by a free input.

What replaces them is the AHB5 two-phase structure, and here the port gets a
simplification the plan did not predict:

> **`x_stall` contains `bus_aph_req_d && !bus_aph_ready_d`**
> (`hdl/hazard3_core.v:484`), so an instruction with a memory operation cannot
> leave stage X until its address phase has been accepted. Since
> `h3_x_progress -> !x_stall`, **the address phase of a memory instruction is
> accepted on exactly the cycle the specification is queried about it.**

`MemAphIsProgress` proves it (`h3_mem_aph -> h3_x_progress`). The consequence is
that Ibex's `FstEnd: spec_en & spec_mem_en |-> mem_gnt_fst_d` — a separate
obligation that the request actually got out before the instruction retired —
has no counterpart here: it is the same cycle as the request. `Load` and `Store`
each collapse from Ibex's `En` + `End` pair into one property.

**Correction to gate 4's handoff, item 6.** It said the follower records the
specification's memory operation "one cycle *before* Hazard3's address phase for
a load/store leaving X". That is wrong: it is the *same* cycle. Only the write
**data** is a cycle later (`hdl/hazard3_core.v:1435-1441` drives `bus_wdata_d`
from `xm_memop` and `m_wdata`, i.e. from stage M), which is why `StoreWData` is
the one memory goal made during the data phase against the follower's latched
copy, and `FollowerOwnsDphase` is the obligation that entitles it to be.

Byte lanes are **compared, which Ibex does not do.** AHB5 has no byte-enable
signal, so `h3_mem_be` is reconstructed from `HSIZE` and the low address bits and
compared against Sail's `write_ram` byte enables (`StoreBe`). Ibex uses the
spec's byte enables only to *mask* the data comparison (`check/top.sv:420-428`),
so an Ibex that asserted extra lanes would not be caught by its goals.

### How the specification is told what a load returned

`spec_mem_read_fst_rdata_i` was left free at gate 4 precisely for this. The
problem it solves: the specification answers in one step at the X→M handoff, but
`HRDATA` does not exist until the data phase, at least a cycle later.

The answer is Ibex's, and the direction of causality is the opposite of what the
port name suggests (`check/peek/mem.sv:46-47` says so in Oxford's own words):
`h3_spec_rdata` is an **undriven free wire**; the solver picks it at the query
cycle; the specification is told it; the follower latches it; and
`MemRdataIsSpecData` then makes the bus hand the core exactly that word when the
data phase completes.

**Why that is a renaming and not a weakening.** `hrdata` is an unconstrained free
input in this harness — Hazard3's own `ahbl_slave_assumptions.v` never mentions
it, because it is data and not protocol. So for every trace of the unconstrained
model there is a trace of the constrained model with the same `hrdata`: choose
`h3_spec_rdata` at the query cycle to be what the trace was going to produce.
The "for all memory contents" quantifier is preserved exactly. The constraint
also fires only on a cycle where the D-side owns the data phase, and
`BusDphMutex` (gate 2) proves the I-side does not — so instruction fetches stay
free even though `hrdata` is physically shared
(`hdl/hazard3_cpu_1port.v:318-319`). It is nevertheless an `assume`, it takes
**C from 5 to 6**, and it is item 5 of the assumption list.

## 3. THE FINDING: the specification has no channel for a bus error

Gate 5's named obligation was to "connect the bus error path to the spec's
exception logic". **Half of that is impossible in this configuration, and the
reason is worth stating precisely, because it is the same fact behind Ibex's
proof hole #2 and behind the `MAIN_IFERR` gap gate 4 predicted.**

**Data side.** `--sv-fun2wires 2:read_ram` / `2:write_ram` turn Sail's
`read_ram` / `write_ram` into the `mem_read_*_rdata_i` / `mem_write_*` ports of
`spec/spec_api.sv`. Those ports carry **data and nothing else**: `read_ram` has
no failure result. The only `MemException` arms reachable from a plain load are
in `phys_mem_read_word_aligned` (`riscv_mem.sail:73-76`), and they fire when
`read_kind_of_flags(aq, rl, res)` returns `None()` — i.e. for illegal
acquire/release/reserve flag combinations, never for a bus response. So **there
is no wire on which to tell the specification that the memory faulted**, and no
amount of harness work creates one without editing the Sail model itself.

**Fetch side, one level up, and worse.** `spec/main.sail:30-34`'s `altFetch`
calls `mem_read_i(Execute(), PC, size)`. `riscv_mem.sail:168-183` shows
`mem_read_i` is a **PMP-and-alignment check only** — it never touches `read_ram`
at all. With an empty PMP and an aligned PC it always returns `MemValue(())`, so
`MAIN_IFERR` always yields `MAINRES_NOIFERR` and hence `int_err`. `SpecEnUnreach`
(Ibex's `thm/ibex.proof:299`) is stated anyway and fails for exactly this
reason; `SpecEnUnreachIdex` is the form this configuration can claim.

**What was done instead of assuming bus errors away.** Ibex's answer is
`check/protocol/mem.sv:38`, `NoErr: assume property (~err_i)`, with the comment
"Sail does not specify what happens on bus errors." This harness does **not** add
that assumption. It drops the ghost instead:

* at query time, `h3_query_specifiable = h3_x_query_checkable && !h3_x_fetch_err`
  — a fetch-error query does not establish a ghost;
* when a data-phase fault lands, `h3_has_ghost` and `h3_ghost_has_reg` are
  cleared on that cycle, in the last statement of the ghost's own always block so
  that a fault coinciding with a query wins.

The two statements are not equivalent and the difference matters. Assuming
`~err_i` makes bus faults **unreachable**; dropping the ghost leaves them
**reachable** — the core still takes them, `NegNeverMemFault` is the control that
it does, the AHB5 master contract is still proved across them, and
`FollowerExceptExact` still has to be exactly right about them. What is given up
is only the architectural comparison for the faulting instruction and its trap,
which is precisely the part Sail cannot express. It is strictly weaker than
Ibex's hole, and it costs **no AIGER constraint**.

## 4. `NegFollowerExceptExact` — the flip, and why it is a real one

Gate 4's named gap. The property is

```
h3_fol_valid |-> h3_fol_<record> == (xm_except != EXCEPT_NONE)
```

At gate 4 `<record>` was `h3_fol_x_except`, a **snapshot** of `x_except` taken at
the X→M handoff, the property was `NegFollowerExceptExact` in step 1, and it
failed at BMC depth 6. The counterexample is the one
`hdl/hazard3_core.v:1289-1296` documents: the pipe register's `else if
(bus_dph_err_d)` arm writes `xm_except` while `m_stall` is high, on the first
phase of the two-phase AHB5 error response, so an instruction that left X clean
is carrying `EXCEPT_LOAD_FAULT` a few cycles later while the follower still says
it is clean.

Gate 5 adds `h3_fol_except`, which is the snapshot **plus** the exception the
instruction picks up while the follower is holding it:

```systemverilog
if (h3_fol_valid && h3_mem_fault) h3_fol_except <= 1'b1;   // late acquisition
if (h3_x_progress)                h3_fol_except <= cpu.core.x_except != H3_EXCEPT_NONE;
```

`FollowerExceptExact` over `h3_fol_except` moves to **step 0**, and the result is
in section 8.

**Note what is deliberately not written there.** The condition is the follower's
own — "I am holding an instruction and the bus reported a D-side error" — and not
a copy of the RTL's `!m_stall ? x_except : bus_dph_err_d ? FAULT : hold`
structure. Copying the RTL would make the obligation tautological: it is the CSR
write-enable trap gate 2 flagged, in a different dress. The harness says a fault
landed on its instruction; the obligation is that this coincides with the pipe
register's own state.

**Two controls make the flip mean something**, and both must still fail:

* `NegFollowerExceptSnapshot` — the gate-4 property restated over the snapshot.
  If it proved, the late term would be dead machinery.
* `NegNeverMemFault` — `!h3_mem_dph_err`. If it proved, `FollowerExceptExact`
  would be true because bus faults never happen, which is exactly the outcome
  adding Ibex's `NoErr` assumption would have produced. This is the control that
  distinguishes "the follower got better" from "the problem was assumed away".

## 5. The register-file-equality-at-reset assumption: measured unnecessary

The plan (section 7) reserved an assumption for this gate:

> `RESET_REGFILE = 0`, so Ibex's "assume `ResetAll`" hole is unavailable. **Do
> not** add a reset assumption to paper over it. Instead: assume the DUT's and
> the specification's initial register state *agree*, which is the honest and
> weaker assumption.

**Gate 5 finds that even that assumption is unnecessary here, and that adding it
would be vacuous. This corrects the plan.** Two facts, both checkable:

1. **The specification instance is stateless.** Sail is built with
   `--sv-inregs --sv-outregs`, so every architectural register is a port, not a
   register. `check/h3_top.sv` drives every one of those input ports from the
   abstraction — from the DUT — on **every** query: `pre_pc`, `pre_mstatus`,
   `pre_mie`, `pre_mcause`, `pre_mtvec`, `pre_mscratch`, `pre_mepc`,
   `pre_regs_cut`. The specification has no initial register state of its own
   with which to disagree. What `Wrap` asserts is that this re-seeding is a
   **no-op**: the state the DUT hands the specification at query N+1 is the state
   the specification produced at query N.
2. **Nothing is compared before the first query.** `h3_has_ghost` starts at 0 and
   `h3_ghost_has_reg` at 0, so every `Wrap` property, and both register lanes,
   are vacuous until the harness has watched the specification produce a value
   for that register. This is Ibex's `has_spec_past` / `spec_past_has_reg`
   mechanism, reproduced faithfully.

Checked against the reference: **Ibex's harness contains no initial-state
assumption either.** `check/top.sv`'s only `initial` is the synthesised reset for
Yosys, and none of its `assume property` statements touches a register, the PC or
a CSR. (It is also worth recording that the reference's `ResetAll` is *not* what
the plan assumed: in this configuration `SecureIbex = 0`, so `ResetAll = 0`, and
`ibex_register_file_ff` has no `ResetAll` parameter at all — its flops reset to
zero unconditionally. So Ibex gets zeroed GPRs for free and simply never needed
the hole. Hazard3's are free, and the `has_spec_past` gating is what makes that
difference invisible.)

**So what is the residual, stated exactly?** The theorem this harness proves is:

> for **every** initial Hazard3 register state `a0`, the trace Hazard3 produces
> agrees with the trace the Sail model produces when started from `abs(a0)`.

which is universally quantified over the initial state rather than fixed to one
— strictly stronger than what the assumption would have bought, and it is what
trace equivalence needs. Ibex's README lists `abs(a0) == s0` as future work; here
it is true by construction, because `s0` is *defined* as `abs(a0)`. The price is
that this is equivalence **relative to a common start**, not a proof that Hazard3
resets correctly — which is Ibex's proof hole #9 and remains ours.

**Nothing was added to the assumption list for this.** The one thing that *was*
checked rather than assumed is that the un-reset register file behaves like a
register file: `RegChangeHasWrite` (gate 4) proves the probed register moves only
on a write to it, which rules out the `setundef -anyseq` failure mode — free
every cycle rather than merely unknown at reset — that gates 1 and 2 found on
four other registers.

## 6. The assumption list after gate 5

1. **AHB5 slave assumptions**, `MAX_BUS_STALL = -1` (stalls unbounded). Hazard3's
   own `test/formal/common/ahbl_slave_assumptions.v`, instantiated verbatim.
   *(gate 1)*
2. **Debug port tied off**, justified by `DEBUG_SUPPORT = 0`. *(gate 1, signed
   off gate 2)*
3. **`mhartid_val` / `eco_version` arbitrary-but-constant** — an environment
   modelling statement, structural rather than an `assume`, listed because it
   narrows the environment. *(gate 2)*
4. **Liveness absent by choice.** The four goals are conditional on instructions
   continuing to retire; section 1 says exactly what that costs. *(plan section
   6, restated here with the composition spelled out)*
5. **NEW — `MemRdataIsSpecData`.** When the in-flight instruction's data phase
   completes, the bus returns the word the specification was told
   (`h3_mem_rdata == h3_fol_spec_rdata`). This is the only `assume` gate 5 adds
   and it is why **C goes from 5 to 6**. Justification in section 2: it is a
   renaming of an already-unconstrained free input (`hrdata` is never mentioned by
   the slave assumptions), the choice is still the solver's, and it is confined to
   cycles where the D-side owns the data phase, which `BusDphMutex` proves the
   I-side does not. It is Ibex's `check/peek/mem.sv:37-39`. Ibex additionally
   needs `SpecReadDataKeep` (stability of the free wire between instructions)
   because its `alt_lsu` reads the live wire outside the query cycle; this harness
   has no `alt_lsu`, so that second assumption is not needed and is not present.

### Coverage narrowings — NOT assumptions, but on the record

These do not constrain the model; they make the harness decline to compare. Each
is strictly weaker than the corresponding Ibex assumption, and none adds an
AIGER constraint.

6. **Data-phase bus faults are not compared.** The ghost is dropped on the cycle
   a fault lands, so the faulting instruction and the trap it causes are outside
   the comparison. Reason: Sail's `read_ram` / `write_ram` have no error result
   (section 3). *Ibex instead assumes `~err_i` — proof hole #2 — which makes the
   fault unreachable; here it stays reachable and `NegNeverMemFault` proves it.*
7. **Instruction-fetch bus faults are not compared.** A `MAIN_IFERR` query does
   not establish a ghost. Reason: `mem_read_i` is a PMP-and-alignment check that
   never fails with an empty PMP, so the specification always answers
   `MAINRES_NOIFERR`. *Ibex does verify `FetchErr`; we do not.* `SpecEnUnreach`
   is the property that measures this rather than hiding it.
8. **`mtval` and `mcounteren` are fed as 0 and never compared**; PMP/`mseccfg`
   are given an empty 4-region PMP granting everything in M-mode; CSR accesses
   outside the 16-address allowlist drop the ghost. *(gate 4, re-audited at gate
   5 — see section 7)*
9. **No proof that Hazard3 resets correctly.** Equivalence is relative to a common
   start (section 6). Ibex's proof hole #9.
10. **No proof of instruction-fetch correctness** — that the instruction executed
    at a given PC was the one loaded from memory at that PC. Ibex's proof hole #8.

## 7. The checkable-CSR allowlist, re-audited from the Sail side

Gate 4 flagged that `h3_x_csr_checkable` had been derived from the Hazard3 side
only. It has now been audited against `riscv_sys_control.sail:17-64`
(`is_CSR_defined`) with `misa = 0x4080_1104`, so
`haveUsrMode() = haveSupMode() = haveNExt() = false` and `xlen == 32`. Note that
`ext_is_CSR_defined` is `= false` in every clause (`riscv_csr_ext.sail:17`), so
that match **is** the complete legal set — there is no extension escape hatch.

**All 16 entries survive. Two justifications were wrong and are corrected in
`check/peek/h3_abs.svh`:**

* **`mcounteren` (0x306).** Gate 4 said it was in the list because "the DUT reads
  it as constant 0". It does not: `hdl/hazard3_csr.v:991` guards the entire
  decode with `if (CSR_COUNTER && U_MODE)`, both 0 here, so **Hazard3 raises an
  illegal instruction**. It stays in the list because **Sail does the same** —
  `riscv_sys_control.sail:32`, `0x306 => p == Machine & haveUsrMode()`. Both
  sides trap; they agree; the entry is correct for a better reason than the one
  given.
* **`mstatush` (0x310).** Sail defines it for RV32 and `readCSR` returns the raw
  `mstatush` register, which **nothing in the Sail model ever writes** (its write
  case, `riscv_insts_zicsr.sail:93`, is commented "ignore writes for now"). That
  would be an unconstrained value — and it is not, only because
  `spec/spec_api.sv:219` pins `.mstatush_in('{bits: 32'b0})`. Hazard3 reads
  0x310 as zero (`hazard3_csr.v:804-806`). So 0x310 is comparable **only because
  of that tie-off**; if it is ever removed, 0x310 must leave the list.

**What the audit confirms about the exclusions**, and why an allowlist was the
right call: in this configuration Sail declares legal four `pmpcfg` (0x3A0-0x3A3),
sixteen `pmpaddr` (0x3B0-0x3BF), `mseccfg`/`mseccfgh` (0x747/0x757),
`mcycle`/`minstret` and their high halves (0xB00/0xB02/0xB80/0xB82) and
`mcountinhibit` (0x320) — **twenty-five addresses Hazard3 traps** because
`PMP_REGIONS = CSR_COUNTER = 0`. In particular:

* **`sail_plat_enable_misaligned_access = 0` has no effect on CSR legality, and
  neither does `sail_plat_enable_pmp = 0`.** `is_CSR_defined` consults only
  `sys_pmp_count()` and `sys_pmp_max_count()`, which `spec/stub.sv:84-85` report
  as 4 and 16. Turning PMP *enforcement* off does not remove the PMP *registers*
  from Sail's legal set.
* **`mseccfg`'s clause carries no PMP condition at all** — it is
  `0x747 => p == Machine`, unconditionally.

A denylist would have had to enumerate all of that correctly and stay correct as
the configuration moved. Gate 4's choice of an allowlist is vindicated: it fails
safe.

Two latent Sail asymmetries were found and are unreachable here, recorded in case
a future configuration reaches them: `medeleg` (0x302) has a `writeCSR` case but
no `readCSR` case, so a read would silently return 0 rather than trap; and
`mcounteren`'s write case is a no-op that never calls a `legalize_` function.

## 8. Results

Model, both files, `make check-env` **PASS**:

```
build/all.aig   L=4690  B=110  C=6      12,078,231 AND gates
build/core.aig  L=4690  B=110  C=6         743,126 AND gates
```

`L` is +33 latches over gate 4 (the follower's exception record, the spec read-data
latch, the memory bookkeeping). `B` is +23 properties (3 gate-5 support lemmas,
20 goals). **`C` is 6, up from 5** — the one assumption of section 2, and the only
one gate 5 adds. `check_env.sh` compares all three across the two models on every
build; 2980 core/environment signal entries are identical.

### 8a. Regression: the 87 still prove, and three more with them

`./sweep.sh core 6 1800` — **90 / 90 PROVED**, unbounded (rIC3 IC3, UNSAT).

* the 87 from gates 1-4 all still prove after the follower and ghost changes;
* the three new gate-5 support lemmas prove, at ~10-13 s each:
  `FollowerExceptExact` 10.5 s, `FollowerOwnsDphase` 10.5 s,
  `MemAphIsProgress` 12.5 s (1.45 GB peak each);
* **`AhbDphWdataStable` needed a re-run, and gate 3's diagnosis was right
  again.** In the sweep it hit the 1800 s cap (a TIMEOUT, not a counterexample)
  while four spec-connected proofs were running beside it — exactly the CPU
  contention gate 3 identified when it recorded this property as high-variance
  under rIC3's thread portfolio (proved in 3 of 4 attempts at 202 s / 186 s /
  1746 s). **Re-run alone it PROVES, in 1934.7 s / 1.77 GB.** Nothing in gate 5
  is in its cone — it is a gate-1 AHB5 master-contract property over
  `hwdata` / `htrans` / `hready`. The operational rule from gate 3 stands and is
  now measured twice: do not run this property under contention.

### 8b. Negative controls: 47 / 47 fail, as required

`./neg_check.sh` on model `L4690-B157-C6` — the 36 from gate 4 plus 11 new,
**every one produces a counterexample under BMC**. The two that matter most for
this gate:

| Control | Depth | What its failure establishes |
|---|---|---|
| `NegFollowerExceptSnapshot` | **6** | the late-exception term is load-bearing — the snapshot-only form is still false, at exactly the depth gate 4 measured |
| `NegNeverMemFault` | **5** | data-phase bus faults are still **reachable** — `FollowerExceptExact` did not become true by making the problem disappear |

and the nine that make the four goals non-vacuous: `NegNeverMemAph` (4),
`NegNeverMemRead` (4), `NegNeverMemWrite` (4), `NegAlwaysMemAph` (4),
`NegNeverWrapPoint` (5), `NegNeverWrapReg` (5), `NegSpecNeverReads` (4),
`NegSpecNeverWrites` (4), `NegNeverStoreDphase` (5), `NegNeverLoadDphaseEnd` (5).

**`NegSpecNeverReads` / `NegSpecNeverWrites` are the important pair**: they are
about the *specification* asking for a load and for a store, so they are what
makes `LoadEn` / `StoreEn` statements about Sail rather than about a free wire.
They are in `neg_check_all.sh` for that reason.

### 8c. THE FOUR GOALS

**Method note, and a correction to how this gate was first run.** The goals were
first attempted with rIC3's IC3 engine (`./goals.sh`). On a 7.94 M-variable,
12.45 M-clause transition system that answers "is it true" slowly *even when the
answer is a shallow counterexample*, because IC3 has to build frames before it
can refute — 30 minutes produced no verdict at all on the first four. The run was
stopped and re-done with **BMC first** (`./goals_bmc.sh`, new), which answers the
question this gate actually asks: is there a counterexample, and can it be read.
This is the right order for a gate whose expected outcome is failure, and it is
recorded here because it is the kind of thing the next person will otherwise
rediscover.

#### Goal 1 — `Wrap`, and THE FINDING OF THIS GATE

`./goals_bmc.sh 4 25 900`, on `build/all.aig`, model `L4690-B110-C6`:

| Property | BMC | Sail's WARL policy for this register | Matches Hazard3? |
|---|---|---|---|
| `WrapMtvec` | **CEX, depth 5** | `legalize_tvec` = `Mk_Mtvec(v[31..8] @ 0x01)` | **NO** |
| `WrapMcause` | **CEX** | `legalize_mcause`, comment *"Ibex internal interrupts"* | **NO** |
| `WrapMstatus` | **CEX, depth 5** | `legalize_mstatus`, generic but has FS/XS/SD/SXL/UXL | partial |
| `WrapMepc` | **CEX** | masked | ? |
| `WrapPc` | **CEX, depth 5** | — | — |
| **`WrapMie`** | **no counterexample to depth 12** | `legalize_mie` = MEI/MTI/MSI writable only | **YES** |
| **`WrapMscratch`** | **no counterexample to depth 9** | none — a plain register | **YES** |
| **`WrapRegA`** / **`WrapRegB`** | **no counterexample to depth 17** | the register-read lanes; guarded by `h3_ghost_has_reg` | — |

**Read that table again: the two properties that resist refutation are exactly
the two registers whose WARL policy in the Sail model matches Hazard3's.** That
is not a coincidence, and it is the finding of this gate.

**The lowRISC Sail fork hard-codes *Ibex's* WARL policy for `mtvec` and
`mcause`.** `$LOWRISC_SAIL_RISCV_SRC/model/riscv_sys_regs.sail:435-438`:

```sail
function legalize_tvec(o : Mtvec, v : xlenbits) -> Mtvec = {
 // 256 byte aligned, always vectored
 Mk_Mtvec(v[31..8] @ 0x01)
}
```

and `:446-452`:

```sail
function legalize_mcause(v : xlenbits) -> Mcause = {
  // Ibex internal interrupts
  if v[31..30] == 0b11 then
    Mk_Mcause([v with 30..5 = sail_ones(26)])
  else
    Mk_Mcause([v with 30..5 = sail_zeros(26)])
}
```

Hazard3's policies are different, and both are architecturally legal — the
privileged spec makes `mtvec` and `mcause` WARL:

* **`mtvec`.** Hazard3 stores `mtvec_reg <= update_nonconst(mtvec_reg, MTVEC_WMASK)`
  (`hazard3_csr.v:294-295`) and reads back `{BASE[31:2], 1'b0, MODE}`
  (`:860-866`) — **4-byte aligned BASE, and MODE genuinely writable, direct or
  vectored.** Sail forces 256-byte alignment and MODE = vectored, unconditionally.
  The counterexample is a single `csrrci` to `0x305` at the very first query
  (instruction `0x305F9FF3`, depth 5): the two models disagree about the result
  of one CSR write, and the ghost carries the disagreement to the next query.
* **`mcause`.** Hazard3 stores `{mcause_irq, mcause_code[3:0]}` and reads
  `{irq, 27'h0, code}` (`hazard3_csr.v:354-355`, `:836-842`). Sail's legalizer
  smears bits 30..5 to all-ones or all-zeros depending on `v[31:30]`, which is an
  Ibex-specific encoding of its internal interrupt causes.

**This is not a Hazard3 bug and it is not a harness error.** It is a
*specification-configuration* mismatch inherited from the fork: the flow's Sail
model is `github.com/lowrisc/sail-riscv`, not upstream sail-riscv, and two of its
legalizers were specialised to the core it was written for. Ibex's own README
documents `LOWRISC_SAIL_RISCV_SRC` as an overridable path precisely so the model
can be modified.

**It also explains the shape of every other row.** `mie` and `mscratch` are the
only two ghosted registers whose Sail-side write path has no Ibex-specific
content — `legalize_mie` keeps exactly MEI/MTI/MSI, which is precisely Hazard3's
`MIE_WMASK = 32'h888`, and `mscratch` has no legalizer at all. They are the two
that survive. This is about as clean a diagnostic signal as a gate like this can
produce, and it says the harness, the abstraction, the commit point and the ghost
are all doing their job: what is left is a disagreement about *values*, exactly
where design (b) said the comparison would land.

#### The other two Wrap rows, which are ordinary missing lemmas

`WrapPc` and `WrapMepc` fail for the reason Ibex needed ~130 lemmas for: nothing
yet proves that Hazard3's next-PC, jump target and trap-return address agree with
Sail's `nextPC_out` per instruction class. That is the per-instruction template
of Ibex's `thm/riscv.proof`, and it is gate 6's main body of work rather than a
finding.

## 9. What gate 6 (the lemma loop) should target first

In priority order, and each with the evidence from section 5 behind it.

**1. Fix the two Ibex-specific legalizers in the Sail model — before writing a
single lemma.** `legalize_tvec` and `legalize_mcause` encode Ibex's WARL policy,
not Hazard3's, and no amount of lemma-writing can make `WrapMtvec` or
`WrapMcause` true while they do. This is half a day's work, not a research
problem: the flow already supports pointing `LOWRISC_SAIL_RISCV_SRC` at a local
clone (Ibex's `dv/formal/README.md`, "Development Builds"), and the two functions
need Hazard3's policy —

```sail
// mtvec: 4-byte aligned BASE, MODE writable (direct or vectored)
function legalize_tvec(o : Mtvec, v : xlenbits) -> Mtvec =
  Mk_Mtvec(v[31..2] @ 0b0 @ v[0])
// mcause: {irq, 27'h0, code[3:0]}
function legalize_mcause(v : xlenbits) -> Mcause =
  Mk_Mcause(v[31..31] @ sail_zeros(27) @ v[3..0])
```

— transcribed from `hazard3_csr.v:294-295` / `:860-866` and `:354-355` /
`:836-842` respectively. **Add a property for each that the harness's belief about
the DUT's WARL policy is right** (the gate-4 `Abs*IsRdata` pattern), so that the
edit to the specification is checked against the design rather than trusted. Do
not skip that: editing the specification is the one move in this project that can
make a real bug invisible, and it must be done with an obligation attached.
Re-measure `WrapMtvec` and `WrapMcause` immediately after; if they do not move
from "counterexample at depth 5" to "no shallow counterexample", the diagnosis in
section 8c is wrong and everything after it should stop.

**2. Make the Sail model stop splitting misaligned accesses.** Same class of fix
as item 1 and the same half-day: `check_misaligned` already exists at
`riscv_insts_base.sail:315` and is never called. Call it from the `LOAD` and
`STORE` clauses (or, equivalently, guard the split in `checked_mem_read` /
`checked_mem_write`) so that a misaligned access raises
`E_Load_Addr_Align` / `E_SAMO_Addr_Align` instead of becoming two granules. Then
re-measure `MemNoSecondGranule`, `LoadEn` and `StoreEn` — all three should move,
because the trace in section 8c shows one root cause behind all of them. Attach an
obligation to this edit too: `MemNoSecondGranule` **is** that obligation, and it
must go from CEX to no-shallow-CEX.

**3. The operand bypass. This is the root lemma of the memory goals.** Every
address and every store data word the goals compare comes from
`x_addr_sum = x_rs1_bypass + d_addr_offs` (`hazard3_core.v:760-763`), while the
specification computes the same address from `pre_regs_cut[rs1]`. So

```
h3_x_progress -> x_rs1_bypass == pre_regs[d_rs1]   (and the rs2 form)
```

is what `LoadAddr`, `StoreAddr` and `StoreWData` all reduce to. It is core-only —
it proves on `build/core.aig` in seconds, not on the 12 M-clause model — which
makes it exactly the kind of lemma gate 0's two-model split was kept for. Gate 2
already proved the bypass *selects* are one-hot-legal (`BypassSel1Legal` /
`BypassSel2Legal`); this is the value half, and it needs the three-way mux at
`hazard3_core.v:574-582` related to the architectural file.

**4. Decode agreement, for `NoMem` / `MemWe` / `LoadEn` / `StoreEn`.** The
specification's `mem_read` / `mem_write` outputs have to be tied to Hazard3's
`d_memop`. One lemma per memory instruction class, stated over the instruction
bits the specification was handed (`h3_x_instr`), is the shape. Note this is the
one place where the deviation recorded in `h3_goals.svh` — adjudicating
"non-memory instruction" by the specification rather than by a second decoder in
the harness — makes gate 6 *easier*, because there is only one decoder to relate
`d_memop` to.

**5. Then, and only then, the per-instruction template.** Ibex's
`thm/riscv.proof` is ~130 lemmas of "for this instruction class: the RF address
and write-enable are right, the RF data is right, the CSRs are right, the PC is
right". That is the bulk of the work and it is what `WrapPc`, `WrapMepc`,
`WrapRegA` and `WrapRegB` are waiting on. Two Hazard3-specific notes:
`use structure_fast` has no rIC3 equivalent, so expect these to be more expensive
than Ibex's were; and the PC family should be done first, because `WrapPc` gates
the usefulness of everything else.

**6. Reserve the first proof block for machine-written lemmas and always append.**
Plan section 5, still unimplemented, and it costs nothing to do now rather than
after the block exists. The `GATE 5 GOALS` marker already splits the file; put the
lemma block immediately above it.

### Two operational findings gate 6 should inherit

* **BMC before IC3 on the spec-connected model.** IC3 gave no verdict at all in
  30 minutes on the first four goals; BMC refuted six of them in the same wall
  clock. Use `./goals_bmc.sh` to triage, `./goals.sh` only on what survives.
  This is the reverse of the right order for the *lemma* set, where almost
  everything is core-only and IC3 is fast.
* **The spec-connected model costs about 10 s per BMC depth step.** Depth 5 is
  reachable in ~3 minutes, depth 12 in ~15, depth 17 in ~30. That is the budget a
  gate-6 counterexample hunt has to plan against, and it is why lemmas belong on
  `build/core.aig` wherever the soundness argument allows.

#### Goals 2, 3 and 4 — `Load`, `Store`, `NoMem`, and a SECOND specification-configuration defect

| Property | BMC |
|---|---|
| **`NoMem`** | **no counterexample to depth 12** |
| `MemNoSecondGranule` | **CEX** |
| `LoadEn` | **CEX** |
| `StoreEn` | **CEX** |
| **`MemWe`**, **`LoadAddr`**, **`StoreAddr`**, **`StoreBe`**, **`StoreWData`** | **no counterexample** (all five hit the 900 s cap) |

**Goal 4, `NoMem`, is the one goal of the four with no counterexample.** "An
instruction the specification says touches no memory causes Hazard3 to issue no
data-side bus transfer" survives BMC to depth 12. It is not proved — that needs
IC3 — but nothing shallow refutes it.

**The `Load` / `Store` failures share one root cause, and it is a defect in the
Sail configuration that gate 4 introduced and mis-justified.** `MemNoSecondGranule`
is the property that found it, which is exactly what gate 4's handoff item 7
asked it to do ("state it as a property; if it fails, something about the
alignment configuration is wrong rather than the core").

The counterexample, read off the trace at depth 5:

```
 t | spec_en | x_progress | mode | h3_x_instr                       | mem_write | mem_write_snd | h3_mem_aph
 4 |    1    |     1      | IDEX | 11111111111111111010111110100011 |     1     |       1       |     0
```

`0xFFFAFA3` decodes as **`sw x31, -1(x31)`** — opcode `0100011` (STORE),
funct3 `010` (SW), rs1 = rs2 = x31, imm = 0xFFF = −1. The base register is a free
input, so the effective address is misaligned. And then:

* **Sail splits it**: `spec_mem_write` *and* `spec_mem_write_snd` are both high —
  two granules, exactly the behaviour Hazard3 does not have;
* **Hazard3 traps it**: `h3_mem_aph` is 0, because `x_unaligned_addr`
  (`hazard3_core.v:613-616`) suppresses `bus_aph_req_d` and the instruction takes
  `EXCEPT_STORE_ALIGN` instead.

**Why, and this is the finding.** Gate 4 set
`sail_plat_enable_misaligned_access` from 1 to 0 in `spec/stub.sv` and recorded
that this stops the specification producing a memory operation where the DUT
produces a trap. **It does not, because in this Sail fork the flag is dead
configuration.** The only function that consults it is `check_misaligned`
(`riscv_insts_base.sail:315`), and a grep over the entire model shows **exactly
one occurrence of that name — the definition itself. It is never called.** The
fork's `STORE` clause (`:375-395`) goes straight to `mem_write_value`, and
`checked_mem_write` / `checked_mem_read` split on alignment *unconditionally*:

```sail
if 4 - unsigned(paddr[1..0]) < width then { ... second granule ... }
```

So the specification will always split a misaligned access, whatever the platform
flag says. That is the right behaviour for Ibex — whose LSU splits misaligned
accesses in hardware, which is why Ibex's harness has `alt_lsu.sv` and a whole
second-granule bundle — and it is the wrong behaviour for Hazard3, which traps.

**Consequences, stated precisely:**

* `LoadEn` and `StoreEn` fail for this reason: the specification asks for a
  memory operation that the DUT correctly refuses to perform.
* Gate 4's `stub.sv` comment is **wrong** and is corrected in the file.
* The plan's section 1 claim that Hazard3's trapping of misaligned accesses
  "deletes `alt_lsu.sv` and the whole two-beat bookkeeping" is still true of the
  *harness* — no second-granule machinery was written, and none is needed — but
  it is **not** true of the specification, which still has to be told to stop
  splitting.
* This is **not a Hazard3 bug.** Trapping a misaligned access is explicitly
  permitted (the unprivileged spec makes misaligned support optional), and
  Hazard3's `EXCEPT_LOAD_ALIGN`/`EXCEPT_STORE_ALIGN` is the architecturally
  correct response.

### 8d. The four goals, in the three categories the gate asks for

No goal **proves** yet, which is the expected outcome. What matters is that every
one of them fails for a reason that can be named, and that **none of them is in
the "cannot explain" category**.

| Goal | Status | Reason |
|---|---|---|
| **`Wrap`** — `WrapMtvec`, `WrapMcause` | fails, understood | the Sail fork hard-codes **Ibex's WARL policy** for these two registers (`legalize_tvec`, `legalize_mcause`). Not a missing lemma and not a Hazard3 bug — a specification-configuration defect. Fix is gate 6 item 1. |
| **`Wrap`** — `WrapPc`, `WrapMepc`, `WrapMstatus` | fails, understood | ordinary missing invariants: nothing yet relates Hazard3's next-PC / trap-return / mstatus-trap-update to Sail's, per instruction class. This is the per-instruction template, gate 6 item 5. |
| **`Wrap`** — `WrapMie`, `WrapMscratch`, `WrapRegA`, `WrapRegB` | **no shallow counterexample** (BMC to depth 12 / 9 / 17 / 17) | the two registers whose Sail-side write path has no Ibex-specific content, plus both register-read lanes. Needs IC3 and lemmas to close, but nothing refutes it. |
| **`Load`** — `LoadEn` | fails, understood | **misaligned split**: Sail asks for a load Hazard3 correctly traps. Same root cause as `MemNoSecondGranule`. Fix is gate 6 item 2. |
| **`Store`** — `StoreEn` | fails, understood | same root cause. |
| **`NoMem`** | **no shallow counterexample** (BMC to depth 12) | the strongest of the four. |
| `MemWe` | **no shallow counterexample** | the transfer direction agrees whenever Hazard3 makes a request. |
| `MemNoSecondGranule` | fails, understood | the measurement that found the misaligned-split defect. |
| `LoadAddr`, `StoreAddr`, `StoreBe`, `StoreWData` | **no shallow counterexample** | all four are guarded by `h3_mem_aph` (the DUT actually issued a transfer), the same guard under which `MemWe` and `NoMem` survive. |

**The pattern across the memory goals is worth stating on its own, because it is
diagnostic, and it is complete: 6 out of 6 against 3 out of 3.** Every memory goal
guarded by *"Hazard3 issued a bus transfer"* survives BMC — `NoMem`, `MemWe`,
`LoadAddr`, `StoreAddr`, `StoreBe`, `StoreWData`; every memory goal guarded by
*"the specification asked for a memory operation"* is refuted — `LoadEn`,
`StoreEn`, `MemNoSecondGranule`. That is exactly the signature of a specification that asks
for operations the DUT is right to refuse — which is what the misaligned split
is — and it says the DUT-side half of `Load`/`Store` is in better shape than the
raw pass/fail count suggests.

**Nothing in this gate looks like a Hazard3 bug.** Both findings are on the
specification side, both are architecturally legal differences (WARL policy;
optional misaligned-access support), and in both cases Hazard3's behaviour is the
one the RISC-V specification permits. Gates 0-4 found no Hazard3 bug either.

### 8e. The complete goal measurement

`./goals_bmc.sh 4 25 900` on `build/all.aig`, model `L4690-B110-C6`. Transition
system as rIC3 reports it: **7,938,504 vars, 836,558 inputs, 4,690 latches,
12,454,525 clauses, 6 constraints.**

| Property | BMC verdict | wall (s) | peak RSS |
|---|---|---:|---:|
| `SpecEnUnreach` | CEX | 237.8 | 11.6 GB |
| `SpecEnUnreachIdex` | no CEX (cap) | 900.7 | 17.5 GB |
| `WrapPc` | CEX | 244.8 | 11.6 GB |
| `WrapMstatus` | CEX | 165.8 | 10.1 GB |
| `WrapMie` | no CEX (cap) | 900.5 | 13.4 GB |
| `WrapMcause` | CEX | 161.3 | 10.1 GB |
| `WrapMtvec` | CEX | 169.8 | 9.1 GB |
| `WrapMscratch` | no CEX (cap) | 900.7 | 11.5 GB |
| `WrapMepc` | CEX | 303.3 | 11.5 GB |
| `WrapRegA` | no CEX (cap) | 900.5 | 11.5 GB |
| `WrapRegB` | no CEX (cap) | 900.5 | 11.7 GB |
| `NoMem` | no CEX (cap) | 901.1 | **22.0 GB** |
| `MemWe` | no CEX (cap) | 901.1 | **22.9 GB** |
| `MemNoSecondGranule` | CEX | 153.3 | 8.5 GB |
| `LoadEn` | CEX | 164.3 | 9.4 GB |
| `LoadAddr` | no CEX (cap) | 900.7 | 10.6 GB |
| `StoreEn` | CEX | 155.1 | 8.4 GB |
| `StoreAddr` | no CEX (cap) | 900.7 | 10.6 GB |
| `StoreBe` | no CEX (cap) | 901.1 | 15.5 GB |
| `StoreWData` | no CEX (cap) | 900.9 | 11.4 GB |

**9 refuted, 11 with no counterexample**, four at a time, nothing OOM-killed.
Two numbers worth carrying forward: every refutation landed in **153-303 s**
(so a shallow counterexample is cheap to find and the 900 s cap was generous),
and `NoMem`/`MemWe` peak at **22-23 GB each** — the highest seen in this project,
and the reason gate 4's four-at-a-time rule must not be relaxed on this box
(4 x 23 GB = 92 GB against 123 GB).

### 8f. Two things this gate did NOT do, stated plainly

1. **The goals were checked with BMC only, not IC3.** "No counterexample" in the
   tables above means *no counterexample within the 900 s cap*, which reached
   depths of roughly 9-17 depending on the property. It is **not** a proof. The
   eleven goals in that column are candidates for `./goals.sh` (IC3, unbounded)
   once gate 6's lemmas exist; running IC3 on them now is what produced no
   verdict at all in 30 minutes and caused the method switch recorded in 8c.
2. **The regression sweep was run on `build/core.aig` only, not on
   `build/all.aig`.** Gate 4 ran both. The gate-4 soundness argument covers the
   gap — every property above the `GATE 5 GOALS` marker depends on the
   specification only as free input data, so UNSAT on `core.aig` implies UNSAT on
   `all.aig` — and the three new support lemmas are core-only, mentioning no
   `spec_*` wire at all. But that argument was flagged at gate 4 as "needs
   sign-off before being leaned on", and this gate leans on it. **A full
   `./sweep.sh all 4 <timeout>` should be run before gate 6 starts**, if only to
   keep the two-model claim measured rather than argued. The 12 spec-dependent
   negative controls were likewise not re-run through `neg_check_all.sh` on a
   specification-connected model at this gate; gate 4's run of them stands, and
   the seven new spec-dependent controls added here have been added to that
   script's list but not yet executed against `build/negall.aig`.

