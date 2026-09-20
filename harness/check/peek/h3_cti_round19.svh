// ===========================================================================
// Round 19.  Round 18's CtiCirIsDecompressedRaw was REFUTED ON CORE at depth
// 4 (results/cex/round18-CtiCirIsDecompressedRaw/): cir_raw = 0x1202, a
// c.slli x4 with shamt[5] = 1 (reserved on RV32), decompresses to 0 with
// invalid = 1 -- and the DUT's cir read 0x00000003, not 0.  The frontend
// loads
//     cir <= decomp_instr_out | 32'd3;          (hazard3_frontend.v:882)
// i.e. it stamps the 32-bit marker onto the expanded word, and
//     cir_invalid_16bit <= decomp_invalid;      (:884)
// on the same clock enable.  The reference decompressor (round 18,
// h3_decomp_ref) is fed cir_raw, whose low halfword is what next_instr held
// at that edge, so both registers are the reference's outputs plus the OR.
// Both DUT-only.
// ===========================================================================
logic h3_cti_cir_is_decompressed_raw_v2;
assign h3_cti_cir_is_decompressed_raw_v2 =
    (cpu.core.fd_cir_raw[1:0] == 2'b11) || !(|cpu.core.fd_cir_vld) ||
    (cpu.core.fd_cir == (h3_decomp_ref_out | 32'd3));
logic h3_cti_cir_invalid_is_decompressed_raw;
assign h3_cti_cir_invalid_is_decompressed_raw =
    (cpu.core.fd_cir_raw[1:0] == 2'b11) || !(|cpu.core.fd_cir_vld) ||
    (cpu.core.fd_cir_invalid_16bit == h3_decomp_ref_invalid);
`include "h3_cti_round20.svh"
