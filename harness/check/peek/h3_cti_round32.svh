// ===========================================================================
// Round 32.  RegMatchV2 (rounds 28/30) CTI: a clean, specifiable write in M
// (h3_fol_clean_write, h3_fol_spec_wX_en, rd = 1) whose instruction word is
// 0xffffffff -- no writeback-class lemma applies, so nothing ties xm_result
// (0xffffffff) to h3_fol_spec_wX (0xbfffffff) and the register diverges one
// cycle later.  Two rungs close the gap generically:
//   R32.1 CtiFolWriteCoverage: the spec answers with a register write only
//         for an instruction in one of the writer classes (23 RV32I writers,
//         loads incl. C.LW/C.LWSP, CSR ops, MUL/DIV, 16 compressed writers).
//         A spec-side fact (Sail calls wX only in those clauses).
//   R32.2 CtiWbAll (one layer above): for every clean, specifiable write
//         that is not a load and not MUL/DIV, xm_result == h3_fol_spec_wX.
//         Propositional over R32.1 + the 39 class lemmas + CtiWbCsrV2.
// MUL/DIV (h3_fol_is_muldiv) is excluded from R32.2 on purpose: the DUT's
// iterative multiplier has no writeback lemma (user decision pending).
// ===========================================================================
logic h3_fol_is_muldiv;
assign h3_fol_is_muldiv = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[31:25] == 7'h01);
logic h3_fol_is_writer;
assign h3_fol_is_writer =
    h3_fol_is_add  | h3_fol_is_addi | h3_fol_is_and  | h3_fol_is_andi | h3_fol_is_auipc |
    h3_fol_is_csr  | h3_fol_is_jal  | h3_fol_is_jalr | h3_fol_is_load | h3_fol_is_lui   |
    h3_fol_is_or   | h3_fol_is_ori  | h3_fol_is_sll  | h3_fol_is_slli | h3_fol_is_slt   |
    h3_fol_is_slti | h3_fol_is_sltiu| h3_fol_is_sltu | h3_fol_is_sra  | h3_fol_is_srai  |
    h3_fol_is_srl  | h3_fol_is_srli | h3_fol_is_sub  | h3_fol_is_xor  | h3_fol_is_xori  |
    h3_fol_is_muldiv |
    h3_fol_is_c_add  | h3_fol_is_c_addi | h3_fol_is_c_addi4spn | h3_fol_is_c_and  | h3_fol_is_c_andi |
    h3_fol_is_c_jal  | h3_fol_is_c_jalr | h3_fol_is_c_li       | h3_fol_is_c_lui16sp | h3_fol_is_c_mv |
    h3_fol_is_c_or   | h3_fol_is_c_slli | h3_fol_is_c_srai     | h3_fol_is_c_srli | h3_fol_is_c_sub  |
    h3_fol_is_c_xor;
logic h3_cti_fol_write_coverage;
assign h3_cti_fol_write_coverage =
    !h3_fol_clean_write || !h3_fol_spec_wX_en || h3_fol_is_writer;
logic h3_cti_wb_all;
assign h3_cti_wb_all =
    !h3_fol_clean_write || !h3_fol_specifiable || !h3_fol_spec_wX_en || !(|h3_fol_spec_wX_addr) ||
    h3_fol_is_load || h3_fol_is_muldiv || (cpu.core.xm_result == h3_fol_spec_wX);
// R32.3 CtiWbMulDiv -- the M-type writeback lemma, ASSUMED, never attempted (user decision
// 2026-09-19, "the Oxford way": the Ibex proof lists MType under spec_compliant_no_err with the
// comment "Never actually proved, just assumed to be true instead").  Same shape as the 39 class
// lemmas: x_muldiv_result lands in xm_result at X->M (hazard3_core.v:807-861), so over the M
// residency the DUT's product/quotient must equal the spec's answer.  Everything above it is proven
// modulo this one sentence; chain_check3.py reports it as an AXIOM.  Discharging it is a separate
// lineage (iterative shift-add multiplier / restoring divider vs Sail's combinational arithmetic).
logic h3_cti_wb_muldiv;
assign h3_cti_wb_muldiv =
    !h3_fol_clean_write || !h3_fol_is_muldiv || !h3_fol_spec_wX_en || (cpu.core.xm_result == h3_fol_spec_wX);
// R32.4 CtiFolLoadSpecReads.  Round 31 CTI for CtiWbLoad (results/icti/round31-CtiWbLoad/report.txt):
// an LBU in M with a clean write and the spec answer 0xff, but h3_fol_spec_mem_read == 0, so the
// gate-5 bus assumption (h3_goals.svh:292, guarded by h3_fol_spec_mem_read) never binds and the bus
// returns 0x7fffffff instead of the word the spec read.  The spec reads memory for every load that
// does not trap: a latched-at-the-same-edge fact, one layer below CtiWbLoad.
logic h3_cti_fol_load_spec_reads;
assign h3_cti_fol_load_spec_reads =
    !h3_fol_clean_write || !h3_fol_is_load || h3_fol_spec_mem_read;
`include "h3_cti_round33.svh"
