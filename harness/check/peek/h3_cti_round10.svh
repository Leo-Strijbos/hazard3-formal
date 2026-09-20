// ===========================================================================
// Round 10.  Port the PROVEN mscratch chain to mie.
//
// WrapMscratch became goal #2 at 00:47 through a four-rung chain:
//     CtiMscratchChangeIsQuery / CtiSpecMscratchFrame  (step 4, the frame pair)
//     CtiFollowerPostIsDutMscratchV2                   (step 18, the link)
//     CtiGhostTracksMscratch                           (step 19, the ghost tie)
//   -> WrapMscratch                                    (step 20)
// The ghost tie is h3_cti_round1.svh:157-158
//     !h3_has_ghost || (pre_mscratch == h3_ghost_mscratch)
// which is STRICTLY STRONGER than the goal (the goal adds an !h3_spec_en
// disjunct), so proving it hands the goal over.
//
// mie is the right CSR to port to next, and the round-9 CTI says so directly:
// results/icti/round9-WrapMcause failed Step20_{WrapMcause,WrapMepc,
// WrapMstatus,WrapPc} together -- and WrapMie was NOT in that set.  The reason
// is structural: trap entry rewrites mepc/mcause/mstatus/pc, so their frame
// lemmas need a trap-window excuse, whereas trap entry touches mstatus.MIE and
// NOT the mie register.  mie therefore changes only through an explicit CSR
// write, exactly like mscratch.
//
// All of the plumbing already exists, so these four are faithful ports with
// mscratch's 12'h340 replaced by mie's 12'h304:
//   pre_mie                      h3_abs.svh:96-97   (= cpu.core.csr_u.mie)
//   h3_past_pre_mie              h3_abs.svh:429,460
//   h3_x_writes_mie              h3_abs.svh:290,296
//   h3_past_x_advance_writes_mie h3_abs.svh:437,468
//   h3_fol_spec_post_mie         h3_follower.svh (latched with the follower)
//   h3_ghost_mie                 h3_follower.svh:374,451
// CtiGhostMieReservedZero is already proved at step 3, so mie's reserved bits
// are pinned on the specification side.
// ===========================================================================

// --- R10.1  the DUT's mie moves only when an instruction wrote it ----------
// Port of h3_cti_mscratch_change_is_query (h3_cti_round2.svh:22-25) onto the
// h3_abs helper pair that already exists for mie.
logic h3_cti_mie_change_is_query;
assign h3_cti_mie_change_is_query =
    !h3_abs_past_valid || (pre_mie == h3_past_pre_mie) ||
    h3_past_x_advance_writes_mie;

// --- R10.2  the specification leaves mie alone unless told to --------------
// Port of h3_cti_spec_mscratch_frame (h3_cti_round2.svh:36-44).  Same shape,
// same reasoning: opcode 7'h73 forces insn[1:0] == 2'b11 so a compressed
// instruction takes the frame branch correctly, funct3 != 000 excludes
// ECALL/EBREAK/MRET, and the CSR address is mie's 12'h304.
logic h3_cti_spec_mie_frame;
assign h3_cti_spec_mie_frame =
    !h3_spec_en ||
    (h3_spec_mode == H3_MAIN_IFERR) ||
    ((h3_spec_mode == H3_MAIN_IDEX) &&
     (h3_x_instr[6:0]   == 7'h73)   &&
     (h3_x_instr[14:12] != 3'b000)  &&
     (h3_x_instr[31:20] == 12'h304)) ||
    (spec_post_mie == pre_mie);

// --- R10.3  the link: DUT mie already equals the specification's post ------
// Port of h3_cti_follower_post_is_dut_mscratch_v2 (h3_cti_round6.svh:36-39),
// fetch-error excuse included for the same reason.
logic h3_cti_follower_post_is_dut_mie;
assign h3_cti_follower_post_is_dut_mie =
    !h3_fol_valid || h3_fol_fetch_err ||
    (pre_mie == h3_fol_spec_post_mie);

// --- R10.4  the ghost tie, which is the goal in strengthened form ----------
// Port of h3_cti_ghost_tracks_mscratch (h3_cti_round1.svh:157-158).
logic h3_cti_ghost_tracks_mie;
assign h3_cti_ghost_tracks_mie =
    !h3_has_ghost || (pre_mie == h3_ghost_mie);
`include "h3_cti_round11.svh"
