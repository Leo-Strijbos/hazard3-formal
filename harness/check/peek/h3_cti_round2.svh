// ===========================================================================
// check/peek/h3_cti_round2.svh -- CTI-derived lemmas, batch round 2.
//
// Round 1 proved the base facts.  These are the next rung: the ones that need
// a round-1 fact beneath them, and the support CtiGhostTracksMscratch needs if
// it ground out at step 5.
// ===========================================================================

// --- R2.1  pre_mscratch moves only at a query ------------------------------
// MscratchChangeHasCause (h3_abs.svh:586) is stated over h3_x_advance, which
// includes the cycle where an instruction is consumed while m_trap_enter_soon
// is high -- NOT a query, so h3_spec_en is low and the ghost does not move.
// That is a hole the DUT could drift through invisibly.  CtiCsrWenIsQuery
// (round 1, PROVED) closes it, so the obligation can be tightened from
// h3_x_advance to h3_x_progress.
logic h3_cti_past_x_progress_writes_mscratch;
initial h3_cti_past_x_progress_writes_mscratch = 1'b0;
always @ (posedge clk_i) begin
    h3_cti_past_x_progress_writes_mscratch <= h3_x_progress && h3_x_writes_mscratch;
end

logic h3_cti_mscratch_change_is_query;
assign h3_cti_mscratch_change_is_query =
    !h3_abs_past_valid || (pre_mscratch == h3_past_pre_mscratch) ||
    h3_cti_past_x_progress_writes_mscratch;

