// ===========================================================================
// Round 47.  CtiLockMNoExcept (round 46) was REFUTED for real: a late data-
// phase bus fault turns the stalled M load into an excepting instruction
// while the locked jump behind it is still held (the trap then ends the lock a
// cycle later).  So the operand ties cannot be silent whenever M excepts; they
// exclude only the case where the bypass would select the excepting
// instruction's dead slot (its rd is the register being read).  With
// CtiLockNoRawHazard (round 43) a locked jump never reads M's rd, so under a
// lock the ties always speak.
// ===========================================================================
logic h3_cti_rs1_bypass_is_pre_regs_v3, h3_cti_rs2_bypass_is_pre_regs_v3;
assign h3_cti_rs1_bypass_is_pre_regs_v3 =
    cpu.core.d_starved || !(|cpu.core.d_rs1) || cpu.core.x_stall_on_raw ||
    ((cpu.core.xm_except != H3R36_EXCEPT_NONE) && (cpu.core.xm_rd == cpu.core.d_rs1)) ||
    (cpu.core.x_rs1_bypass == pre_regs[cpu.core.d_rs1]);
assign h3_cti_rs2_bypass_is_pre_regs_v3 =
    cpu.core.d_starved || !(|cpu.core.d_rs2) || cpu.core.x_stall_on_raw || h3_cti_x_is_store ||
    ((cpu.core.xm_except != H3R36_EXCEPT_NONE) && (cpu.core.xm_rd == cpu.core.d_rs2)) ||
    (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);
`include "h3_cti_round48.svh"
