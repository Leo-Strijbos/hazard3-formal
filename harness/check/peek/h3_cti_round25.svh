// ===========================================================================
// Round 25.  Writeback-value class lemmas, batch 5: loads and CSR reads.
//
// Loads: the value is not in xm_result but in m_result = m_rdata_pick_sext
// (hazard3_core.v:1443-1455, lane pick + extension from bus_rdata_d), which
// exists only when the data phase completes; the specification computed its
// wX from h3_spec_rdata, a free input that gate 5's one assumption
// (h3_goals.svh:293) pins to the bus data exactly on that cycle
// (h3_fol_valid && h3_fol_spec_mem_read && h3_mem_dph_active &&
// h3_mem_dph_end), and the load retires on it (m_bus_stall, core.v:1387).
// So the lemma is stated AT RETIRE, which is also the edge RegMatch needs.
// LoadAddr (goal #7) already gives the same word address on both sides.
//
// CSR reads: xm_result <= x_csr_rdata at X-exit (core.v:1359) and the spec's
// wX is the CSR's pre-value; the residency form of round 18 applies, but only
// for the addresses the harness calls checkable (h3_abs.svh:376-392) -- the
// same list that keeps the ghost trustworthy (h3_x_query_checkable).
// ===========================================================================
logic h3_fol_is_load;
assign h3_fol_is_load =
    (h3_fol_is32 && (h3_fol_instr[6:0] == 7'h03) &&
     ((h3_fol_instr[14:12] == 3'b000) || (h3_fol_instr[14:12] == 3'b001) ||
      (h3_fol_instr[14:12] == 3'b010) || (h3_fol_instr[14:12] == 3'b100) ||
      (h3_fol_instr[14:12] == 3'b101))) ||
    (h3_fol_is16 && (h3_fol_c[1:0] == 2'b00) && (h3_fol_c[15:13] == 3'b010)) ||   // C.LW
    (h3_fol_is16 && (h3_fol_c[1:0] == 2'b10) && (h3_fol_c[15:13] == 3'b010));     // C.LWSP
logic h3_cti_wb_load;
assign h3_cti_wb_load =
    !h3_retire || !h3_fol_clean_write || !h3_fol_is_load || !h3_fol_spec_wX_en ||
    (cpu.core.m_result == h3_fol_spec_wX);

logic [11:0] h3_fol_csr_addr;
assign h3_fol_csr_addr = h3_fol_instr[31:20];
logic h3_fol_is_csr;
assign h3_fol_is_csr =
    h3_fol_is32 && (h3_fol_instr[6:0] == 7'h73) &&
    (h3_fol_instr[14:12] != 3'b000) && (h3_fol_instr[14:12] != 3'b100);
logic h3_fol_csr_checkable;
assign h3_fol_csr_checkable =
    h3_fol_csr_addr == H3_CSR_MSTATUS    || h3_fol_csr_addr == H3_CSR_MSTATUSH   ||
    h3_fol_csr_addr == H3_CSR_MISA       || h3_fol_csr_addr == H3_CSR_MIE        ||
    h3_fol_csr_addr == H3_CSR_MTVEC      || h3_fol_csr_addr == H3_CSR_MCOUNTEREN ||
    h3_fol_csr_addr == H3_CSR_MSCRATCH   || h3_fol_csr_addr == H3_CSR_MEPC       ||
    h3_fol_csr_addr == H3_CSR_MCAUSE     || h3_fol_csr_addr == H3_CSR_MTVAL      ||
    h3_fol_csr_addr == H3_CSR_MIP        || h3_fol_csr_addr == H3_CSR_MVENDORID  ||
    h3_fol_csr_addr == H3_CSR_MARCHID    || h3_fol_csr_addr == H3_CSR_MIMPID     ||
    h3_fol_csr_addr == H3_CSR_MHARTID    || h3_fol_csr_addr == H3_CSR_MCONFIGPTR;
logic h3_cti_wb_csr;
assign h3_cti_wb_csr =
    !h3_fol_clean_write || !h3_fol_is_csr || !h3_fol_csr_checkable ||
    !h3_fol_spec_wX_en || (cpu.core.xm_result == h3_fol_spec_wX);
`include "h3_cti_round26.svh"
