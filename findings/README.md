# Findings

Six divergences between Hazard3 (pinned commit, see spec/PINS.md) and the
RISC-V Sail model, each found as a machine-checked counterexample of the
equivalence proof and each fixed in the RTL or spec copy under proof.

| # | file | side | status |
|---|---|---|---|
| 1 | FINDING_C_ADDI4SPN.md | Hazard3 | reproduced in simulation on v1.1.1 and develop; draft issue in upstream/; not yet filed |
| 2 | FINDING_MPRV.md | Hazard3 (U_MODE=0) | reproduced in simulation on v1.1.1; draft issue in upstream/; not yet filed |
| 3 | FINDING_MEICONTEXT.md | Hazard3 (EXTENSION_XH3IRQ=0) | reproduced in simulation on v1.1.1; draft issue in upstream/; not yet filed |
| 4 | FINDING_FENCE_FIELDS.md | Hazard3 | reproduced on v1.1.1; already fixed on develop (6adda670, 2026-08-22, found independently by the maintainer with riscv-arch-test); not filed |
| 5 | FINDING_MTVEC_VECTORED_OR.md | Hazard3 (documented behaviour) | reproduced in simulation on v1.1.1 and develop; draft issue (conformance question) in upstream/; not yet filed |
| 6 | FINDING_SPEC_TW.md | Sail (lowRISC fork, branch ibex) | present at branch head; fixed in riscv/sail-riscv 8de2591 (2025-02-19); draft issue in upstream/; not yet filed |

The BMC witness traces cited inside findings 1 to 4 and 6 were produced on the
pre-fix proof models and are not carried in this repository (only their BMC
logs survived the working tree). Each Hazard3 finding is instead reproduced
independently of the proof, on Hazard3's own CXXRTL testbench at v1.1.1, by a
hand-assembled program in `upstream/repro/`; the same programs show that the
conformance patches in `harness/patch_hazard3_rtl.sh` close every divergence
(`upstream/repro/out-fixed/`). Hazard3's Contributing.md rules out reports that
suggest RTL changes, so the issue drafts describe behaviour only.
