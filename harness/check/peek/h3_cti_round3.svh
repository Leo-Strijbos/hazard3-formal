// ===========================================================================
// check/peek/h3_cti_round3.svh -- CTI-derived lemmas, batch round 3a.
//
// Written from the counterexample to CtiGhostTracksMscratch on the post-strip
// model (results/cti/7_CtiGhostTracksMscratch): h3_has_ghost=1 with
// h3_abs_past_valid=0.  Every frame condition in the harness is guarded by
// `!h3_abs_past_valid || ...`, so in that state they are all vacuous and the
// ghost is unconstrained.  The state is unreachable: h3_has_ghost is clocked,
// cleared under !rst_ni and set only in the else-branch (h3_follower.svh:423-
// 428), so has_ghost(N+1)=1 forces rst_ni(N)=1, which IS h3_abs_past_valid(N+1)
// (h3_abs.svh:456, `<= rst_ni`).  Provable in one step.
// ===========================================================================

// --- L3.1  a ghost cannot exist before the past is valid -------------------
logic h3_cti_has_ghost_implies_past_valid;
assign h3_cti_has_ghost_implies_past_valid = !h3_has_ghost || h3_abs_past_valid;

// --- L3.2  neither can a follower record -----------------------------------
// h3_fol_valid: cleared at h3_follower.svh:291 under reset, set at :320 only on
// h3_x_progress.  Same one-step argument.
logic h3_cti_fol_valid_implies_past_valid;
assign h3_cti_fol_valid_implies_past_valid = !h3_fol_valid || h3_abs_past_valid;

// --- L3.3  the specification never reads AND writes in one instruction -----
// From the CtiFollowerMemHasXmMemop counterexample: the follower held both
// h3_fol_spec_mem_read and h3_fol_spec_mem_write for h3_fol_instr = 0.  No
// RV32IMC instruction does both; AMOs would, but EXTENSION_A = 0 and the Sail
// model is built without them.  Spec-side only; no DUT term.
logic h3_cti_spec_mem_not_both;
assign h3_cti_spec_mem_not_both = !h3_spec_en || !(spec_mem_read && spec_mem_write);

// --- L3.4  ...so the follower's record never claims both -------------------
// Registered image of L3.3: both fields latch from spec_mem_read/write on the
// same h3_x_progress edge (h3_follower.svh:316-349).  DEPENDS ON L3.3.
logic h3_cti_fol_mem_not_both;
assign h3_cti_fol_mem_not_both =
    !h3_fol_valid || !(h3_fol_spec_mem_read && h3_fol_spec_mem_write);

// --- L3.5  a CSR write in X comes from a 32-bit instruction ---------------
// From the WrapMscratch counterexample on the honest model: h3_x_instr (raw,
// fd_cir_raw) = 0x4102 = c.lwsp, while h3_x_writes_mscratch (decoded from the
// EXPANDED fd_cir) = 1.  CtiCirRawPassthrough covers only the 32-bit case, so
// for compressed words fd_cir was unconstrained relative to fd_cir_raw.
// The decompressor (hazard3_instr_decompress.v) produces a SYSTEM opcode for
// exactly one compressed encoding, C.EBREAK -> EBREAK (:241-242), whose funct3
// is 000 and so is never a CSR write.  Every CSR write therefore comes from a
// 32-bit word.  Stated over the DUT's own write enable and the raw length
// bits: it says nothing about WHAT any expansion is, so it cannot hide a
// decompressor bug (cf. FINDING_C_ADDI4SPN.md); it only says CSR ops are not
// compressed.  With CtiCirRawPassthrough (proved) this makes the decoded CSR
// write and h3_x_instr describe the same instruction.
logic h3_cti_csr_wen_is_uncompressed;
assign h3_cti_csr_wen_is_uncompressed =
    !h3_x_csr_wen || (cpu.core.fd_cir_raw[1:0] == 2'b11);
`include "h3_cti_round3b.svh"
