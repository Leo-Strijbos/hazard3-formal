// ===========================================================================
// Round 48.  CtiLockImpliesTakenJump's core CTI (round 47): a locked BEQ with
// d_rs1 = d_rs2 = 0 although the CIR reads x4/x2.  hazard3_decode.v:558-576
// forces the register numbers to x0 only for d_invalid, d_starved,
// d_except_instr_bus_fault or a partial predicted branch (predictor off), so
// the free state is a locked CIR carrying a bus-fault or illegal flag.  A lock
// is asserted by a valid jump that issued x_jump_req (impossible with those
// flags) and the CIR, flags included, is frozen under the lock.
// ===========================================================================
logic h3_cti_lock_cir_clean;
assign h3_cti_lock_cir_clean =
    !cpu.core.decode_u.cir_lock_prev ||
    (!cpu.core.decode_u.d_invalid && !cpu.core.decode_u.d_except_instr_bus_fault);
