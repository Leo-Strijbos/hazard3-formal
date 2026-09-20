// ===========================================================================
// Round 20.  The writeback-value class lemmas, batch 2.  Round 18 proved the
// pattern (CtiWbLui 151 s, CtiWbAddi 223 s, CtiWbXor 259 s): while a 32-bit
// instruction of the class sits in M with a clean, specifiable follower
// record, xm_result equals the Sail answer latched beside it.  Same shape,
// twelve more 32-bit ALU classes (funct7 7'h20 selects SUB / SRA / SRAI;
// 7'h00 excludes the M-extension row, which shares opcode 7'h33).
// ===========================================================================
logic h3_fol_is_auipc;
assign h3_fol_is_auipc = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h17);
logic h3_cti_wb_auipc;
assign h3_cti_wb_auipc = !h3_fol_is_auipc || h3_fol_wb_is_spec;

logic h3_fol_is_sub;
assign h3_fol_is_sub = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b000) && (h3_fol_instr[31:25] == 7'h20);
logic h3_cti_wb_sub;
assign h3_cti_wb_sub = !h3_fol_is_sub || h3_fol_wb_is_spec;

logic h3_fol_is_sll;
assign h3_fol_is_sll = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b001) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_sll;
assign h3_cti_wb_sll = !h3_fol_is_sll || h3_fol_wb_is_spec;

logic h3_fol_is_slt;
assign h3_fol_is_slt = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b010) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_slt;
assign h3_cti_wb_slt = !h3_fol_is_slt || h3_fol_wb_is_spec;

logic h3_fol_is_sltu;
assign h3_fol_is_sltu = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b011) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_sltu;
assign h3_cti_wb_sltu = !h3_fol_is_sltu || h3_fol_wb_is_spec;

logic h3_fol_is_srl;
assign h3_fol_is_srl = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b101) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_srl;
assign h3_cti_wb_srl = !h3_fol_is_srl || h3_fol_wb_is_spec;

logic h3_fol_is_sra;
assign h3_fol_is_sra = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b101) && (h3_fol_instr[31:25] == 7'h20);
logic h3_cti_wb_sra;
assign h3_cti_wb_sra = !h3_fol_is_sra || h3_fol_wb_is_spec;

logic h3_fol_is_or;
assign h3_fol_is_or = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b110) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_or;
assign h3_cti_wb_or = !h3_fol_is_or || h3_fol_wb_is_spec;

logic h3_fol_is_and;
assign h3_fol_is_and = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b111) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_and;
assign h3_cti_wb_and = !h3_fol_is_and || h3_fol_wb_is_spec;

logic h3_fol_is_slli;
assign h3_fol_is_slli = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b001) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_slli;
assign h3_cti_wb_slli = !h3_fol_is_slli || h3_fol_wb_is_spec;

logic h3_fol_is_srli;
assign h3_fol_is_srli = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b101) && (h3_fol_instr[31:25] == 7'h00);
logic h3_cti_wb_srli;
assign h3_cti_wb_srli = !h3_fol_is_srli || h3_fol_wb_is_spec;

logic h3_fol_is_srai;
assign h3_fol_is_srai = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b101) && (h3_fol_instr[31:25] == 7'h20);
logic h3_cti_wb_srai;
assign h3_cti_wb_srai = !h3_fol_is_srai || h3_fol_wb_is_spec;
`include "h3_cti_round21.svh"
