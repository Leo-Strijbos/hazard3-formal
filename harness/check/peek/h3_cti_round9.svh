// ===========================================================================
// Round 9.  The x0-read hole underneath the operand rungs.
//
// Round 8's follower-link CTI (results/icti/round8-CtiFollowerPostIsDutMscratchV2)
// is `csrrw x31, mscratch, x0` in X with h3_fol_valid=1, h3_fol_fetch_err=0 and
// no exception: the specification writes 0 (rs1 = x0) but the DUT's mscratch
// took 0x0000000b, so pre_mscratch != h3_fol_spec_post_mscratch and the link
// broke.  The CSR write data for a non-immediate CSR op is x_rs1_bypass
// (core.v:1073), and x_rs1_bypass is the one-hot AND-OR mux of core.v:574-577
// driven by the REGISTER x_rs1_select_regs_xm_mw (core.v:528-540).
//
// Hazard3 zeroes an x0 read by making that select all-zero -- NOT by a mux on
// the register file.  With RESET_REGFILE=0 (hazard3_config.vh:236) the regfile
// is the no-reset variant, whose read port is a plain rdata1 <= mem[raddr1]
// (hazard3_regfile_1w2r.v:68-75) with no x0 case, and mem[0] is never written
// (m_reg_wen is gated on |xm_rd, core.v:1510).  So mem[0] is a free register in
// induction: it supplied the 0x0000000b.
//
// Nothing below the link excluded that.  CtiRs1SelectTracksRd (round 4)
// deliberately WAIVES the case d_rs1 == 0 with d_rs1_predecoded != 0 -- its
// `1'b1` arm -- because LUI/AUIPC/JAL force raw_rs1 = X0 (decode.v:385-388)
// while the raw instruction field still holds bits, so the select is legitimately
// non-zero there.  CtiRs1BypassIsPreRegs (round 4) excludes |d_rs1 == 0 outright.
// Round 4's own comment states "the DUT's x0 read is also 0" -- true of every
// reachable state, but never written down as a lemma, so induction is free to
// deny it.
//
// The fact that closes the hole is the CIR-flag class again: a registered
// description of the CIR must agree with the CIR.  d_rs1_predecoded
// (core.v:505-514) is f_rs1_fine latched alongside the CIR.  For a 32-bit
// instruction predecode_rs1_fine takes its default arm = predecode_rs1_coarse
// (the fine special cases are the compressed C_LI / C_MV, frontend.v:771-781)
// and predecode_rs1_coarse = next_instr[19:15] (frontend.v:737) -- the very
// field the decoder reads as raw_rs1 = d_instr[19:15] (decode.v:348).
// REGADDR_MASK is 5'h1f here (EXTENSION_E = 0, core.v:102), so the mask is
// transparent.  Guarded to 32-bit because a compressed CIR holds the EXPANDED
// instruction while the predecode saw the compressed one; fd_cir_is_32bit is
// tied to fd_cir_raw[1:0] by the proved CtiCirLengthAgreesRaw.  Guarded on
// fd_cir_vld[1] because a starved frontend latches the predecode of a word the
// CIR does not hold (d_starved, h3_commit.svh:60); with both halves present the
// CIR and the predecode describe the same instruction.
//
// Hazard3 is 3-stage (F, D/X fused, M), so fd_cir IS the instruction in X --
// h3_x_instr is fd_cir_raw for exactly this reason.
//
// With this rung, CtiRs1SelectTracksRd takes its FIRST arm for an x0 read
// (~|d_rs1 and ~|d_rs1_predecoded => ~|x_rs1_select_regs_xm_mw), the AND-OR mux
// emits a literal zero, and the CSR write data is 0 as the specification says.
// Both lemmas are DUT-only: no specification signal appears, so a core proof
// transfers unconditionally and neither can make any comparison vacuous.
// ===========================================================================
logic h3_cti_rs1_predecode_agrees_cir32;
assign h3_cti_rs1_predecode_agrees_cir32 =
    !cpu.core.fd_cir_is_32bit || !cpu.core.fd_cir_vld[1] ||
    (cpu.core.d_rs1_predecoded == cpu.core.fd_cir_raw[19:15]);

// The rs2 twin.  predecode_rs2_fine's non-default arms are C_BEQZ / C_BNEZ
// (compressed) and the Zilsd SD / C_SDSP forms; EXTENSION_ZILSD = 0 and
// EXTENSION_ZCLSD = 0 in this build (hazard3_config.vh:75,86), so for a 32-bit
// instruction the default arm predecode_rs2_coarse = next_instr[24:20] is the
// only reachable one, matching raw_rs2 = d_instr[24:20] in the decoder.
logic h3_cti_rs2_predecode_agrees_cir32;
assign h3_cti_rs2_predecode_agrees_cir32 =
    !cpu.core.fd_cir_is_32bit || !cpu.core.fd_cir_vld[1] ||
    (cpu.core.d_rs2_predecoded == cpu.core.fd_cir_raw[24:20]);
`include "h3_cti_round10.svh"
