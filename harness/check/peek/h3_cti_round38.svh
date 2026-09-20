// ===========================================================================
// Round 38.  PC lineage for WrapPc (BRANCH_PREDICTOR = 0: a frontend redirect
// comes only from x_jump_req -- JAL/JALR/taken branch in X -- or from a trap
// handshake, hazard3_core.v:1376-1377; the D-stage PC takes f_jump_target at
// f_jump_now and pc_seq_next otherwise, hazard3_decode.v:213-226).
//   R38.1 CtiJumpTargetAgrees: at a specifiable query whose X instruction
//         requests a jump, the spec's next pc is the DUT's jump target
//         (x_addr_sum & ~1, core.v:908 -- JALR clears bit 0 exactly as Sail).
//   R38.2 CtiSeqNextPcAgrees: at a specifiable query with no jump request and
//         no exception, the spec's next pc is the sequential one.
//   R38.3 CtiGhostTracksPcV4: tracking with the excuse widened to the trap
//         handshake cycle itself (the irq query and the DUT's redirect land on
//         the same edge).  On the unfixed RTL the vectored-irq divergence
//         (FINDING_MTVEC_VECTORED_OR.md) makes this refutable; the CTI/CEX is
//         the point of running it now.
// ===========================================================================
logic h3_x_query_clean;
assign h3_x_query_clean =
    h3_x_progress && h3_query_specifiable && (cpu.core.x_except == H3R36_EXCEPT_NONE);
logic h3_cti_jump_target_agrees, h3_cti_seq_next_pc_agrees;
assign h3_cti_jump_target_agrees =
    !h3_x_query_clean || !cpu.core.x_jump_req || (spec_post_pc == cpu.core.x_jump_target);
assign h3_cti_seq_next_pc_agrees =
    !h3_x_query_clean ||  cpu.core.x_jump_req || (spec_post_pc == pre_nextpc);
logic h3_cti_ghost_tracks_pc_v4;
assign h3_cti_ghost_tracks_pc_v4 =
    !h3_has_ghost || h3_exc_entry_pending || h3_trap_handshake || (pre_pc == h3_ghost_pc);
`include "h3_cti_round39.svh"
