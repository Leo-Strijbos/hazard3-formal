#!/usr/bin/env bash
# Run the five reproducers on Hazard3's own CXXRTL testbench.
#
#   ./run.sh /path/to/Hazard3        # a checkout (v1.1.1 = 8af99293 was used here)
#
# Needs yosys (for write_cxxrtl) and a C++ compiler; no RISC-V toolchain, the
# binaries are produced by mkrepro.py. Builds two testbench configurations:
# the default one, and the checkout's default with U_MODE=0 and EXTENSION_XH3IRQ=0
# (config_nou_noxh3irq.vh here is that file as derived from v1.1.1).
set -euo pipefail
H3=${1:?path to a Hazard3 checkout}
HERE=$(cd "$(dirname "$0")" && pwd)
CXX=${CXX:-clang++}
cd "$H3"
git submodule update --init scripts >/dev/null
sed -e 's/^localparam U_MODE .*/localparam U_MODE              = 0;/' \
    -e 's/^localparam EXTENSION_XH3IRQ .*/localparam EXTENSION_XH3IRQ    = 0;/' \
    test/sim/tb_common/hdl/config_default.vh > test/sim/tb_common/hdl/config_nou_noxh3irq.vh
cd test/sim/tb_cxxrtl
make CLANGXX="$CXX"
make CLANGXX="$CXX" CONFIG=nou_noxh3irq
python3 "$HERE/mkrepro.py" "$HERE"
run() { # run <tb> <program>
  "./$1" --bin "$HERE/$2.bin" --cycles 2000 --logfile /dev/stdout --cpuret && rc=0 || rc=$?
  echo "$2: exit $rc  (0 = agrees with the Sail model, 1 = diverges)"; echo
}
run tb              c_addi4spn_reserved
run tb              fence_rd_nonzero
run tb              mtvec_vectored_unaligned
run tb-nou_noxh3irq mstatus_mprv_no_umode
run tb-nou_noxh3irq meicontext_side_effect
