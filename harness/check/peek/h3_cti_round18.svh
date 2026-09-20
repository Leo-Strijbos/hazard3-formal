// ===========================================================================
// Round 18.  Two rungs the fixed-model CTIs converge on.
//
// (1) results/icti/fix1-LoadAddr: fd_cir_raw = 0xc5438fe1 (a c.and in the
// low halfword) while the DUT decodes a c.lwsp (d_rs1 = x2, d_imm = 0xc4)
// and raises a load on the bus the specification never asked for.  cir is a
// REGISTER ("pre-expanded to 32-bit", hazard3_frontend.v:50) loaded from the
// decompressor's output, cir_raw is a wire over the buffer (:897); nothing
// ties them for a 16-bit instruction (CtiCirRawPassthrough, step 2, covers
// the 32-bit case only).  A reference decompressor, the RTL's own module with
// this build's extension set, states the missing relation.  DUT-only.
//
// (2) results/icti/round17-CtiGhostTracks{Mepc,Pc,Mstatus}V2 and
// fix1-WrapRegA: every remaining goal needs the DUT's WRITEBACK VALUE to be
// the specification's.  The Ibex proof carries this as one lemma per
// instruction class ("Arith: use spec_compliant") beneath RegMatch.  Stated
// here in follower form, as an invariant over the whole M residency:
//   xm_result is loaded from x_alu_result at the same edge the follower
//   latches spec_post_wX (core.v:1359, h3_follower.svh:320-330), and neither
//   moves until M retires -- so "xm_result == h3_fol_spec_wX while the class
//   instruction sits in M" is 1-inductive given the operand rungs (step 13),
//   the 32-bit CIR passthrough (step 2) and the specification reading
//   pre_regs_cut.  32-bit encodings only; the compressed forms come after (1).
// ===========================================================================

// --- R18.1  cir is the decompression of cir_raw for a 16-bit CIR ------------
logic        h3_decomp_ref_is_32bit;
logic [31:0] h3_decomp_ref_out;
logic        h3_decomp_ref_invalid;
hazard3_instr_decompress #(
    .EXTENSION_C     (1),
    .EXTENSION_E     (0),
    .EXTENSION_M     (1),
    .EXTENSION_ZBB   (0),
    .EXTENSION_ZCB   (0),
    .EXTENSION_ZCLSD (0),
    .EXTENSION_ZCMP  (0),
    .EXTENSION_ZILSD (0)
) h3_decomp_ref (
    .clk                        (clk_i),
    .rst_n                      (rst_ni),
    .instr_in                   (cpu.core.fd_cir_raw),
    .instr_is_32bit             (h3_decomp_ref_is_32bit),
    .instr_out                  (h3_decomp_ref_out),
    .instr_out_is_uop           (),
    .instr_out_is_final_uop     (),
    .instr_out_uop_no_pc_update (),
    .instr_out_uop_atomic       (),
    .instr_out_uop_stall        (1'b0),
    .instr_out_uop_clear        (1'b0),
    .df_uop_step                (),
    .invalid                    (h3_decomp_ref_invalid)
);
logic h3_cti_cir_is_decompressed_raw;
assign h3_cti_cir_is_decompressed_raw =
    (cpu.core.fd_cir_raw[1:0] == 2'b11) || !(|cpu.core.fd_cir_vld) ||
    (cpu.core.fd_cir == h3_decomp_ref_out);

// --- R18.2-R18.5  writeback value, per 32-bit class, over the M residency ---
logic h3_fol_is32;
assign h3_fol_is32 = h3_fol_instr[1:0] == 2'b11;
logic h3_fol_is_addi, h3_fol_is_add, h3_fol_is_xor, h3_fol_is_lui;
assign h3_fol_is_addi = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h13) && (h3_fol_instr[14:12] == 3'b000);
assign h3_fol_is_add  = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b000) && (h3_fol_instr[31:25] == 7'h00);
assign h3_fol_is_xor  = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h33) && (h3_fol_instr[14:12] == 3'b100) && (h3_fol_instr[31:25] == 7'h00);
assign h3_fol_is_lui  = h3_fol_is32 && (h3_fol_instr[6:0] == 7'h37);
// The shared consequent: nothing to say unless the follower holds a clean,
// specifiable instruction whose answer was a register write.
logic h3_fol_wb_is_spec;
assign h3_fol_wb_is_spec =
    !h3_fol_valid || h3_fol_except || h3_fol_fetch_err || h3_fol_spec_int_err ||
    !h3_fol_spec_wX_en || (cpu.core.xm_result == h3_fol_spec_wX);
logic h3_cti_wb_addi, h3_cti_wb_add, h3_cti_wb_xor, h3_cti_wb_lui;
assign h3_cti_wb_addi = !h3_fol_is_addi || h3_fol_wb_is_spec;
assign h3_cti_wb_add  = !h3_fol_is_add  || h3_fol_wb_is_spec;
assign h3_cti_wb_xor  = !h3_fol_is_xor  || h3_fol_wb_is_spec;
assign h3_cti_wb_lui  = !h3_fol_is_lui  || h3_fol_wb_is_spec;
`include "h3_cti_round19.svh"
