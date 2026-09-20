// ===========================================================================
// Round 17.  First round on the FIXED model (fix1, 2026-09-19 09:35: MPRV,
// meicontext, FENCE rs1/rd conformance patches; Sail Gate 8 TW).
//
// fix1's goal sweep: WrapMstatus/WrapMcause/WrapMepc/WrapPc no longer refute
// from reset -- they show k=1 induction CTIs that fail TOGETHER
// (results/icti/fix1-WrapMstatus: pre_mstatus 0x1880 -> 0x1888 while an MRET
// sits in M with xm_except == EXCEPT_MRET; the ghost keeps 0x1880).  Trap
// EXIT writes mstatus at the same handshake as trap entry
// (hazard3_csr.v:180-182: trapreg_update_exit = trap_enter_vld &&
// trap_enter_rdy && except == EXCEPT_MRET), and m_trap_is_irq is 0 for an
// MRET, so round 13's window h3_exc_entry_pending ALREADY covers it.  mstatus
// therefore takes exactly the round-13 V2 shape.  Round 13's McauseV2 was
// REFUTED in depth 6 by the FENCE bug (0xf150020f) and MepcV2/PcV2 timed out
// beside it; all three are re-submitted unchanged on the fixed model.
//
// Both mstatus CTIs also show MPRV/TW garbage in pre_mstatus (0x00221888 in
// fix1-WrapPc): after the fix mstatus_mprv/mstatus_tw are never written with
// U_MODE = 0, and legalize_mstatus (Gate 8) masks both on the spec side, so
// bit 17 and bit 21 are hardwired 0 on both sides and the ghost inherits it.
// ===========================================================================

// --- R17.1  DUT: MPRV (17) and TW (21) read-only 0 (FINDING_MPRV, post-fix)
logic h3_cti_mstatus_hardwired_zero;
assign h3_cti_mstatus_hardwired_zero = !pre_mstatus[21] && !pre_mstatus[17];

// --- R17.2  spec: the same two bits after legalize_mstatus (Gate 8) --------
logic h3_cti_spec_post_mstatus_hardwired_zero;
assign h3_cti_spec_post_mstatus_hardwired_zero =
    !h3_spec_en || (!spec_post_mstatus[21] && !spec_post_mstatus[17]);

// --- R17.3  spec-side mstatus frame -----------------------------------------
// Same shape as the mcause frame (h3_cti_round12.svh) with mstatus's 12'h300,
// the trap indicator (spec_post_mepc == pre_pc: every trap, interrupts
// included, moves MIE -> MPIE), and MRET (32'h30200073, no compressed form)
// which moves MPIE -> MIE.
logic h3_cti_spec_mstatus_frame;
assign h3_cti_spec_mstatus_frame =
    !h3_spec_en ||
    (h3_spec_mode == H3_MAIN_IFERR) ||
    ((h3_spec_mode == H3_MAIN_IDEX) &&
     (h3_x_instr[6:0]   == 7'h73)   &&
     (h3_x_instr[14:12] != 3'b000)  &&
     (h3_x_instr[31:20] == 12'h300)) ||
    (spec_post_mepc == pre_pc) ||
    (h3_x_instr == 32'h30200073) ||
    (spec_post_mstatus == pre_mstatus);

// --- R17.4  ghost: inherits the hardwired zeros from R17.2 ------------------
logic h3_cti_ghost_mstatus_hardwired_zero;
assign h3_cti_ghost_mstatus_hardwired_zero =
    !h3_has_ghost || (!h3_ghost_mstatus[21] && !h3_ghost_mstatus[17]);

// --- R17.5  the excused ghost tie for mstatus (round-13 V2 shape) ----------
logic h3_cti_ghost_tracks_mstatus_v2;
assign h3_cti_ghost_tracks_mstatus_v2 =
    !h3_has_ghost || h3_exc_entry_pending || (pre_mstatus == h3_ghost_mstatus);
`include "h3_cti_round18.svh"
