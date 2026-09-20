// ===========================================================================
// Round 13.  The trap-window excuse for the trap-CSR ghost ties.
//
// Round 12 refuted CtiGhostTracksMcause (depth 5), CtiGhostTracksPc (depth 5)
// and CtiGhostTracksMepc (depth 6) with ONE mechanism, NOT an RTL bug.  The
// mcause witness (results/cex/round12-CtiGhostTracksMcause/): an illegal
// instruction 0xffffffff leaves X at f4 with h3_spec_en=1 and
// spec_post_mcause=2; at f5 h3_has_ghost=1 and h3_ghost_mcause=2 (the ghost
// took the spec's post value at X-exit) while pre_mcause is still 0 and
// m_trap_enter_vld=1 -- the DUT writes mcause/mepc only at the trap-entry
// HANDSHAKE (hazard3_csr.v:180 trapreg_update = trap_enter_vld &&
// trap_enter_rdy && ...), which waits on the frontend.  mscratch/mie/mtvec
// never showed this because their CSR writes land in X, the same cycle the
// ghost updates.
//
// Interrupts do NOT open the window: h3_commit.svh:240
//     h3_spec_en = h3_x_progress || (h3_trap_entry && h3_trap_is_irq)
// queries the spec AT the IRQ handshake, so ghost and DUT update on the same
// edge.  An exception is queried at X-exit and the DUT catches up at the later
// handshake.  So the window is exactly: a NON-interrupt trap pending entry.
// ===========================================================================
logic h3_exc_entry_pending;
assign h3_exc_entry_pending = cpu.core.m_trap_enter_vld && !cpu.core.m_trap_is_irq;

// --- R13.1  the bridge: no query while an exception is pending entry --------
// The excused ties below are no longer strictly stronger than their goals, so
// the goals need this: h3_x_progress cannot fire during the window (M holds
// the excepting instruction and x_stall follows m_stall, core.v:1391-1393; at
// the handshake cycle the pipeline flushes rather than progresses).  DUT-only,
// so the core pre-screen decides it.  If it refutes, the witness shows the
// case the excuse must widen to.
logic h3_cti_no_progress_during_exc_entry;
assign h3_cti_no_progress_during_exc_entry =
    !h3_x_progress || !h3_exc_entry_pending;

// --- R13.2-R13.4  the excused ghost ties -------------------------------------
logic h3_cti_ghost_tracks_mcause_v2;
assign h3_cti_ghost_tracks_mcause_v2 =
    !h3_has_ghost || h3_exc_entry_pending || (pre_mcause == h3_ghost_mcause);
logic h3_cti_ghost_tracks_mepc_v2;
assign h3_cti_ghost_tracks_mepc_v2 =
    !h3_has_ghost || h3_exc_entry_pending || (pre_mepc == h3_ghost_mepc);
logic h3_cti_ghost_tracks_pc_v2;
assign h3_cti_ghost_tracks_pc_v2 =
    !h3_has_ghost || h3_exc_entry_pending || (pre_pc == h3_ghost_pc);

// --- R13.5/R13.6  the compressed predecode twins, corrected ------------------
// Round 12's CtiRs{1,2}PredecodeAgreesCir16 timed out on all.aig.  Their CTI
// (results/icti/round12-CtiRs1PredecodeAgreesCir16) is NOT a transcription
// error: h3_c_rs1_fine and the RTL's own f_rs1_fine agree (both 9 for the
// c.slli x9 at f1).  The defect was MY GUARD.  cir_vld is a BINARY count of
// valid halfwords (hazard3_frontend.v:52,661,674 -- min(level,2), asserted
// <= 2), so for a 16-bit instruction "the low half is valid" is |fd_cir_vld,
// NOT fd_cir_vld[0]: with both halves valid (2'b10) bit 0 is CLEAR and the
// round-12 lemma excused every full-CIR state, leaving d_rs1_predecoded free
// exactly where the CTI needed it.  (Round 9's 32-bit guard !fd_cir_vld[1] is
// correct as written: bit 1 <=> count 2 <=> a whole 32-bit word.)
// Also adopted: Hazard3's own consistency assertion (core.v:559-567) is guarded
// `if (rst_n && !x_stall)`; d_rs1_predecoded latches only on
// `d_starved || !x_stall` (core.v:518-522) and the select register consumes
// d_rs1_predecoded_NXT, so a stale register during a stall is never observed.
// The tie is therefore stated for !x_stall, matching the RTL.
logic h3_cti_rs1_predecode_agrees_cir16_v2;
assign h3_cti_rs1_predecode_agrees_cir16_v2 =
    cpu.core.fd_cir_is_32bit || !(|cpu.core.fd_cir_vld) || cpu.core.x_stall ||
    (cpu.core.d_rs1_predecoded == h3_c_rs1_fine);
logic h3_cti_rs2_predecode_agrees_cir16_v2;
assign h3_cti_rs2_predecode_agrees_cir16_v2 =
    cpu.core.fd_cir_is_32bit || !(|cpu.core.fd_cir_vld) || cpu.core.x_stall ||
    (cpu.core.d_rs2_predecoded == h3_c_rs2_fine);
`include "h3_cti_round14.svh"
