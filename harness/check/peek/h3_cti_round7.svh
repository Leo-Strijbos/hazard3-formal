// ===========================================================================
// check/peek/h3_cti_round7.svh -- round 7: the frontend's registered CIR
// flags agree with the CIR word.
//
// results/icti/round6-CtiFollowerPostIsDutMscratchV2 (k=1): a legal
// `csrrw x10, mscratch, x1` (0x34009573) at a progressing query with
// h3_x_csr_wen = 0, then an (illegal-instruction) exception, while Sail
// executed it.  RVOPC_CSRRW sets raw_csr_wen unconditionally
// (hazard3_decode.v:506), so d_csr_wen = 0 came from the gate at :558:
// d_invalid || d_starved || d_except_instr_bus_fault || partial_predicted_branch,
// and d_invalid = fd_cir_invalid_16bit || d_invalid_32bit (:92).  The first
// term is the frontend REGISTER cir_invalid_16bit <= decomp_invalid
// (hazard3_frontend.v:886), free in an induction state; decomp_invalid is 0
// for every 32-bit word (hazard3_instr_decompress.v:186-200) and set only for
// specific RESERVED compressed encodings (:226-270).  Same class as cir vs
// cir_raw (CtiCirRawPassthrough) and cir_is_32bit (CtiCirLengthAgreesRaw):
// a registered description of the CIR must agree with the CIR.
// ===========================================================================
logic h3_cti_cir_invalid_agrees_raw;      // a 32-bit CIR is never "invalid 16-bit"
assign h3_cti_cir_invalid_agrees_raw =
    (cpu.core.fd_cir_raw[1:0] != 2'b11) || !cpu.core.fd_cir_invalid_16bit;

// With EXTENSION_ZCMP = 0 every cir_uop_* flag is gated to zero at each load
// (hazard3_frontend.v:887-890: `|EXTENSION_ZCMP && ...`).  The decoder's
// image for this family is {0}; stated before a CTI has to find it.
logic h3_cti_cir_uop_flags_zero;
assign h3_cti_cir_uop_flags_zero =
    !cpu.core.fd_cir_is_uop && !cpu.core.fd_cir_uop_nonfinal &&
    !cpu.core.fd_cir_uop_no_pc_update && !cpu.core.fd_cir_uop_atomic;

// --- the store's rs2 operand at X, with the hazard excused PRECISELY ---------
// results/icti/round6-CtiStoreDataIsRegfile (k=1): `sb x31,0(x6)` at X with
// NO hazard on x31 (M is writing x30), yet m_wdata != pre_regs[31] a cycle
// later.  CtiRs2BypassIsPreRegsV2 excludes stores wholesale, so for a store
// nothing tied x_rs2_bypass to the register file; xm_result inherited a free
// x_rdata2 and the M-stage forward (core.v:1429-1435) only repairs the
// load-use case.  The exact exclusion is the LOAD-USE HAZARD on rs2 -- a
// load in M whose rd is d_rs2 (the case core.v:467 waives the interlock for)
// -- not "is a store".  Everything else a store reads is final at X.
logic h3_cti_rs2_load_use_hazard;
assign h3_cti_rs2_load_use_hazard =
    (cpu.core.xm_memop <= 5'h04) && (|cpu.core.xm_rd) && (cpu.core.xm_rd == cpu.core.d_rs2);

logic h3_cti_rs2_store_bypass_is_pre_regs;
assign h3_cti_rs2_store_bypass_is_pre_regs =
    !h3_x_progress || !h3_cti_x_is_store || !(|cpu.core.d_rs2) ||
    h3_cti_rs2_load_use_hazard ||
    (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);
`include "h3_cti_round8.svh"
