// ===========================================================================
// check/peek/h3_cti_round5.svh -- operand invariant, corrected (round 5).
//
// CtiRs2BypassIsPreRegs was REFUTED at BMC depth 5 from reset
// (results/cex/CtiRs2BypassIsPreRegs): `lw x10,0(x0)` then `c.sw x10,0(x8)`.
// hazard3_core.v:467 waives the load-use interlock for stores ONLY:
//     x_stall_on_raw = !(d_memop == MEMOP_SW || MEMOP_SH || MEMOP_SB);
// so X progresses while x_rs2_bypass still holds the load's ADDRESS
// (xm_result); the store's data is resolved a cycle later in M by the
// m_wdata mux (core.v:1429-1435: mw_result if xm_rs2 == mw_rd, else
// xm_result).  The core is correct; the lemma named a wire a store never
// consumes.  For every other consumer of rs2, and for rs1 always, the
// interlock makes the X-stage bypass final at h3_x_progress.
// ===========================================================================
localparam [4:0] H3_MEMOP_SW = 5'h05;   // hazard3_ops.vh
localparam [4:0] H3_MEMOP_SH = 5'h06;
localparam [4:0] H3_MEMOP_SB = 5'h07;

logic h3_cti_x_is_store;
assign h3_cti_x_is_store =
    (cpu.core.d_memop == H3_MEMOP_SW) || (cpu.core.d_memop == H3_MEMOP_SH) ||
    (cpu.core.d_memop == H3_MEMOP_SB);

// --- rs2 as an ALU / branch / address operand: final at X -----------------
logic h3_cti_rs2_bypass_is_pre_regs_v2;
assign h3_cti_rs2_bypass_is_pre_regs_v2 =
    !h3_x_progress || !(|cpu.core.d_rs2) || h3_cti_x_is_store ||
    (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);

// --- the store data the DUT commits in M is its rs2's register value ------
// The M-stage twin of the operand lemma, DUT-only.  By M the preceding
// load's write has landed (core.v:1577 writes the array from M), so
// pre_regs[xm_rs2] is the architectural value, and the m_wdata forward
// (:1429-1435) delivers exactly that.  Lane replication and the spec
// comparison remain the goal's (StoreWData) business, not this lemma's.
logic h3_cti_m_is_store;
assign h3_cti_m_is_store =
    (cpu.core.xm_memop == H3_MEMOP_SW) || (cpu.core.xm_memop == H3_MEMOP_SH) ||
    (cpu.core.xm_memop == H3_MEMOP_SB);

logic h3_cti_store_data_is_regfile;
assign h3_cti_store_data_is_regfile =
    !h3_fol_valid || !h3_cti_m_is_store || !(|cpu.core.xm_rs2) ||
    (cpu.core.m_wdata == pre_regs[cpu.core.xm_rs2]);

// ===========================================================================
// The pipe-register invariant the k=2 induction-CTI for CtiRs1BypassIsPreRegs
// exploited (results/icti/r34_CtiRs1BypassIsPreRegs): a STORE in M carrying
// xm_rd = 16.  hazard3_core.v:1510 gates m_reg_wen only on |xm_rd and no
// exception -- never on memop -- and for a store m_result is
// m_rdata_pick_sext's default 32'hxxxx (core.v:1471-1473), i.e. a FREE value
// in the formal model.  So the free pairing wrote garbage into x16 while X
// read x16.  Unreachable: hazard3_decode.v:412-414 sets raw_rd = X0 for
// SB/SH/SW, and xm_rd/xm_memop are loaded together from d_rd/d_memop
// (core.v:1266-1267).  Two rungs: the X-stage fact is combinational; the
// M-stage one follows from it in one step.
// ===========================================================================
logic h3_cti_x_store_has_no_rd;
assign h3_cti_x_store_has_no_rd = !h3_cti_x_is_store || !(|cpu.core.d_rd);

logic h3_cti_m_store_has_no_rd;
assign h3_cti_m_store_has_no_rd = !h3_cti_m_is_store || !(|cpu.core.xm_rd);
`include "h3_cti_round6.svh"
