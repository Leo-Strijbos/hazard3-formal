# hazard3-formal

An unbounded formal proof that Hazard3, the RISC-V core in the Raspberry Pi
RP2350, executes instructions the way the RISC-V Sail specification says it
should. The proof covers an RV32IMC + Zicsr, machine-mode-only configuration of
Hazard3 v1.1.1, uses only open-source tools, and closes all 18 of its top-level
goals modulo one explicitly stated axiom (the arithmetic result of the
multiplier/divider). Along the way it found five behaviours of Hazard3 that
differ from the specification, and one place where the specification model
itself was wrong.

The proof is of a *patched* copy of the core: five one-line RTL changes fix the
five divergences, and one two-line change fixes the specification. The shipped
RTL is not equivalent to the Sail model; the shipped RTL with those five changes
is, under the conditions listed below.

The write-up is [`paper/report.pdf`](paper/report.pdf) (source in
[`paper/report.tex`](paper/report.tex)). The proof itself is
[`results/proofs/hazard3.proof.final`](results/proofs/hazard3.proof.final).

## Results

The 18 goals are the goals of lowRISC's and Oxford's Ibex proof, ported to
Hazard3, minus liveness. `Wrap*` says that each time the specification is
queried, its inputs equal its outputs from the previous query, register by
register; `Load*`, `Store*`, `NoMem` and `Mem*` say that the memory requests the
core makes are the ones the specification makes. Together they give trace
equivalence of the architectural state and the memory traffic, for every
sequence of instructions, conditional on instructions continuing to retire.

| goal | what it states | verdict |
|---|---|---|
| WrapPc | PC at each query equals the specification's next PC | proven modulo axiom |
| WrapMstatus, WrapMie, WrapMcause, WrapMtvec, WrapMscratch, WrapMepc | the six checked CSRs agree at each query | proven modulo axiom |
| WrapRegA, WrapRegB | both register-file read operands agree at each query | proven modulo axiom |
| LoadEn, LoadAddr | a load is issued when, and where, the specification loads | proven modulo axiom |
| StoreEn, StoreAddr, StoreBe, StoreWData | a store is issued when, where, with which lanes and which data | proven modulo axiom |
| NoMem | an instruction that touches no memory in the specification makes no data-side transfer | proven modulo axiom |
| MemWe, MemNoSecondGranule | transfer direction agrees; no access is split into a second granule | proven modulo axiom |

"Modulo axiom" means the chain of lemmas beneath the goal contains exactly one
unproven link, `CtiWbMulDiv`: for MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM and
REMU the value the core writes to rd equals the specification's value. Everything
around it is proven: that such an instruction retires, writes rd and only rd, at
the right time, without trapping, and advances the PC. The Ibex proof assumes the
same lemma (its `MType`). The statement is written out in full in the proof file
above `CtiWbMulDiv`.

The proof rests on 265 helper lemmas in 62 layers, each proven by k-induction
with the layers beneath it as constraints (91 spec-free lemmas in the base
layer, 174 found in the lemma loop above it). The verdicts are computed by
[`tools/chain_check3.py`](tools/chain_check3.py), which walks the log and
refuses to call a goal proven if any lemma that was a constraint at proof time
was later refuted, removed, or never proven itself. The 18 verdicts as printed
are in [`results/chain/chain_all.txt`](results/chain/chain_all.txt).

## Findings

Each row is a machine-checked counterexample to the equivalence proof, later
reproduced on Hazard3's own simulator with a program of a few dozen
instructions ([`findings/upstream/repro/`](findings/upstream/repro/)).

