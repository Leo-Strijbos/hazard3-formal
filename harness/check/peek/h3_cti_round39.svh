// ===========================================================================
// Round 39 (first round on the fix2 model).  Round 38 CTIs:
//  * CtiSeqNextPcAgrees: a JAL whose jump the frontend had already accepted
//    under the CIR lock (hazard3_decode.v:155-168) progresses with
//    d_branchcond forced to BCOND_NEVER (decode.v:585-587), so x_jump_req is
//    0 although the spec's next pc is the jump target.  V2 excludes the
//    locked case; CtiLockedJumpTargetAgrees covers it: the operands and the
//    held PC are unchanged, so x_jump_target is still the target that was
//    taken (decode.v:204 update_pc_on_cir_unlock reloads it).
//  * CtiGhostTracksPcV4's only CTI was the vectored-irq divergence, removed by
//    conformance patch #6 (fix2).  Re-submitted unchanged.
// ===========================================================================
logic h3_cti_seq_next_pc_agrees_v2, h3_cti_locked_jump_target_agrees;
assign h3_cti_seq_next_pc_agrees_v2 =
    !h3_x_query_clean || cpu.core.x_jump_req || cpu.core.decode_u.cir_lock_prev ||
    (spec_post_pc == pre_nextpc);
assign h3_cti_locked_jump_target_agrees =
    !h3_x_query_clean || !cpu.core.decode_u.cir_lock_prev || (spec_post_pc == cpu.core.x_jump_target);
`include "h3_cti_round40.svh"
