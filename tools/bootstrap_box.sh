#!/bin/bash
# bootstrap.sh -- lay out a fresh proof machine from the pinned sources.
# Expects: /opt/verif/ibex (from the warm AMI), this repo's harness/ and tools/
# already copied to /opt/verif/h3formal and /opt/verif/ablation, spec/ patches
# in /opt/verif/h3formal/specpatches/.
set -euo pipefail
cd /opt/verif
echo "ibex: $(git -C ibex rev-parse HEAD)"
[ -d hazard3 ] || git clone -q https://github.com/Wren6991/Hazard3.git hazard3
git -C hazard3 checkout -q 8af992930f71a69b0e06c38734c1094f41a05ca0
echo "hazard3: $(git -C hazard3 rev-parse HEAD)"
cd /opt/verif/h3formal
if [ ! -d sail-riscv-h3 ]; then
  git clone -q --branch ibex https://github.com/lowrisc/sail-riscv.git sail-riscv-h3
  cd sail-riscv-h3 && git checkout -q 81a266b6f65365b34180af7b91708265da653878
  git -c user.name=repro -c user.email=repro@localhost am -q ../specpatches/000*.patch
  cd ..
fi
echo "sail-riscv-h3: $(git -C sail-riscv-h3 log --oneline | head -4 | tr '\n' '|')"
[ -d aig-manip ] || cp -r /opt/verif/ablation/aig-manip aig-manip
mkdir -p build results
echo BOOTSTRAP-OK