| # | behaviour | side | v1.1.1 | develop | status |
|---|---|---|---|---|---|
| 1 | seven reserved `C.ADDI4SPN` encodings (nzuimm = 0, rd' ≠ 0) execute as `addi rd', sp, 0` instead of trapping | Hazard3 | present | present | to be filed |
| 2 | `mstatus.MPRV` is writable and reads back set when `U_MODE = 0`; the spec says read-only 0 | Hazard3 | present | present | to be filed |
| 3 | a write to `meicontext` traps as illegal when `EXTENSION_XH3IRQ = 0` but still modifies `mie` | Hazard3 | present | present | to be filed |
| 4 | `FENCE` with rs1 or rd non-zero raises illegal-instruction; the spec says ignore the fields | Hazard3 | present | fixed 2026-08-22 | rediscovered; not filed |
| 5 | vectored trap entry computes `BASE \| 4·cause`, the spec says `BASE + 4·cause`, and an unaligned BASE is accepted rather than legalised | Hazard3 (documented) | present | present | to be filed as a conformance question |
| 6 | `legalize_mstatus` lets `TW` be set with U-mode absent; the spec says read-only 0 | Sail, lowRISC `ibex` branch | present at branch head | fixed upstream 2025-02-19 | to be filed |

None of the five Hazard3 items can be reached by code a compiler emits, and
numbers 2 and 3 need a non-default configuration. They are conformance
divergences, not exploitable bugs, and item 5 is a documented design choice.
Finding 4 had already been fixed by the maintainer on `develop` from a newer
riscv-arch-test run before this work found it; the other four are still in
both branches. Full write-ups are in [`findings/`](findings/), issue drafts in
[`findings/upstream/`](findings/upstream/).

## Check it yourself

The fastest check is the findings. With Yosys and a C++ compiler:

```
git clone https://github.com/Wren6991/Hazard3 && cd Hazard3 && git checkout 8af99293
../hazard3-formal/findings/upstream/repro/run.sh "$PWD"
```

Each program exits 1 on v1.1.1 (the divergence reproduces) and 0 with the
conformance patches in `harness/patch_hazard3_rtl.sh` applied. No RISC-V
toolchain is needed; the binaries are hand-assembled by `mkrepro.py` and each
comes with a listing.

The proof itself is meant to re-run from the pinned sources with
`reproduce.sh` inside the lowRISC Ibex formal tool environment (a Nix dev
shell): rebuild both models, re-prove every lemma with nothing stripped, print
the 18 chain verdicts. It needs a large machine (the original ran on 48 cores
and 384 GB) and about three hours. The runner scripts still carry the proof
machine's paths and this has not yet been done on a fresh machine;
[`docs/REPRODUCE.md`](docs/REPRODUCE.md) says what to point where.

## Scope

What is verified is a specific build of Hazard3, not the RP2350's. The
configuration is in `harness/check/h3_core_common.svh`.

| in scope | out of scope |
|---|---|
| RV32I, M (sequential multiplier, `MULDIV_UNROLL = 1`), C, Zicsr | A, Zba/Zbb/Zbc/Zbs/Zbkb/Zbkx, Zcb/Zcmp/Zclsd/Zilsd, Zifencei, Xh3 extensions |
| machine mode only | U-mode, PMP, debug, triggers |
| mstatus, mie, mcause, mtvec, mscratch, mepc, misa, ids; one external interrupt, software and timer interrupts | mtval, mcounteren, counters, other CSRs (an access to one drops the comparison until the next query) |
| aligned and misaligned data access, both directions | bus faults on either port (reachable, but the faulting instruction and its trap are not compared: the Sail model has no bus-error channel) |
| every instruction sequence, unbounded, from a common start state | reset correctness; that the instruction executed at a PC was the one fetched from that PC; liveness |

The environment assumptions are Hazard3's own AHB5 slave assumptions with
unbounded stalls, the debug port tied off, and one assumption inherited from the
Ibex proof: the bus returns the data the specification was given. The full list
with justifications is section 6 of [`docs/BRINGUP.md`](docs/BRINGUP.md).

## Layout

```
harness/     the proof harness: SystemVerilog checks, the proof script (thm/), the Sail glue (spec/),
             the Yosys build and the RTL patch script
spec/        pinned commits and the three patches applied to the Sail model
tools/       the round runner, the chain checker, the CTI tools, aig-manip (lowRISC)
results/     the final proof, the chain verdicts, the proof logs of all three model versions
findings/    the six findings, the issue drafts and the simulator reproducers
docs/        the bring-up notes (how the harness was built and validated), the round timeline
paper/       the write-up
```

## Provenance

The harness, the proof structure and the tools are a port of the lowRISC /
Oxford Ibex proof (`ibex/dv/formal`, Louis-Emile Ploix), which this work
reproduced first. The lemma discovery, the proof runs and the findings were
done by an LLM agent (Claude, via Claude Code) driving the tools, with a person
deciding what to attempt, what to accept and what to fix; the paper has a
section on how that went. Hazard3 is by Luke Wren. See `NOTICE` for licences.
