# Upstream reports

Status of each finding against the projects it concerns. Issues are filed
before this repository is made public; the "filed" column carries the issue
link once it exists.

| # | draft | project | branch state at time of writing | filed |
|---|---|---|---|---|
| 1 | hazard3-1-c-addi4spn-reserved.md | Wren6991/Hazard3 | present on stable (v1.1.1) and develop (ba0c83c6) | not yet |
| 2 | hazard3-2-mstatus-mprv-no-umode.md | Wren6991/Hazard3 | present on stable and develop | not yet |
| 3 | hazard3-3-meicontext-side-effect.md | Wren6991/Hazard3 | present on stable and develop | not yet |
| 4 | hazard3-4-fence-fields-NOT-FILED.md | Wren6991/Hazard3 | fixed on develop by 6adda670 (2026-08-22), independently of this work; still on stable | not filed |
| 5 | hazard3-5-mtvec-vectored-unaligned.md | Wren6991/Hazard3 | present on stable and develop; documented behaviour, filed as a conformance question | not yet |
| 6 | sail-riscv-6-mstatus-tw-no-umode.md | lowRISC/sail-riscv, branch ibex | present at branch head 5fca3f99; fixed in riscv/sail-riscv by 8de2591 (2025-02-19) | not yet |

Hazard3's Contributing.md asks that bug reports contain no suggested changes to
`hdl/`; the drafts describe behaviour only. Our own conformance patches live in
`harness/patch_hazard3_rtl.sh` and are not part of the reports.

## Reproducers

`repro/` holds one program per finding for Hazard3's CXXRTL testbench,
hand-assembled by `mkrepro.py` (no toolchain needed), each with a listing.
Exit code 0 means the core agreed with the Sail model, 1 means the divergence
reproduced. `run.sh <hazard3-checkout>` builds the two testbench
configurations and runs all five.

| program | v1.1.1 (8af99293) | v1.1.1 + our conformance patches | develop (ba0c83c6) |
|---|---|---|---|
| c_addi4spn_reserved | exit 1 | exit 0 | exit 1 (present) |
| fence_rd_nonzero | exit 1 | exit 0 | exit 0 (fixed by 6adda670) |
| mtvec_vectored_unaligned | exit 1 | exit 0 | exit 1 (present) |
| mstatus_mprv_no_umode | exit 1 | exit 0 | exit 1 (present) |
| meicontext_side_effect | exit 1 | exit 0 | exit 1 (present) |

Logs of each run are in `repro/out/` (v1.1.1), `repro/out-fixed/` and
`repro/out-develop/`.
