# Pinned sources

| component | repository | commit |
|---|---|---|
| Hazard3 RTL | https://github.com/Wren6991/Hazard3 | 8af992930f71a69b0e06c38734c1094f41a05ca0 |
| Sail model base | https://github.com/lowRISC/sail-riscv (branch ibex) | 54d9ed690937d0aa11788aefc41c59c4f3bef2c0 |
| Ibex formal flow (tool environment, harness origin) | https://github.com/lowRISC/ibex | 405c6d1d8220a18b2f9196141167a5875422dee4 |

The Sail model used is the base commit plus the three patches in this directory
(Gate 6, 7, 8), applied in order. The Hazard3 RTL used is the pinned commit with
the six conformance patches applied by harness/patch_hazard3_rtl.sh
(H3_CONFORMANCE=1). Tool versions come from the Ibex flake lock (ibex.flake.lock).
