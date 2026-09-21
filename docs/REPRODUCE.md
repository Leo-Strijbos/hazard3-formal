# Reproducing the proof

Status: done once. On 2026-09-20 a fresh machine (a new r7i.12xlarge from the
same AMI as the proof machine, holding only the Ibex checkout and its Nix
toolchain) was laid out with `tools/bootstrap_box.sh` and ran
`tools/reproduce_prove.sh`: every one of the 265 lemmas re-proved and all 18
goals came back `PROVEN MODULO AXIOMS [CtiWbMulDiv]`. The log and the chain
outputs are in `results/reproduce/`; details in the last section.

## What you need

- A machine with about 48 cores and 256 GB or more. The full model is 10.4
  million AND gates; 18 rIC3 jobs ran in parallel on an r7i.12xlarge.
- Nix. Everything else comes from the Ibex formal flake.
- The three pinned sources (`spec/PINS.md`):
  - lowRISC Ibex at `405c6d1d`, for its `dv/formal` flake (tools: Yosys,
    yosys-slang, the lowRISC Sail back end, psgen, rIC3, aig-manip).
  - Hazard3 at `8af99293` (v1.1.1).
  - lowRISC sail-riscv, branch `ibex`, at `81a266b6`, with the three patches
    in the top-level `spec/` applied in order (`git am spec/000*.patch`). It
    lives at `harness/sail-riscv-h3`; the Sail glue the build reads is
    `harness/spec/` (main.sail, spec_api.sv, stub.sv, fix_bugs.py).

## Layout on the proof machine

```
/opt/verif/ibex            Ibex checkout; `nix develop /opt/verif/ibex#oss-dev` is the shell
/opt/verif/hazard3         pristine Hazard3 checkout, never modified
/opt/verif/h3formal        this repository's harness/ directory, the working tree
/opt/verif/h3formal/sail-riscv-h3   sail-riscv at the pin plus the three patches
/opt/verif/ablation        this repository's tools/ directory
/var/tmp/h3loop.log        the proof log the chain checker reads
```

`harness/Makefile` sets `LOWRISC_SAIL_RISCV_SRC` to `sail-riscv-h3` so a plain
`make` cannot pick up the unpatched model. `harness/patch_hazard3_rtl.sh` copies
the RTL into `build/hazard3-rtl` and writes `PATCH_MANIFEST`; with
`H3_CONFORMANCE=1` the five conformance patches are applied, which is the model
the results are about.

## Steps

1. Enter the shell: `nix develop /opt/verif/ibex#oss-dev`.
2. Build the models from `harness/`:
   `H3_CONFORMANCE=1 make build/core.aig build/all.aig`. About 40 minutes.
   Check `build/hazard3-rtl/PATCH_MANIFEST` lists the six patch lines.
3. Re-prove everything: `./reproduce.sh` (which runs
   `tools/reproduce_prove.sh`, the portable form of `tools/reprove_all2.sh`,
   the sweep that produced the final results). It builds aig-manip and both
   models, logs the axiom, pre-screens every lemma on the core model,
   re-proves the step-0 stragglers with IC3 (1800 s each), proves the rest on
   the full model with k-induction (600 s), inserts nothing and strips
   nothing, sweeps the 18 goals and prints one `CHAIN <goal>: VERDICT ...`
   line each. It refuses to start on a non-empty log. About three and a half
   hours.
4. Check the chains yourself:
   `python3 tools/chain_check3.py WrapPc` and so on for each goal. The
   expected last line is `VERDICT: PROVEN MODULO AXIOMS [CtiWbMulDiv]`.
   `results/chain/chain_all.txt` is what the original run printed.

## Checking a single lemma

`aig-manip select` extracts one property with its constraint set, and rIC3
proves it:

```
build/aig-manip build/all.aig select build/sel.aig build/all.ywmap <step> <Name>
rIC3 -e kind build/sel.aig
```

`tools/h3round_v41.sh` does this for a list of candidates, with the
counterexample-to-induction analysis in parallel; its header documents the
rules it runs under.

## What is not reproducible from this repository

- The BMC witness traces behind findings 1 to 4 and 6 (only their logs
  survived). The findings are reproduced instead on Hazard3's simulator,
  `findings/upstream/repro/run.sh`, which needs only Yosys and a C++ compiler.
- The bounded multiplier experiment (`results/mulexp` on the proof machine);
  its outcome is recorded in the axiom comment in the proof file.

## The reproduction run of 2026-09-20

Machine: AWS r7i.12xlarge (48 vCPUs, 371 GB), fresh from the AMI that holds
Ibex `405c6d1d` and its Nix toolchain. Tools as reported by the shell: rIC3
1.4.1, Yosys 0.62, Sail 0.20.1, psgen 20250805. Sources: Hazard3 `8af99293`,
lowRISC sail-riscv `81a266b6` plus the three spec patches, this repository's
harness and tools.

| phase | start (UTC) | result |
|---|---|---|
| aig-manip and core model build | 16:58 | ok; PATCH_MANIFEST lists the six conformance patches |
| full model build | 16:58 | ok after two packaging fixes (see below); check_env PASS, both models L=4762 B=286 C=6 |
| core pre-screen, 265 lemmas | 17:01 | done 18:10; 106 proved on the core model, none refuted |
| step-0 IC3, 48 stragglers | 18:10 | done 18:44; 47 within the 1800 s cap, one (AhbDphWdataStable) timed out |
| full-model k-induction, 111 lemmas | 18:44 | done 20:12; 265 of 265 lemmas re-proved, nothing refuted |
| goals, 18 + 2 measure properties | 20:12 | all 18 proved by k-induction, no induction counterexample; SpecEnUnreach refuted at depth 5 as documented, SpecEnUnreachIdex proved |
| chain check per goal | 20:38 | 18 of 18 `PROVEN MODULO AXIOMS [CtiWbMulDiv]`, 266 constraints each |

Wall clock 3 h 40 min. The verdicts were re-derived by hand afterwards from
the saved log with `tools/chain_check3.py` (`results/reproduce/chain_all.txt`).

The one timeout was solver seed variance, not a proof problem: the same lemma
proved in 180 s with `--rseed 7`, 285 s with `--rseed 1234`, 336 s with
`--ic3-inn`, 1992 s at the default seed with a longer cap, and 2578 s with
`--ic3-no-ctg`; only k-induction did not close it in 5400 s. The original runs
had it at 134 s and 263 s. `reproduce_prove.sh` now retries a step-0 timeout
with a second seed.

Two packaging mistakes surfaced and are fixed in the repository: the Sail glue
must be at `harness/spec/` (it had been renamed), and `fix_ywmap.py` must be in
`harness/` where the Makefile runs it after `write_aiger`.

Not part of this run: proof certificates. rIC3 can emit them; that is the next
step for checking without trusting the solver.
