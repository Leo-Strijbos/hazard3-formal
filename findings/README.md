# Findings

Six divergences between Hazard3 (pinned commit, see spec/PINS.md) and the
RISC-V Sail model, each found as a machine-checked counterexample of the
equivalence proof and each fixed in the RTL or spec copy under proof.

| # | file | side | status |
|---|---|---|---|
| 1 | FINDING_C_ADDI4SPN.md | Hazard3 | fix in patch_hazard3_rtl.sh; not yet reported |
| 2 | FINDING_MPRV.md | Hazard3 | fix in patch_hazard3_rtl.sh; not yet reported |
| 3 | FINDING_MEICONTEXT.md | Hazard3 | fix in patch_hazard3_rtl.sh; not yet reported |
| 4 | FINDING_FENCE_FIELDS.md | Hazard3 | fix in patch_hazard3_rtl.sh; not yet reported |
| 5 | FINDING_MTVEC_VECTORED_OR.md | Hazard3 (documented behaviour) | fix in patch_hazard3_rtl.sh; not yet reported |
| 6 | FINDING_SPEC_TW.md | Sail (lowRISC fork, old revision; fixed upstream) | fix in spec/0003-Gate-8-*.patch; not yet reported |

The witness traces cited inside findings 1 to 4 and 6 were produced on the
pre-fix models and are not carried in this repository (only their BMC logs
survived the working tree); `upstream/` will hold minimal reproducers and the
issue drafts, regenerated from the pinned RTL, before anything is filed.
