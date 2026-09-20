# Pinned sources

| component | repository | commit |
|---|---|---|
| Hazard3 RTL | https://github.com/Wren6991/Hazard3 | 8af992930f71a69b0e06c38734c1094f41a05ca0 (tag v1.1.1, head of `stable`) |
| Sail model base | https://github.com/lowRISC/sail-riscv (branch ibex) | 81a266b6f65365b34180af7b91708265da653878 (the revision Ibex's dv/formal flake.lock pins; the working repository on the proof machine imported it as local commit 54d9ed69, content-identical) |
| Ibex formal flow (tool environment, harness origin) | https://github.com/lowRISC/ibex | 405c6d1d8220a18b2f9196141167a5875422dee4 |

The Sail model used is the base commit plus the three patches in this directory
(Gate 6, 7, 8), applied in order. The Hazard3 RTL used is the pinned commit with
the six conformance patches applied by harness/patch_hazard3_rtl.sh
(H3_CONFORMANCE=1). Tool versions come from the Ibex flake lock (ibex.flake.lock).

## Tool versions

From the Ibex flake's `oss-dev` shell at the pinned Ibex commit, as reported on
the reproduction machine (2026-09-20): rIC3 1.4.1, Yosys 0.62 (with the
lowRISC yosys-slang fork and the `yosys_formal` passes in `harness/`), Sail
0.20.1 (lowRISC fork, SystemVerilog back end), psgen 20250805, cargo nightly
2025-07-29 (for aig-manip).
