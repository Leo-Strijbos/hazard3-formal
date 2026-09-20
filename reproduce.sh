#!/bin/bash
# reproduce.sh -- rebuild the two models from the pinned sources, re-prove every lemma
# with nothing stripped, re-check every goal, on a fresh log.
#
# Layout expected (tools/bootstrap_box.sh creates it from the pinned commits):
#   /opt/verif/ibex        lowRISC Ibex at the commit in spec/PINS.md (its dv/formal Nix flake
#                          is the tool environment: yosys, yosys-slang, sail, psgen, rIC3, cargo)
#   /opt/verif/hazard3     Hazard3 at the pinned commit (never modified)
#   /opt/verif/h3formal    this repository's harness/, with sail-riscv-h3/ (lowRISC sail-riscv
#                          at the pin plus spec/*.patch) and aig-manip/ (from tools/) inside it
#   /opt/verif/ablation    this repository's tools/
# Override with H3FORMAL, IBEX, TOOLS, LOG. About three and a half hours on 48 cores / 384 GB;
# 20 GB of RAM per parallel proof.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
export TOOLS=${TOOLS:-$here/tools}
exec bash "$TOOLS/reproduce_prove.sh" "${1:-reproduce}"
