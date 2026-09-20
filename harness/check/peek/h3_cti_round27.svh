// ===========================================================================
// Round 27.  Round 25's CtiWbLoad timed out (600 s, kind depth 20).  Its CTI
// (results/icti/round25-CtiWbLoad): M holds an LHU with xm_addr_align = 3 --
// a misaligned halfword -- and xm_except = NONE, so the DUT lane-picks
// bus_rdata_d[31:16] while the specification answered for a different
// access.  Unreachable: Hazard3 raises EXCEPT_LOAD_ALIGN / STORE_ALIGN at X
// for a misaligned halfword/word (x_unaligned_addr, hazard3_core.v), and
// xm_except / xm_addr_align / xm_memop are loaded together at X-exit.
// Stated as a DUT-only invariant of the M stage; CtiWbLoad re-submitted one
// layer above it.  MEMOP codes: LW 0, LH 1, LB 2, LHU 3, LBU 4, SW 5, SH 6,
// SB 7 (hazard3_ops.vh:66-73).
// ===========================================================================
logic h3_cti_xm_mem_aligned;
assign h3_cti_xm_mem_aligned =
    !h3_m_valid || (cpu.core.xm_except != H3_EXCEPT_NONE) ||
    (((cpu.core.xm_memop == 5'h00) || (cpu.core.xm_memop == 5'h05)) ? (cpu.core.xm_addr_align == 2'b00) :
     ((cpu.core.xm_memop == 5'h01) || (cpu.core.xm_memop == 5'h03) || (cpu.core.xm_memop == 5'h06)) ? !cpu.core.xm_addr_align[0] :
     1'b1);
`include "h3_cti_round28.svh"
