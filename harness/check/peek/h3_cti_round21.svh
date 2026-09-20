// ===========================================================================
// Round 21.  Writeback-value class lemmas, batch 3: the remaining 32-bit
// I-type ALU classes and the jumps.  JAL/JALR write the link address through
// the same ALU path (hazard3_decode.v:383-386: ALUSRCA_PC + imm 4, or 2 for
// a compressed form), so xm_result is the link and the round-18 shape holds
// unchanged.  A jump whose target traps is excused by h3_fol_except on the
// DUT side and by !h3_fol_spec_wX_en on the specification side.
// Also re-submitted: CtiSpecPostMstatusHardwiredZero, which round 17 placed
// at the same step as the DUT rung it needs (CtiMstatusHardwiredZero, step
// 28); an insert lands above every existing lemma, so it now sees it.
// ===========================================================================
logic h3_fol_is_slti;
assign h3_fol_is_slti = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b010);
logic h3_cti_wb_slti;
assign h3_cti_wb_slti = !h3_fol_is_slti || h3_fol_wb_is_spec;

logic h3_fol_is_sltiu;
assign h3_fol_is_sltiu = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b011);
logic h3_cti_wb_sltiu;
assign h3_cti_wb_sltiu = !h3_fol_is_sltiu || h3_fol_wb_is_spec;

logic h3_fol_is_xori;
assign h3_fol_is_xori = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b100);
logic h3_cti_wb_xori;
assign h3_cti_wb_xori = !h3_fol_is_xori || h3_fol_wb_is_spec;

logic h3_fol_is_ori;
assign h3_fol_is_ori = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b110);
logic h3_cti_wb_ori;
assign h3_cti_wb_ori = !h3_fol_is_ori || h3_fol_wb_is_spec;

logic h3_fol_is_andi;
assign h3_fol_is_andi = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b111);
logic h3_cti_wb_andi;
assign h3_cti_wb_andi = !h3_fol_is_andi || h3_fol_wb_is_spec;

logic h3_fol_is_jal;
assign h3_fol_is_jal = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h6f);
logic h3_cti_wb_jal;
assign h3_cti_wb_jal = !h3_fol_is_jal || h3_fol_wb_is_spec;

logic h3_fol_is_jalr;
assign h3_fol_is_jalr = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h67) && (h3_fol_instr[14:12] == 3'b000);
logic h3_cti_wb_jalr;
assign h3_cti_wb_jalr = !h3_fol_is_jalr || h3_fol_wb_is_spec;
`include "h3_cti_round23.svh"
