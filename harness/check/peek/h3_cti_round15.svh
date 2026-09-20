// ===========================================================================
// Round 15.  The compressed predecode twins, third statement.
//
// V1 (round 12): wrong guard (fd_cir_vld[0] under a BINARY count).
// V2 (rounds 13-14): guard fixed to |fd_cir_vld, but an x_stall EXCUSE added.
// Round 14's core ICTI (results/icti/round14-core-CtiRs1PredecodeAgreesCir16V2)
// shows the excuse itself is the hole: f0 has x_stall = 1, the CIR = 0x4001
// (c.li x0) with h3_c_rs1_fine = 0 and d_rs1_predecoded = 16 -- garbage that
// the excuse permitted -- and at f1 x_stall drops with the CIR UNCHANGED, but
// the register only latches at the END of an unstalled cycle (core.v:518-522,
// d_starved || !x_stall), so it still holds 16 and the tie fails.  In a
// reachable state the register was latched correctly when the instruction
// ENTERED the CIR and simply holds through the stall; the excuse was never
// needed, it only let induction corrupt the stalled state.  So V3 drops it.
// The round-14 tie CtiCirVldTracksBufLevel (step 26, proved) closes the other
// hole (a fetch landing in slot 0 while cir_vld said "not starved").
// ===========================================================================
logic h3_cti_rs1_predecode_agrees_cir16_v3;
assign h3_cti_rs1_predecode_agrees_cir16_v3 =
    cpu.core.fd_cir_is_32bit || !(|cpu.core.fd_cir_vld) ||
    (cpu.core.d_rs1_predecoded == h3_c_rs1_fine);
logic h3_cti_rs2_predecode_agrees_cir16_v3;
assign h3_cti_rs2_predecode_agrees_cir16_v3 =
    cpu.core.fd_cir_is_32bit || !(|cpu.core.fd_cir_vld) ||
    (cpu.core.d_rs2_predecoded == h3_c_rs2_fine);
`include "h3_cti_round17.svh"
