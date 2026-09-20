# Reproducing the proof

Status: a full re-run on a fresh machine (a new instance from the same AMI as
the proof machine, with only the Ibex checkout and its Nix toolchain on it)
was started on 2026-09-20 with `tools/bootstrap_box.sh` and
`tools/reproduce_prove.sh`; its outcome is recorded at the end of this page.

## What you need

- A machine with about 48 cores and 256 GB or more. The full model is 10.4
  million AND gates; 18 rIC3 jobs ran in parallel on an r7i.12xlarge.
- Nix. Everything else comes from the Ibex formal flake.
- The three pinned sources (`spec/PINS.md`):
  - lowRISC Ibex at `405c6d1d`, for its `dv/formal` flake (tools: Yosys,
    yosys-slang, the lowRISC Sail back end, psgen, rIC3, aig-manip).
  - Hazard3 at `8af99293` (v1.1.1).
  - lowRISC sail-riscv, branch `ibex`, at `81a266b6`, with the three patches
    in `spec/` applied in order (`git am spec/000*.patch`).

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
