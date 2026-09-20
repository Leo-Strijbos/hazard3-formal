// ===========================================================================
// Round 29.  Round 27's CtiWbLoad timed out again (900 s, kind depth 23).
// Its CTI (results/icti/round27-CtiWbLoad): the follower's instruction is an
// LHU (0xffffdf83, funct3 101) while the pipe's xm_memop is LBU (5'h04) --
// nothing ties the follower's latched instruction bits to the M-stage memop
// (CtiFollowerMemHasXmMemop was removed in round 2).  Both are DUT/harness
// state, so this is a DUT-only rung: for a load in the follower, xm_memop is
// the decode of that instruction (hazard3_decode.v load arms: funct3 -> LB 2,
// LH 1, LW 0, LBU 4, LHU 3; C.LW / C.LWSP expand to LW).  CtiWbLoad is
// re-submitted one layer above it.
// ===========================================================================
logic [4:0] h3_fol_load_memop;
assign h3_fol_load_memop =
    h3_fol_is16 ? 5'h00 :
    (h3_fol_instr[14:12] == 3'b000) ? 5'h02 :
    (h3_fol_instr[14:12] == 3'b001) ? 5'h01 :
    (h3_fol_instr[14:12] == 3'b010) ? 5'h00 :
    (h3_fol_instr[14:12] == 3'b100) ? 5'h04 :
                                      5'h03;
logic h3_cti_fol_load_memop_matches;
assign h3_cti_fol_load_memop_matches =
    !h3_fol_valid || h3_fol_except || !h3_fol_is_load || (cpu.core.xm_memop == h3_fol_load_memop);
`include "h3_cti_round30.svh"
