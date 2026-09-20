// ===========================================================================
// Round 44.  CtiLockImpliesTakenJump's core CTI (round 43): a locked BEQ whose
// registered read-port data for rs1 (regs.rdata1, read one cycle earlier from
// the predecoded address) differs from mem[rs1] in the pre-state, so
// x_branch_cmp flips a cycle later with no write to rs1.  CtiRs1BypassIsPreRegs
// (round 4) pins the bypassed operand to pre_regs only at h3_x_progress; the
// lock needs it in every cycle the CIR holds an instruction.  Hazard3 issues
// the register read from the frontend's predecode one cycle ahead
// (d_rs1_predecoded, CtiRs1PredecodeAgreesCir32/16V3), so the always-form is
// a DUT invariant.  pre_regs[] forwards the landing write (h3_abs.svh:224).
// ===========================================================================
logic h3_cti_rs1_bypass_is_pre_regs_always, h3_cti_rs2_bypass_is_pre_regs_always;
assign h3_cti_rs1_bypass_is_pre_regs_always =
    cpu.core.d_starved || !(|cpu.core.d_rs1) || (cpu.core.x_rs1_bypass == pre_regs[cpu.core.d_rs1]);
assign h3_cti_rs2_bypass_is_pre_regs_always =
    cpu.core.d_starved || !(|cpu.core.d_rs2) || (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);
`include "h3_cti_round45.svh"
