// ===========================================================================
// Round 36.  TRAP AGREEMENT -- the lineage for WrapMcause / WrapMepc /
// WrapMstatus / WrapPc.  Round 34 CTI (results/icti/round34-WrapMcause):
// the four goals share one state: an MRET in M with DUT mcause/mepc already
// different from the ghost, excused by h3_exc_entry_pending (which covers
// MRET), then exposed at the next query.  The ghost-tracking rungs for these
// four CSRs (round 13/17 V2) were never proven because nothing said what the
// DUT writes at the trap-entry edge equals what the spec wrote into the ghost
// at the query.  These rungs state exactly that, per CSR and per event:
//   * exception entry  (M holds an excepting instruction; hazard3_csr.v:312-313
//     mepc <- mepc_in, :368-370 mcause <- {irq_next, code_next}, :231-236
//     mstatus.mpie <- mie, mie <- 0, mpp <- m_mode; core.v:1377 pc <- trap_addr)
//   * MRET             (csr.v:221-227 mpie <- 1, mie <- mpie; pc <- mepc;
//     mcause and mepc untouched)
//   * interrupt entry  (the query happens at the handshake edge itself, on the
//     live spec outputs: h3_spec_en = h3_trap_entry && h3_trap_is_irq)
// The follower record for the instruction in M carries the spec's post-state
// (h3_fol_spec_post_*); h3_fol_except is 1 for MRET too (x_except != NONE), so
// the guards split on xm_except.
// ===========================================================================
localparam [3:0] H3R36_EXCEPT_MRET = 4'ha, H3R36_EXCEPT_REFETCH = 4'he, H3R36_EXCEPT_NONE = 4'hf;

// Trustworthy excepting record in M: the ghost is live, the follower holds the
// instruction, the spec could execute it, and it is a real exception (not
// MRET, not REFETCH, not a fetch fault the spec cannot express).
logic h3_fol_trap_rec;
assign h3_fol_trap_rec =
    h3_has_ghost && h3_fol_valid && h3_fol_except && !h3_fol_fetch_err && !h3_fol_spec_int_err &&
    (cpu.core.xm_except != H3R36_EXCEPT_MRET) && (cpu.core.xm_except != H3R36_EXCEPT_REFETCH) &&
    (cpu.core.xm_except != H3R36_EXCEPT_NONE);
logic h3_fol_mret_rec;
assign h3_fol_mret_rec =
    h3_has_ghost && h3_fol_valid && !h3_fol_spec_int_err && (cpu.core.xm_except == H3R36_EXCEPT_MRET);

// mstatus after trap entry / after MRET, computed from the DUT's current
// mstatus in the harness packing (h3_abs.svh:121-126; MPP hardwired 11).
logic [31:0] h3_mstatus_after_trap, h3_mstatus_after_mret;
assign h3_mstatus_after_trap =
    {pre_mstatus[31:13], 2'b11, pre_mstatus[10:8], pre_mstatus[3], pre_mstatus[6:4], 1'b0, pre_mstatus[2:0]};
assign h3_mstatus_after_mret =
    {pre_mstatus[31:13], 2'b11, pre_mstatus[10:8], 1'b1, pre_mstatus[6:4], pre_mstatus[7], pre_mstatus[2:0]};

// --- exception entry: the four agreements over the M residency ---------------
logic h3_cti_trap_mcause_agrees, h3_cti_trap_mepc_agrees, h3_cti_trap_mstatus_agrees, h3_cti_trap_pc_agrees;
assign h3_cti_trap_mcause_agrees =
    !h3_fol_trap_rec || (h3_fol_spec_post_mcause == {28'h0, cpu.core.xm_except});
assign h3_cti_trap_mepc_agrees =
    !h3_fol_trap_rec || (h3_fol_spec_post_mepc == cpu.core.m_exception_return_addr);
assign h3_cti_trap_mstatus_agrees =
    !h3_fol_trap_rec || (h3_fol_spec_post_mstatus == h3_mstatus_after_trap);
assign h3_cti_trap_pc_agrees =
    !h3_fol_trap_rec || (h3_fol_spec_post_pc == cpu.core.m_trap_addr);

// --- MRET: mcause/mepc untouched, mstatus/pc by the MRET rule ----------------
logic h3_cti_mret_mcause_untouched, h3_cti_mret_mepc_untouched, h3_cti_mret_mstatus_agrees, h3_cti_mret_pc_agrees;
assign h3_cti_mret_mcause_untouched =
    !h3_fol_mret_rec || (h3_fol_spec_post_mcause == pre_mcause);
assign h3_cti_mret_mepc_untouched =
    !h3_fol_mret_rec || (h3_fol_spec_post_mepc == pre_mepc);
assign h3_cti_mret_mstatus_agrees =
    !h3_fol_mret_rec || (h3_fol_spec_post_mstatus == h3_mstatus_after_mret);
assign h3_cti_mret_pc_agrees =
    !h3_fol_mret_rec || (h3_fol_spec_post_pc == pre_mepc);

// --- interrupt entry: live spec outputs at the handshake edge ----------------
logic h3_irq_query;
assign h3_irq_query = h3_trap_entry && h3_trap_is_irq && h3_query_specifiable;
logic h3_cti_irq_mcause_agrees, h3_cti_irq_mepc_agrees, h3_cti_irq_mstatus_agrees, h3_cti_irq_pc_agrees;
assign h3_cti_irq_mcause_agrees =
    !h3_irq_query || (spec_post_mcause == {1'b1, 27'h0, cpu.core.csr_u.mcause_irq_num});
assign h3_cti_irq_mepc_agrees =
    !h3_irq_query || (spec_post_mepc == cpu.core.m_exception_return_addr);
assign h3_cti_irq_mstatus_agrees =
    !h3_irq_query || (spec_post_mstatus == h3_mstatus_after_trap);
assign h3_cti_irq_pc_agrees =
    !h3_irq_query || (spec_post_pc == cpu.core.m_trap_addr);

// --- tracking V3: the excuse is exactly the pending window, per CSR ----------
// mcause/mepc are excused only while a real exception is pending (MRET does
// not touch them); mstatus/pc while either an exception or an MRET is pending.
logic h3_exc_window_nomret;
assign h3_exc_window_nomret = h3_exc_entry_pending && (cpu.core.xm_except != H3R36_EXCEPT_MRET);
logic h3_cti_ghost_tracks_mcause_v3, h3_cti_ghost_tracks_mepc_v3, h3_cti_ghost_tracks_mstatus_v3, h3_cti_ghost_tracks_pc_v3;
assign h3_cti_ghost_tracks_mcause_v3  = !h3_has_ghost || h3_exc_window_nomret  || (pre_mcause  == h3_ghost_mcause);
assign h3_cti_ghost_tracks_mepc_v3    = !h3_has_ghost || h3_exc_window_nomret  || (pre_mepc    == h3_ghost_mepc);
assign h3_cti_ghost_tracks_mstatus_v3 = !h3_has_ghost || h3_exc_entry_pending  || (pre_mstatus == h3_ghost_mstatus);
assign h3_cti_ghost_tracks_pc_v3      = !h3_has_ghost || h3_exc_entry_pending  || (pre_pc      == h3_ghost_pc);
`include "h3_cti_round37.svh"
