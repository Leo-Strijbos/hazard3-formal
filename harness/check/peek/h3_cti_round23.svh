// ===========================================================================
// Round 23.  Writeback-value class lemmas, batch 4: the COMPRESSED forms.
// h3_fol_instr holds the raw halfword for a 16-bit instruction (h3_x_instr
// is fd_cir_raw, upper half masked); the DUT executed the expanded word,
// which round 19 tied to the decompression of that halfword
// (CtiCirIsDecompressedRawV2, step 31), and the specification decompresses
// the same halfword itself.  Same consequent as round 18.  Class predicates
// follow the RV32C quadrant/funct3 map; reserved code points (C.ADDI4SPN
// nzuimm == 0, C.LUI nzimm == 0, C.SLLI shamt[5]) trap on both sides and are
// excused by h3_fol_except / !h3_fol_spec_wX_en.  C.J / C.JR / branches /
// loads / stores write no register and are not in this batch.
// Also re-submitted: CtiWbSub, which timed out at 400 s in round 20 at kind
// depth 1 (CtiWbAdd took 334 s) -- this round runs with KIND_CAP=900.
// ===========================================================================
logic        h3_fol_is16;
assign h3_fol_is16 = h3_fol_instr[1:0] != 2'b11;
logic [15:0] h3_fol_c;
assign h3_fol_c = h3_fol_instr[15:0];
logic h3_fol_is_c_addi;
assign h3_fol_is_c_addi = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b000);
logic h3_cti_wb_c_addi;
assign h3_cti_wb_c_addi = !h3_fol_is_c_addi || h3_fol_wb_is_spec;

logic h3_fol_is_c_jal;
assign h3_fol_is_c_jal = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b001);
logic h3_cti_wb_c_jal;
assign h3_cti_wb_c_jal = !h3_fol_is_c_jal || h3_fol_wb_is_spec;

logic h3_fol_is_c_li;
assign h3_fol_is_c_li = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b010);
logic h3_cti_wb_c_li;
assign h3_cti_wb_c_li = !h3_fol_is_c_li || h3_fol_wb_is_spec;

logic h3_fol_is_c_lui16sp;
assign h3_fol_is_c_lui16sp = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b011);
logic h3_cti_wb_c_lui16sp;
assign h3_cti_wb_c_lui16sp = !h3_fol_is_c_lui16sp || h3_fol_wb_is_spec;

logic h3_fol_is_c_srli;
assign h3_fol_is_c_srli = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b00);
logic h3_cti_wb_c_srli;
assign h3_cti_wb_c_srli = !h3_fol_is_c_srli || h3_fol_wb_is_spec;

logic h3_fol_is_c_srai;
assign h3_fol_is_c_srai = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b01);
logic h3_cti_wb_c_srai;
assign h3_cti_wb_c_srai = !h3_fol_is_c_srai || h3_fol_wb_is_spec;

logic h3_fol_is_c_andi;
assign h3_fol_is_c_andi = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b10);
logic h3_cti_wb_c_andi;
assign h3_cti_wb_c_andi = !h3_fol_is_c_andi || h3_fol_wb_is_spec;

logic h3_fol_is_c_sub;
assign h3_fol_is_c_sub = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b11) && !h3_fol_c[12] && (h3_fol_c[6:5] == 2'b00);
logic h3_cti_wb_c_sub;
assign h3_cti_wb_c_sub = !h3_fol_is_c_sub || h3_fol_wb_is_spec;

logic h3_fol_is_c_xor;
assign h3_fol_is_c_xor = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b11) && !h3_fol_c[12] && (h3_fol_c[6:5] == 2'b01);
logic h3_cti_wb_c_xor;
assign h3_cti_wb_c_xor = !h3_fol_is_c_xor || h3_fol_wb_is_spec;

logic h3_fol_is_c_or;
assign h3_fol_is_c_or = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b11) && !h3_fol_c[12] && (h3_fol_c[6:5] == 2'b10);
logic h3_cti_wb_c_or;
assign h3_cti_wb_c_or = !h3_fol_is_c_or || h3_fol_wb_is_spec;

logic h3_fol_is_c_and;
assign h3_fol_is_c_and = h3_fol_is16 && (h3_fol_c[1:0] == 2'b01) && (h3_fol_c[15:13] == 3'b100) && (h3_fol_c[11:10] == 2'b11) && !h3_fol_c[12] && (h3_fol_c[6:5] == 2'b11);
logic h3_cti_wb_c_and;
assign h3_cti_wb_c_and = !h3_fol_is_c_and || h3_fol_wb_is_spec;

logic h3_fol_is_c_addi4spn;
assign h3_fol_is_c_addi4spn = h3_fol_is16 && (h3_fol_c[1:0] == 2'b00) && (h3_fol_c[15:13] == 3'b000);
logic h3_cti_wb_c_addi4spn;
assign h3_cti_wb_c_addi4spn = !h3_fol_is_c_addi4spn || h3_fol_wb_is_spec;

logic h3_fol_is_c_slli;
assign h3_fol_is_c_slli = h3_fol_is16 && (h3_fol_c[1:0] == 2'b10) && (h3_fol_c[15:13] == 3'b000);
logic h3_cti_wb_c_slli;
assign h3_cti_wb_c_slli = !h3_fol_is_c_slli || h3_fol_wb_is_spec;

logic h3_fol_is_c_mv;
assign h3_fol_is_c_mv = h3_fol_is16 && (h3_fol_c[1:0] == 2'b10) && (h3_fol_c[15:13] == 3'b100) && !h3_fol_c[12] && (|h3_fol_c[6:2]);
logic h3_cti_wb_c_mv;
assign h3_cti_wb_c_mv = !h3_fol_is_c_mv || h3_fol_wb_is_spec;

logic h3_fol_is_c_add;
assign h3_fol_is_c_add = h3_fol_is16 && (h3_fol_c[1:0] == 2'b10) && (h3_fol_c[15:13] == 3'b100) &&  h3_fol_c[12] && (|h3_fol_c[6:2]);
logic h3_cti_wb_c_add;
assign h3_cti_wb_c_add = !h3_fol_is_c_add || h3_fol_wb_is_spec;

logic h3_fol_is_c_jalr;
assign h3_fol_is_c_jalr = h3_fol_is16 && (h3_fol_c[1:0] == 2'b10) && (h3_fol_c[15:13] == 3'b100) &&  h3_fol_c[12] && !(|h3_fol_c[6:2]) && (|h3_fol_c[11:7]);
logic h3_cti_wb_c_jalr;
assign h3_cti_wb_c_jalr = !h3_fol_is_c_jalr || h3_fol_wb_is_spec;
`include "h3_cti_round24.svh"
