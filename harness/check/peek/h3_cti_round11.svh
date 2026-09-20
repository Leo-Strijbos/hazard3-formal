// ===========================================================================
// Round 11.  Port the proven chain shape to mtvec -- premise VERIFIED first.
//
// The mie lesson (round 10): before porting, grep EVERY write path to the
// target register.  For mtvec, hazard3_csr.v has exactly two:
//     :289/:292  mtvec_reg <= MTVEC_INIT;                            (reset)
//     :295       mtvec_reg <= update_nonconst(mtvec_reg, MTVEC_WMASK); (CSR write)
// No custom-CSR side door, no trap-entry write.  So unlike mie, "mtvec changes
// only through a CSR write to 0x305" is TRUE of the RTL.
//
// Round 10 also showed the LINK rung (follower post == DUT) is not needed when
// the ghost tie can be reached from the frame pair alone -- CtiGhostTracksMie
// proved at step 21 in 154 s with its link REMOVED.  So this round carries two
// layers, not three: the frame pair, then the ghost tie.  If the ghost tie
// times out, THEN add the link beneath it in round 12.
//
// Plumbing, all pre-existing:
//   pre_mtvec  h3_abs.svh:102-103  = {mtvec_reg[31:2], 1'b0, mtvec_reg[0]}
//              (bit 1 spliced to 0: the WARL reserved bit, pinned on both
//              sides by CtiPastPreMtvecReservedZero / CtiSpecPostMtvecReservedZero
//              at step 2 and CtiGhostMtvecReservedZero at step 3)
//   h3_past_pre_mtvec              h3_abs.svh:428,459
//   h3_x_writes_mtvec              h3_abs.svh:289,294  (csr_wen && addr == 12'h305)
//   h3_past_x_advance_writes_mtvec h3_abs.svh:436,467
//   h3_ghost_mtvec / spec_post_mtvec / h3_fol_spec_post_mtvec in h3_follower.svh
// The goal WrapMtvec (h3_goals.svh:121) is already an obligation in the proof.
// ===========================================================================

// --- R11.1  the DUT's mtvec moves only when an instruction wrote it ---------
logic h3_cti_mtvec_change_is_query;
assign h3_cti_mtvec_change_is_query =
    !h3_abs_past_valid || (pre_mtvec == h3_past_pre_mtvec) ||
    h3_past_x_advance_writes_mtvec;

// --- R11.2  the specification leaves mtvec alone unless told to -------------
// Same shape as the proven mscratch/mie frames; CSR address 12'h305.
logic h3_cti_spec_mtvec_frame;
assign h3_cti_spec_mtvec_frame =
    !h3_spec_en ||
    (h3_spec_mode == H3_MAIN_IFERR) ||
    ((h3_spec_mode == H3_MAIN_IDEX) &&
     (h3_x_instr[6:0]   == 7'h73)   &&
     (h3_x_instr[14:12] != 3'b000)  &&
     (h3_x_instr[31:20] == 12'h305)) ||
    (spec_post_mtvec == pre_mtvec);

// --- R11.3  the ghost tie: the goal in strengthened form ---------------------
logic h3_cti_ghost_tracks_mtvec;
assign h3_cti_ghost_tracks_mtvec =
    !h3_has_ghost || (pre_mtvec == h3_ghost_mtvec);
`include "h3_cti_round12.svh"
