// ===========================================================================
// Round 45.  Round 44's always-form operand ties were REFUTED for real: while
// X is stalled on a load-use hazard the bypassed operand is the not-yet-landed
// load's slot (a store's rs2 behind LW in M: x_rs2_bypass = xm_result, the
// data is not there yet).  That is what x_stall_on_raw / the store-data path
// exist for, and CtiLockNoRawHazard (round 43) already says a lock never
// coexists with a RAW stall.  So: the operand equals the architectural
// register in every CIR-valid cycle with no RAW stall (rs2: and not a store,
// whose data is bypassed later -- the round-5/7 guards).
// ===========================================================================
logic h3_cti_rs1_bypass_is_pre_regs_noraw, h3_cti_rs2_bypass_is_pre_regs_noraw;
assign h3_cti_rs1_bypass_is_pre_regs_noraw =
    cpu.core.d_starved || !(|cpu.core.d_rs1) || cpu.core.x_stall_on_raw ||
    (cpu.core.x_rs1_bypass == pre_regs[cpu.core.d_rs1]);
assign h3_cti_rs2_bypass_is_pre_regs_noraw =
    cpu.core.d_starved || !(|cpu.core.d_rs2) || cpu.core.x_stall_on_raw || h3_cti_x_is_store ||
    (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);
`include "h3_cti_round46.svh"