// --- R2.2  the specification leaves mscratch alone unless told to ----------
// A frame condition on Sail over its OWN inputs.  spec_api_i.mscratch_i is
// wired straight to pre_mscratch with no use_curr select, and Sail changes
// mscratch only for a Zicsr instruction naming 0x340 (riscv_insts_zicsr.sail);
// MAIN_IRQ trap entry writes mepc/mcause/mstatus and nothing else.
// Stated over h3_x_instr (the spec's own insn_bits) rather than over the DUT's
// h3_x_writes_mscratch, so it carries no coupling to the DUT's decoder.
// RVC is safe without a guard: opcode 7'h73 forces insn[1:0] == 2'b11, so a
// compressed instruction takes the frame branch, correctly.
logic h3_cti_spec_mscratch_frame;
assign h3_cti_spec_mscratch_frame =
    !h3_spec_en ||
    (h3_spec_mode == H3_MAIN_IFERR) ||
    ((h3_spec_mode == H3_MAIN_IDEX) &&
     (h3_x_instr[6:0]   == 7'h73)   &&
     (h3_x_instr[14:12] != 3'b000)  &&
     (h3_x_instr[31:20] == 12'h340)) ||
    (spec_post_mscratch == pre_mscratch);

// --- R2.3  the specification's memory direction follows the instruction ----
// Sail reaches mem_write_value only from STORE (0100011) and the compressed
// C.SW / C.SWSP; EXTENSION_A = 0 so there are no AMOs, and MAIN_IRQ/IFERR
// execute no instruction.  h3_x_instr IS spec_api_i.insn_bits and it is the
// RAW CIR, so the compressed arms are load-bearing, not defensive: the LoadEn
// CTI's own instruction is 0x00004f82 = c.lwsp.
// Constrains only the specification's input->output relation; it deliberately
// stops at the raw bits and does NOT claim the DUT's decompressor agrees --
// that is R2.5, kept separate so the decompressor stays under test.
logic h3_cti_spec_write_is_store_insn;
assign h3_cti_spec_write_is_store_insn =
    !h3_spec_en || !spec_mem_write ||
    ((h3_spec_mode == H3_MAIN_IDEX) && (
        ((h3_x_instr[1:0] == 2'b11) && (h3_x_instr[6:0]   == 7'b0100011)) ||
        ((h3_x_instr[1:0] == 2'b00) && (h3_x_instr[15:13] == 3'b110))     ||
        ((h3_x_instr[1:0] == 2'b10) && (h3_x_instr[15:13] == 3'b110))));

logic h3_cti_spec_read_is_load_insn;
assign h3_cti_spec_read_is_load_insn =
    !h3_spec_en || !spec_mem_read ||
    ((h3_spec_mode == H3_MAIN_IDEX) && (
        ((h3_x_instr[1:0] == 2'b11) && (h3_x_instr[6:0]   == 7'b0000011)) ||
        ((h3_x_instr[1:0] == 2'b00) && (h3_x_instr[15:13] == 3'b010))     ||
        ((h3_x_instr[1:0] == 2'b10) && (h3_x_instr[15:13] == 3'b010))));

// --- R2.5  a raw store/load stays a store/load after decompression ---------
// hazard3_instr_decompress.v maps C.SW -> SW and C.SWSP -> SW (likewise the
// loads), and fd_cir is the decompression of fd_cir_raw.  One direction only,
// and the WEAK one: it says a store stays a store, not that the expansion is
// correct.  A decompressor producing SW with the wrong rs1/rs2/immediate still
// fails StoreAddr/StoreWData; one turning a non-store into a store still fails
// NoMem.  (This is the shape of the C.ADDI4SPN bug this project already found,
// so the decompressor is deliberately NOT assumed correct.)
logic h3_cti_raw_store_decompresses_to_store;
assign h3_cti_raw_store_decompresses_to_store =
    !h3_x_progress ||
    !( ((h3_x_instr[1:0] == 2'b11) && (h3_x_instr[6:0]   == 7'b0100011)) ||
       ((h3_x_instr[1:0] == 2'b00) && (h3_x_instr[15:13] == 3'b110))     ||
       ((h3_x_instr[1:0] == 2'b10) && (h3_x_instr[15:13] == 3'b110)) ) ||
    (cpu.core.fd_cir[6:0] == 7'b0100011);

logic h3_cti_raw_load_decompresses_to_load;
assign h3_cti_raw_load_decompresses_to_load =
    !h3_x_progress ||
    !( ((h3_x_instr[1:0] == 2'b11) && (h3_x_instr[6:0]   == 7'b0000011)) ||
       ((h3_x_instr[1:0] == 2'b00) && (h3_x_instr[15:13] == 3'b010))     ||
       ((h3_x_instr[1:0] == 2'b10) && (h3_x_instr[15:13] == 3'b010)) ) ||
    (cpu.core.fd_cir[6:0] == 7'b0000011);

// ===========================================================================
// Layer B -- need a layer-A fact.
// ===========================================================================

// --- R2.6  the follower's recorded mscratch is the DUT's -------------------
// h3_follower.svh:50-59, the file's own design premise: Hazard3's CSR file
// already holds the retiring instruction's post-state during its retire cycle,
// because a CSR write lands at the X->M handoff and the next instruction
// cannot leave X until the one in M retires.  The follower is loaded at that
// same edge.  DEPENDS ON CtiCsrWenIsQuery (round 1) and XProgressEmptiesM.
// NOT implied by GhostMatchesFollowerMscratch: that relates two copies of the
// same latched word and has no DUT term.
logic h3_cti_follower_post_is_dut_mscratch;
assign h3_cti_follower_post_is_dut_mscratch =
    !h3_fol_valid || (pre_mscratch == h3_fol_spec_post_mscratch);

// --- R2.7  a follower memory record implies a memory op in M --------------
// xm_memop is the X->M pipe register, loaded from d_memop on the same !x_stall
// that loads the follower.  DEPENDS ON R2.3/R2.4.  The h3_fol_except carve-out
// is needed because an excepting instruction's xm_memop is cancelled.
logic h3_cti_follower_mem_has_xm_memop;
assign h3_cti_follower_mem_has_xm_memop =
    !h3_fol_valid ||
    !(h3_fol_spec_mem_read || h3_fol_spec_mem_write) ||
    h3_fol_except ||
    (cpu.core.xm_memop != H3_MEMOP_NONE);

// ===========================================================================
// Layer C -- the all-index register invariant.
//
// GhostRegMatchesFollower ties ONE entry (the follower's) to the follower's
// own copy.  The probe device (h3_abs.svh:407-423) is sound for an ASSERTION
// -- the solver picks the index, so proving it there proves it everywhere --
// but useless as an ASSUMPTION inside another property, because the solver
// picks the probe in the same trace it picks d_rs1 and will pick them
// different.  The WrapRegA CTI does exactly that.  So the ghost/DUT register
// invariant has to be stated over ALL indices.
// Strictly stronger than WrapRegA/WrapRegB, hence sound: a register file that
// disagreed with the specification fails this first and harder.
// ===========================================================================
logic [31:0] h3_cti_ghost_reg_entry_ok;
assign h3_cti_ghost_reg_entry_ok[0] = 1'b1;       // x0 is deliberately unknown
for (genvar gk = 1; gk < 32; gk = gk + 1) begin: g_h3_cti_ghost_reg_entry_ok
    assign h3_cti_ghost_reg_entry_ok[gk] =
        !h3_ghost_has_reg[gk] || (pre_regs[gk] == h3_ghost_regs[gk]);
end

logic h3_cti_ghost_regs_match_dut;
assign h3_cti_ghost_regs_match_dut = !h3_spec_en || (&h3_cti_ghost_reg_entry_ok);
`include "h3_cti_round3.svh"
