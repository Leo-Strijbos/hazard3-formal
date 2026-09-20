// ===========================================================================
// Round 26.  What RegMatch needs beneath it (from round 24's CTIs).
//
// results/icti/round24-CtiRegMatch04 (k=1): M holds an instruction with
// xm_except = STORE_FAULT and h3_fol_except = 1, yet the follower record
// carries a specification write to its rd (h3_fol_spec_wX_en, addr 4) and
// the ghost holds that value; the DUT never writes (m_reg_wen needs
// xm_except == NONE), so when M empties the excuse ends and reg 4 differs.
// In a reachable trace this cannot happen: an exception raised AT X means the
// specification trapped on the same query and wrote nothing; a fault raised
// LATE (bus error in M, gate 5) clears the whole ghost on the same edge
// (h3_follower.svh, h3_fol_valid && h3_mem_fault) and the trap-entry bridge
// (CtiNoProgressDuringExcEntry, step 25) keeps a new query from re-arming it
// while the faulted instruction sits in M.
//   R26.1  the x0-masked form of round 24's refuted en-agreement rung
//   R26.2  DUT exception at X  =>  no specification register write
//   R26.3  excepting follower with a spec write  =>  ghost dropped
// then RegMatch01..31 re-submitted above them.
// ===========================================================================
logic h3_cti_fol_spec_wx_en_is_rd_v2;
assign h3_cti_fol_spec_wx_en_is_rd_v2 =
    !h3_fol_clean_write || ((h3_fol_spec_wX_en && (|h3_fol_spec_wX_addr)) == (|h3_fol_rd));
logic h3_cti_fol_x_except_no_spec_write;
assign h3_cti_fol_x_except_no_spec_write =
    !h3_fol_valid || !h3_fol_x_except || !h3_fol_spec_wX_en;
logic h3_cti_ghost_dropped_for_excepting_write;
assign h3_cti_ghost_dropped_for_excepting_write =
    !h3_fol_valid || !h3_fol_except || !h3_fol_spec_wX_en || !h3_has_ghost;

// --- R26.4  CSR-read value, x0-guarded (round 25's CtiWbCsr refuted at depth 5:
// csrrwi x0, mip, 31 -- rd = x0, so the DUT decodes d_csr_ren = 0 and never
// reads the CSR (xm_result is the ALU's value), while Sail hands wX(0) the old
// mip.  Vacuous for rd = x0 on the DUT side; the other classes survived the
// same hole only because their xm_result is computed regardless of rd.) ------
logic h3_cti_wb_csr_v2;
assign h3_cti_wb_csr_v2 =
    !h3_fol_clean_write || !h3_fol_is_csr || !h3_fol_csr_checkable ||
    !h3_fol_spec_wX_en || !(|h3_fol_spec_wX_addr) || (cpu.core.xm_result == h3_fol_spec_wX);
`include "h3_cti_round27.svh"
