// ===========================================================================
// Round 41.  CtiLockImpliesTakenJump's core CTI (round 40): cir_lock_prev = 1
// with d_starved = 1, so the (invalid) CIR is refilled by the next fetch word
// and the locked "instruction" changes under the lock.  In the RTL a lock is
// asserted only by a jump that issued from a VALID CIR (x_jump_req needs the
// instruction), the CIR is held while locked, and the RAW-stall that would
// block a jump (x_stall_on_raw, hazard3_core.v:455-467) cannot appear while
// the same M instruction is stalled.  Three DUT-only ties, layered so the
// taken-jump statement sits on top of the class statement.
// ===========================================================================
logic h3_cti_lock_cir_valid, h3_cti_lock_no_raw_hazard, h3_cti_lock_implies_jump_or_branch;
assign h3_cti_lock_cir_valid            = !cpu.core.decode_u.cir_lock_prev || !cpu.core.d_starved;
assign h3_cti_lock_no_raw_hazard        = !cpu.core.decode_u.cir_lock_prev || !cpu.core.x_stall_on_raw;
assign h3_cti_lock_implies_jump_or_branch =
    !cpu.core.decode_u.cir_lock_prev || (cpu.core.decode_u.raw_branchcond != 2'h0);
`include "h3_cti_round44.svh"
