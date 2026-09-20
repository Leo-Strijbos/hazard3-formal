// ===========================================================================
// Round 40.  Round 39 CTIs for CtiLockedJumpTargetAgrees and (after its strip)
// CtiGhostTracksPcV4 share one free state: decode_u.cir_lock_prev = 1 while
// the CIR holds a non-jump instruction (a store, a CSR op).  In the RTL a
// lock is asserted only by jump_caused_by_d = f_jump_now && x_jump_not_except
// (hazard3_decode.v:151-155), i.e. by a taken jump/branch in X, and the CIR
// is frozen for the lock's duration, so the locked instruction is always a
// taken JAL/JALR/branch.  R40.1 states that on the DUT's own decode
// (raw_branchcond, decode.v:337, before the lock forces d_branchcond to
// BCOND_NEVER at :585-587) and the DUT's own compare (x_branch_cmp,
// core.v:913).  BCOND_NEVER=0, ALWAYS=1, ZERO=2, NZERO=3 (hazard3_ops.vh:80-83).
// ===========================================================================
logic h3_cti_lock_implies_taken_jump;
assign h3_cti_lock_implies_taken_jump =
    !cpu.core.decode_u.cir_lock_prev ||
    (cpu.core.decode_u.raw_branchcond == 2'h1) ||
    (cpu.core.decode_u.raw_branchcond == 2'h2 && !cpu.core.x_branch_cmp) ||
    (cpu.core.decode_u.raw_branchcond == 2'h3 &&  cpu.core.x_branch_cmp);
`include "h3_cti_round41.svh"
