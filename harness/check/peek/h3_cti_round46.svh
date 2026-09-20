// ===========================================================================
// Round 46.  Round 45's RAW-guarded operand ties were REFUTED for one more
// real case: M holds an EXCEPTING instruction (xm_except = LOAD_ALIGN in both
// witnesses) that will never write its rd, yet the X bypass mux still selects
// its result slot for a reader of that rd -- harmless, the reader is flushed
// by the trap.  So the ties hold only while M is not excepting.  A CIR lock is
// never asserted while a trap is entering (jump_caused_by_d = f_jump_now &&
// x_jump_not_except, decode.v:151-155) and M's instruction does not change
// under the lock, so "lock => M not excepting" is a DUT invariant.
// ===========================================================================
logic h3_cti_rs1_bypass_is_pre_regs_clean, h3_cti_rs2_bypass_is_pre_regs_clean, h3_cti_lock_m_no_except;
assign h3_cti_rs1_bypass_is_pre_regs_clean =
    cpu.core.d_starved || !(|cpu.core.d_rs1) || cpu.core.x_stall_on_raw ||
    (cpu.core.xm_except != H3R36_EXCEPT_NONE) || (cpu.core.x_rs1_bypass == pre_regs[cpu.core.d_rs1]);
assign h3_cti_rs2_bypass_is_pre_regs_clean =
    cpu.core.d_starved || !(|cpu.core.d_rs2) || cpu.core.x_stall_on_raw || h3_cti_x_is_store ||
    (cpu.core.xm_except != H3R36_EXCEPT_NONE) || (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);
assign h3_cti_lock_m_no_except =
    !cpu.core.decode_u.cir_lock_prev || (cpu.core.xm_except == H3R36_EXCEPT_NONE);
`include "h3_cti_round47.svh"
