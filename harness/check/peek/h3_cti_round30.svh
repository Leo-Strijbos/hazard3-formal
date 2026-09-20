// ===========================================================================
// Round 30.  Two ties the RegMatch-V2 CTIs exploit (round28-CtiRegMatchV2_01):
// the follower holds `csrrci x31, 0xfff` -- an UNSPECIFIABLE CSR -- yet
// h3_has_ghost is still 1, and the pipe's xm_memop reads LBU for an
// instruction that is no load, so the landing value takes the rdata leg of
// m_result (core.v:1463-1473).  Neither state is reachable:
//   R30.1  an unspecifiable query sets h3_has_ghost = h3_query_specifiable = 0
//          (h3_follower.svh:428) and nothing re-arms the ghost while that
//          instruction sits in M (a new query needs X to progress, which
//          retires M in the same cycle).  Fetch-error records are unspecifiable
//          too (:420).
//   R30.2  xm_memop is loaded from d_memop with the instruction (core.v);
//          only loads/stores decode a memop (hazard3_decode.v), so a follower
//          record that is neither has xm_memop == MEMOP_NONE (5'h10).
// Both DUT-only.  RegMatch V2 re-submitted above them.
// ===========================================================================
logic h3_cti_ghost_dropped_for_unspecifiable;
assign h3_cti_ghost_dropped_for_unspecifiable =
    !h3_fol_valid || (h3_fol_specifiable && !h3_fol_fetch_err) || !h3_has_ghost;
logic h3_fol_is_store;
assign h3_fol_is_store =
    (h3_fol_is32 && (h3_fol_instr[6:0] == 7'h23) &&
     ((h3_fol_instr[14:12] == 3'b000) || (h3_fol_instr[14:12] == 3'b001) || (h3_fol_instr[14:12] == 3'b010))) ||
    (h3_fol_is16 && (h3_fol_c[1:0] == 2'b00) && (h3_fol_c[15:13] == 3'b110)) ||   // C.SW
    (h3_fol_is16 && (h3_fol_c[1:0] == 2'b10) && (h3_fol_c[15:13] == 3'b110));     // C.SWSP
logic h3_cti_fol_memop_none_unless_mem;
assign h3_cti_fol_memop_none_unless_mem =
    !h3_fol_valid || h3_fol_except || h3_fol_is_load || h3_fol_is_store || (cpu.core.xm_memop == 5'h10);
`include "h3_cti_round31.svh"
