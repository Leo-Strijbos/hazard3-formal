// ===========================================================================
// check/peek/h3_cti_round3b.svh -- CTI-derived lemmas, batch round 3b.
//
// The memory-path goals (MemWe, NoMem, StoreBe, StoreEn, WrapRegB) fail on the
// same raw-vs-expanded hole as the CSR goals, reached through d_memop instead
// of d_csr_wen: results/cti/6_MemWe has raw = 0x9402 (c.add) and 6_NoMem has
// raw = 0x6002 (c.flwsp -- RESERVED in RV32IMC), yet the DUT is on the bus
// while the specification says no memory operation.  With EXTENSION_C=1,
// `cir` is a register (hazard3_frontend.v:876-884) and cir_raw is combinational
// from the buffer, so a free start state can pair any expansion with any raw
// word.  Nothing here assumes the decompressor is CORRECT (cf.
// FINDING_C_ADDI4SPN.md); these say only which raw words a decoded field may
// come from.
// ===========================================================================

// --- L3b.1  the DUT's own length flag agrees with the raw word's length bits
// fd_cir_is_32bit (hazard3_core.v:132) is loaded alongside cir from the same
// decompressor output on the same cir_clken edge (hazard3_frontend.v:876-884),
// and the decoder already trusts it for the PC increment (hazard3_decode.v:384,
// :386).  The raw length bits are fd_cir_raw[1:0] == 2'b11.  This is the
// alignment anchor: it ties the registered expansion to the live raw word by
// length only, which every correct decompressor satisfies by definition.
logic h3_cti_cir_length_agrees_raw;
assign h3_cti_cir_length_agrees_raw =
    !h3_x_progress ||
    (cpu.core.fd_cir_is_32bit == (cpu.core.fd_cir_raw[1:0] == 2'b11));

// --- L3b.2  a decoded memory operation comes from a load/store word ---------
// The only RV32IMC encodings that touch data memory: LOAD (0000011), STORE
// (0100011), c.lw (00/010), c.sw (00/110), c.lwsp (10/010), c.swsp (10/110).
// No F/D, no Zcb, no A in this configuration.  Weak direction only: it does
// not say a load word yields a load, only that a non-memory word yields no
// memop.  If the decompressor expanded a reserved word (NoMem's 0x6002) into a
// memory operation this would be REFUTED -- which would itself be a finding.
logic h3_cti_raw_is_mem_word;
assign h3_cti_raw_is_mem_word =
    ((h3_x_instr[1:0] == 2'b11) && ((h3_x_instr[6:0] == 7'b0000011) ||
                                    (h3_x_instr[6:0] == 7'b0100011))) ||
    ((h3_x_instr[1:0] == 2'b00) && ((h3_x_instr[15:13] == 3'b010) ||
                                    (h3_x_instr[15:13] == 3'b110))) ||
    ((h3_x_instr[1:0] == 2'b10) && ((h3_x_instr[15:13] == 3'b010) ||
                                    (h3_x_instr[15:13] == 3'b110)));

logic h3_cti_memop_is_load_store_word;
assign h3_cti_memop_is_load_store_word =
    !h3_x_progress || (cpu.core.d_memop == H3_MEMOP_NONE) || h3_cti_raw_is_mem_word;
`include "h3_cti_round4.svh"
