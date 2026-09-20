# Tools

Scripts that drove the proof. Paths default to the proof machine's layout
(`/opt/verif/h3formal` for the harness, `/opt/verif/ibex` for the tool flake,
`/opt/verif/ablation` for this directory, `/var/tmp/h3loop.log` for the log);
the runner and the reproduce script take `H3FORMAL`, `IBEX`, `TOOLS` and `LOG`
from the environment. `aig-manip/` is lowRISC's AIGER tool from the Ibex flow
(Apache-2.0), with small local additions; the harness Makefile builds it.

## Running proofs

| tool | what it does |
|---|---|
| `reproduce_prove.sh` | the portable full sweep: build both models, log the axiom, pre-screen every lemma on the core model, IC3 on the step-0 stragglers, k-induction on the rest on the full model, the goals, then a chain check per goal. What `reproduce.sh` runs. |
| `bootstrap_box.sh` | lays out a fresh machine from the pinned commits (Hazard3, lowRISC sail-riscv plus the three spec patches, aig-manip). |
| `h3round_v41.sh` | one round of the lemma loop: insert candidates at a layer, core pre-screen, full-model proof with the induction-counterexample analysis in parallel, goals CTI-first, strip failures and re-prove survivors above the lowest stripped layer. Its header records the rules and why each exists. |
| `reprove_all2.sh` | the model-change sweep as it ran on the proof machine after the mtvec fix (log rotation, waits for the previous round). Kept as the record; use `reproduce_prove.sh`. |
| `step0_ic3.sh` | IC3 pass over the step-0 lemmas that do not prove by k-induction on the full model. |
| `regprobe.sh` | prove one property against the current model outside a round, emitting a `PROBE` line the chain checker accepts. |
| `h3step.sh` | print the layer a property lives at, read from the ywmap without entering the Nix shell (whose banner pollutes command substitution). |
| `h3insert.py` | insert a batch of candidate lemmas into `thm/hazard3.proof` at a new layer, or remove named ones. |
| `ywstrip.py` | retire properties in a ywmap in place so `aig-manip select` never uses them as constraints. |

## Reading results

| tool | what it does |
|---|---|
| `chain_check3.py` | the chain of custody: for a goal, reconstruct the constraint set present at its proof line from the log's insert/remove events, check each constraint is present and validly proven (recursively), and print `PROVEN`, `PROVEN MODULO AXIOMS [...]` or `STALE`. |
| `check_model.py` | refuse a model whose property set has drifted from the proof text. |
| `make_timeline.py`, `timeline.py` | one markdown row per round from the log (docs/timeline.md). |

## Counterexamples

| tool | what it does |
|---|---|
| `aigicti.py` | build the inductive-step model for a property at k, so BMC on it yields a real counterexample to induction. |
| `witness.sh`, `corewitness.sh` | BMC witness of a refuted candidate from its select file, rendered to VCD and a report. |
| `coreicti.sh` | induction counterexample of a DUT-only candidate on the core model. |
| `h3ctirep.py` | render a counterexample VCD as the report the lemma writer reads: failing obligations per frame, harness predicates false in the final frame, signals that changed. |
| `vcd_summary.py`, `ctisum.py`, `vcdtab.py`, `h3frames.py` | smaller VCD readers used while diagnosing. |
