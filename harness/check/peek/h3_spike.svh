// ===========================================================================
// check/peek/h3_spike.svh -- SPIKE.  Delete or promote after evaluation.
//
// Tests the one combination never tried: BOUNDED + ONE INSTRUCTION CLASS +
// SAME-CYCLE value comparison.  RVFI sidesteps the post-state problem that
// blocked everything today: rvfi_rd_wdata IS the value the core wrote, by the
// core author's own definition -- not a harness reconstruction, so the "a copy
// hides the bug" objection does not apply and no RTL refactor is needed.
//
// h3_fol_spec_wX is Sail's answer for the same instruction. Follower/monitor
// alignment is already PROVEN (FollowerInstrMatchesMonitor at step 0).
// ===========================================================================
`define INSTR h3_rvfi_insn
`include "isa/encodings.svh"

// Sail's answer delayed one cycle, in case RVFI (writeback) lags the follower (M).
logic        h3_spk_wX_en_q;
logic [4:0]  h3_spk_wX_addr_q;
logic [31:0] h3_spk_wX_q;
initial begin
    h3_spk_wX_en_q   = 1'b0;
    h3_spk_wX_addr_q = 5'h0;
    h3_spk_wX_q      = 32'h0;
end
always @ (posedge clk_i) begin
    h3_spk_wX_en_q   <= h3_fol_spec_wX_en;
    h3_spk_wX_addr_q <= h3_fol_spec_wX_addr;
    h3_spk_wX_q      <= h3_fol_spec_wX;
end


// --- CTI-DERIVED LEMMAS (loop turn 1) ---------------------------------------
// L1. The destination register RVFI reports is the one encoded in the
// instruction RVFI reports. hdl/hazard3_rvfi_monitor.vh:220 drives rd_addr from
// mw_rd, which is the pipe register carrying that instruction's rd field.
logic h3_cti_rd_addr_matches_insn;
assign h3_cti_rd_addr_matches_insn =
    !h3_rvfi_valid || !(|h3_rvfi_rd_addr) ||
    (h3_rvfi_insn[1:0] != 2'b11) ||        // RVC: rvfi_insn is the ORIGINAL 16-bit form
    (h3_rvfi_rd_addr == h3_rvfi_insn[11:7]);

// L2. The follower and the monitor track the SAME instruction, one cycle apart
// (RVFI retires at writeback, the follower tracks M -- established by the
// refutation of the same-cycle spike variants and confirmed by the lag variant
// not being refuted at that depth).
logic [31:0] h3_cti_fol_instr_q;
logic        h3_cti_fol_valid_q;
initial begin
    h3_cti_fol_instr_q = 32'h0;
    h3_cti_fol_valid_q = 1'b0;
end
always @ (posedge clk_i) begin
    h3_cti_fol_instr_q <= h3_fol_instr;
    h3_cti_fol_valid_q <= h3_fol_valid;
end

logic h3_cti_fol_instr_matches_rvfi;
assign h3_cti_fol_instr_matches_rvfi =
    !h3_rvfi_valid || !h3_cti_fol_valid_q ||
    (h3_rvfi_insn[1:0] != 2'b11) ||        // RVC: follower holds the EXPANDED form
    (h3_cti_fol_instr_q == h3_rvfi_insn);

// ---- Add ----------------------------------------------------------------
logic h3_spike_add_same;
assign h3_spike_add_same =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_ADD) || !(|h3_rvfi_rd_addr) ||
    !h3_fol_spec_wX_en || (h3_fol_spec_wX_addr != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_fol_spec_wX);

logic h3_spike_add_lag;
assign h3_spike_add_lag =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_ADD) || !(|h3_rvfi_rd_addr) ||
    !h3_spk_wX_en_q || (h3_spk_wX_addr_q != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_spk_wX_q);

// vacuity control -- MUST FAIL, else the guard is unreachable
logic h3_spike_add_reach;
assign h3_spike_add_reach =
    !(h3_rvfi_valid && !h3_rvfi_trap && (`IS_ADD) && (|h3_rvfi_rd_addr));

// ---- Addi ----------------------------------------------------------------
logic h3_spike_addi_same;
assign h3_spike_addi_same =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_ADDI) || !(|h3_rvfi_rd_addr) ||
    !h3_fol_spec_wX_en || (h3_fol_spec_wX_addr != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_fol_spec_wX);

logic h3_spike_addi_lag;
assign h3_spike_addi_lag =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_ADDI) || !(|h3_rvfi_rd_addr) ||
    !h3_spk_wX_en_q || (h3_spk_wX_addr_q != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_spk_wX_q);

// vacuity control -- MUST FAIL, else the guard is unreachable
logic h3_spike_addi_reach;
assign h3_spike_addi_reach =
    !(h3_rvfi_valid && !h3_rvfi_trap && (`IS_ADDI) && (|h3_rvfi_rd_addr));

// ---- Xor ----------------------------------------------------------------
logic h3_spike_xor_same;
assign h3_spike_xor_same =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_XOR) || !(|h3_rvfi_rd_addr) ||
    !h3_fol_spec_wX_en || (h3_fol_spec_wX_addr != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_fol_spec_wX);

logic h3_spike_xor_lag;
assign h3_spike_xor_lag =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_XOR) || !(|h3_rvfi_rd_addr) ||
    !h3_spk_wX_en_q || (h3_spk_wX_addr_q != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_spk_wX_q);

// vacuity control -- MUST FAIL, else the guard is unreachable
logic h3_spike_xor_reach;
assign h3_spike_xor_reach =
    !(h3_rvfi_valid && !h3_rvfi_trap && (`IS_XOR) && (|h3_rvfi_rd_addr));

// ---- Slli ----------------------------------------------------------------
logic h3_spike_slli_same;
assign h3_spike_slli_same =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_SLLI) || !(|h3_rvfi_rd_addr) ||
    !h3_fol_spec_wX_en || (h3_fol_spec_wX_addr != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_fol_spec_wX);

logic h3_spike_slli_lag;
assign h3_spike_slli_lag =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_SLLI) || !(|h3_rvfi_rd_addr) ||
    !h3_spk_wX_en_q || (h3_spk_wX_addr_q != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_spk_wX_q);

// vacuity control -- MUST FAIL, else the guard is unreachable
logic h3_spike_slli_reach;
assign h3_spike_slli_reach =
    !(h3_rvfi_valid && !h3_rvfi_trap && (`IS_SLLI) && (|h3_rvfi_rd_addr));

// ---- Lui ----------------------------------------------------------------
logic h3_spike_lui_same;
assign h3_spike_lui_same =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_LUI) || !(|h3_rvfi_rd_addr) ||
    !h3_fol_spec_wX_en || (h3_fol_spec_wX_addr != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_fol_spec_wX);

logic h3_spike_lui_lag;
assign h3_spike_lui_lag =
    !h3_rvfi_valid || h3_rvfi_trap || !(`IS_LUI) || !(|h3_rvfi_rd_addr) ||
    !h3_spk_wX_en_q || (h3_spk_wX_addr_q != h3_rvfi_rd_addr) ||
    (h3_rvfi_rd_wdata == h3_spk_wX_q);

// vacuity control -- MUST FAIL, else the guard is unreachable
logic h3_spike_lui_reach;
assign h3_spike_lui_reach =
    !(h3_rvfi_valid && !h3_rvfi_trap && (`IS_LUI) && (|h3_rvfi_rd_addr));
`include "h3_cti_round1.svh"
