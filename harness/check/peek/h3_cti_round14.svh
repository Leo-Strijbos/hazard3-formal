// ===========================================================================
// Round 14.  The frontend register-pair tie the compressed predecode needs.
//
// Rounds 12 and 13 both timed out CtiRs{1,2}PredecodeAgreesCir16(V2) with the
// same ICTI shape: the CIR's low halfword changes while x_stall = 1 and
// !d_starved, with no x_jump_req and no trap pending.  The round-13 CTI
// (results/icti/round13-CtiRs1PredecodeAgreesCir16V2) finally shows why:
//     f0  buf_level = 0   cir_vld = 1   cir_use = 0   jump_now = 0
//         fifo_pop = 1    fetch_data_vld = 1   level_next_no_fetch = 0
// buf_level = 0 puts the incoming fetch into slot 0 (hazard3_frontend.v:638-642,
// the last arm of buf_shifted_plus_fetch fires when level_next_no_fetch == 0),
// so the CIR is RELOADED, while cir_vld = 1 tells decode it is not starved, so
// d_rs1_predecoded never re-latches (core.v:518-522).  That pair of values is
// unreachable: buf_level and cir_vld are two registers written from the SAME
// value on the SAME edge --
//     :660  buf_level <= buf_level_next;
//     :661  cir_vld   <= buf_level_next & ~(buf_level_next >> 1);
// (reset: :654 buf_level <= 0, :655 cir_vld <= 0), so in every reachable state
// cir_vld == buf_level & ~(buf_level >> 1) == min(buf_level, 2).  Induction
// treats them as independent.  This tie restores the relation; it is DUT-only
// and 1-inductive by construction.
// ===========================================================================
logic h3_cti_cir_vld_tracks_buf_level;
assign h3_cti_cir_vld_tracks_buf_level =
    cpu.core.frontend.cir_vld ==
    (cpu.core.frontend.buf_level & ~(cpu.core.frontend.buf_level >> 1));
`include "h3_cti_round15.svh"
