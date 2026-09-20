// ===========================================================================
// check/peek/h3_cti_round4.svh -- the operand invariant (round 4).
//
// From the first real INDUCTION counterexample (results/icti/7_CtiFollower-
// PostIsDutMscratch, k=1): at a query both sides process
// `csrrs x31, mscratch, x12` (0x34062ff3); Sail, handed pre_regs, answers 8
// (it saw x12 = 8); the DUT writes 4 (it used x12 = 4).  Same instruction,
// different operand.  pre_regs (h3_abs.svh:224) reads the register-file array
// with the M-stage write forwarded, and the RTL writes the array from M
// (hazard3_core.v:1577 .waddr(xm_rd)), so the harness is CORRECT; but
// x_rs1_bypass (core.v:574-577) muxes x_rdata1 / xm_result / mw_result, and in
// a free induction state those are latches independent of the array.  The
// state is unreachable: in any real trace x_rdata1 is the array read one
// cycle earlier, and xm/mw_result are the values written to the array.
//
// This is the invariant EVERY goal converges on: the CSR goals need it for
// the value written (this CTI); StoreAddr/LoadAddr need it for the address
// (BRINGUP.md:2477-2490 called it "the root lemma of the memory goals").
// Stated over the DUT's decoded register numbers and its own bypass output;
// no specification signal appears, so it cannot make any comparison vacuous.
// A read of x0 is excluded (pre_regs[0] is the constant 0; the DUT's x0 read
// is also 0, but d_rs1 is forced to 0 for instructions with no operand, so the
// guard keeps the lemma about real operands).
// ===========================================================================
logic h3_cti_rs1_bypass_is_pre_regs;
assign h3_cti_rs1_bypass_is_pre_regs =
    !h3_x_progress || !(|cpu.core.d_rs1) ||
    (cpu.core.x_rs1_bypass == pre_regs[cpu.core.d_rs1]);

logic h3_cti_rs2_bypass_is_pre_regs;
assign h3_cti_rs2_bypass_is_pre_regs =
    !h3_x_progress || !(|cpu.core.d_rs2) ||
    (cpu.core.x_rs2_bypass == pre_regs[cpu.core.d_rs2]);

// ===========================================================================
// Support for the operand invariant.  The bypass SELECT is a register
// (core.v:528-540, computed one cycle ahead from *_nxt), so in a free
// induction state it is independent of the addresses it is supposed to track.
// Hazard3 states the consistency itself, under `ifdef HAZARD3_ASSERTIONS
// (core.v:559-567), which this flow does not compile (h3_core_common.svh:426).
// Transcribed verbatim, one wire per source; DUT-only.
// ===========================================================================
logic h3_cti_rs1_select_tracks_rd;
assign h3_cti_rs1_select_tracks_rd =
    !(|cpu.core.d_rs1) ? (!(|cpu.core.d_rs1_predecoded) ? ~|cpu.core.x_rs1_select_regs_xm_mw : 1'b1) :
    (cpu.core.d_rs1 == cpu.core.xm_rd) ? cpu.core.x_rs1_select_regs_xm_mw[1] :
    (cpu.core.d_rs1 == cpu.core.mw_rd) ? cpu.core.x_rs1_select_regs_xm_mw[0] :
                                         cpu.core.x_rs1_select_regs_xm_mw[2];

logic h3_cti_rs2_select_tracks_rd;
assign h3_cti_rs2_select_tracks_rd =
    !(|cpu.core.d_rs2) ? (!(|cpu.core.d_rs2_predecoded) ? ~|cpu.core.x_rs2_select_regs_xm_mw : 1'b1) :
    (cpu.core.d_rs2 == cpu.core.xm_rd) ? cpu.core.x_rs2_select_regs_xm_mw[1] :
    (cpu.core.d_rs2 == cpu.core.mw_rd) ? cpu.core.x_rs2_select_regs_xm_mw[0] :
                                         cpu.core.x_rs2_select_regs_xm_mw[2];

// The writeback-stage bypass value is what the register file now holds.
// mw_result <= m_result and mem[xm_rd] <= m_result land on the SAME edge
// (core.v:1536-1541, regfile .waddr(xm_rd) at :1577), and mw_rd <= xm_rd
// with them (:1560).  Nothing else writes mw_*.  A later write to a different
// register moves mw_rd with it, so the pair always names a landed write.
// x0 is excluded: mw_rd is masked but the array's entry 0 is never written.
logic h3_cti_mw_result_is_regfile;
assign h3_cti_mw_result_is_regfile =
    !(|cpu.core.mw_rd) ||
    (cpu.core.mw_result == cpu.core.regs.real_dualport_noreset.mem[cpu.core.mw_rd]);
`include "h3_cti_round5.svh"
