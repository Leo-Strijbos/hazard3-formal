// ===========================================================================
// Round 28.  RegMatch, second form, and the specifiable guard.
//
// Round 26: CtiFolXExceptNoSpecWrite and CtiFolSpecWxEnIsRdV2 REFUTED from
// reset by CSR instructions on addresses OUTSIDE the harness's checkable list
// (results/cex/round26-*: csrrs x31, pmpaddr15 -- Hazard3 traps, PMP absent;
// Sail's stub has 16 regions and reads it; csrrci x31, 0xbf1 -- Hazard3
// accepts, Sail traps).  That is exactly the class h3_x_query_checkable
// (h3_abs.svh:376-396) excludes from the ghost, so both rungs take the same
// guard, reconstructed from the follower's instruction bits.
//
// Round 26's RegMatch CTIs (results/icti/round26-CtiRegMatch01): M holds an
// instruction with xm_rd = 1 and NO specification write for it
// (h3_fol_spec_wX_en = 0) while register 1 already differs from the ghost --
// the round-24 excuse "M holds a pending write to i" hid a mismatch that was
// never going to be repaired.  The excuse is narrowed to "the follower says
// the specification wrote i for the instruction in M", which is the only case
// in which the DUT's register may lag the ghost.
// ===========================================================================
logic h3_fol_specifiable;
assign h3_fol_specifiable = !h3_fol_is_csr || h3_fol_csr_checkable;
logic h3_cti_fol_x_except_no_spec_write_v2;
assign h3_cti_fol_x_except_no_spec_write_v2 =
    !h3_fol_valid || !h3_fol_x_except || !h3_fol_specifiable || !h3_fol_spec_wX_en;
logic h3_cti_fol_spec_wx_en_is_rd_v3;
assign h3_cti_fol_spec_wx_en_is_rd_v3 =
    !h3_fol_clean_write || !h3_fol_specifiable ||
    ((h3_fol_spec_wX_en && (|h3_fol_spec_wX_addr)) == (|h3_fol_rd));
logic h3_fol_pending_write;
assign h3_fol_pending_write = h3_m_valid && h3_fol_valid && h3_fol_spec_wX_en;
logic h3_cti_reg_match_v2_1;
assign h3_cti_reg_match_v2_1 =
    !h3_ghost_has_reg[1] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd1) && (h3_fol_spec_wX_addr == 5'd1)) ||
    (pre_regs[1] == h3_ghost_regs[1]);

logic h3_cti_reg_match_v2_2;
assign h3_cti_reg_match_v2_2 =
    !h3_ghost_has_reg[2] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd2) && (h3_fol_spec_wX_addr == 5'd2)) ||
    (pre_regs[2] == h3_ghost_regs[2]);

logic h3_cti_reg_match_v2_3;
assign h3_cti_reg_match_v2_3 =
    !h3_ghost_has_reg[3] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd3) && (h3_fol_spec_wX_addr == 5'd3)) ||
    (pre_regs[3] == h3_ghost_regs[3]);

logic h3_cti_reg_match_v2_4;
assign h3_cti_reg_match_v2_4 =
    !h3_ghost_has_reg[4] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd4) && (h3_fol_spec_wX_addr == 5'd4)) ||
    (pre_regs[4] == h3_ghost_regs[4]);

logic h3_cti_reg_match_v2_5;
assign h3_cti_reg_match_v2_5 =
    !h3_ghost_has_reg[5] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd5) && (h3_fol_spec_wX_addr == 5'd5)) ||
    (pre_regs[5] == h3_ghost_regs[5]);

logic h3_cti_reg_match_v2_6;
assign h3_cti_reg_match_v2_6 =
    !h3_ghost_has_reg[6] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd6) && (h3_fol_spec_wX_addr == 5'd6)) ||
    (pre_regs[6] == h3_ghost_regs[6]);

logic h3_cti_reg_match_v2_7;
assign h3_cti_reg_match_v2_7 =
    !h3_ghost_has_reg[7] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd7) && (h3_fol_spec_wX_addr == 5'd7)) ||
    (pre_regs[7] == h3_ghost_regs[7]);

logic h3_cti_reg_match_v2_8;
assign h3_cti_reg_match_v2_8 =
    !h3_ghost_has_reg[8] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd8) && (h3_fol_spec_wX_addr == 5'd8)) ||
    (pre_regs[8] == h3_ghost_regs[8]);

logic h3_cti_reg_match_v2_9;
assign h3_cti_reg_match_v2_9 =
    !h3_ghost_has_reg[9] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd9) && (h3_fol_spec_wX_addr == 5'd9)) ||
    (pre_regs[9] == h3_ghost_regs[9]);

logic h3_cti_reg_match_v2_10;
assign h3_cti_reg_match_v2_10 =
    !h3_ghost_has_reg[10] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd10) && (h3_fol_spec_wX_addr == 5'd10)) ||
    (pre_regs[10] == h3_ghost_regs[10]);

logic h3_cti_reg_match_v2_11;
assign h3_cti_reg_match_v2_11 =
    !h3_ghost_has_reg[11] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd11) && (h3_fol_spec_wX_addr == 5'd11)) ||
    (pre_regs[11] == h3_ghost_regs[11]);

logic h3_cti_reg_match_v2_12;
assign h3_cti_reg_match_v2_12 =
    !h3_ghost_has_reg[12] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd12) && (h3_fol_spec_wX_addr == 5'd12)) ||
    (pre_regs[12] == h3_ghost_regs[12]);

logic h3_cti_reg_match_v2_13;
assign h3_cti_reg_match_v2_13 =
    !h3_ghost_has_reg[13] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd13) && (h3_fol_spec_wX_addr == 5'd13)) ||
    (pre_regs[13] == h3_ghost_regs[13]);

logic h3_cti_reg_match_v2_14;
assign h3_cti_reg_match_v2_14 =
    !h3_ghost_has_reg[14] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd14) && (h3_fol_spec_wX_addr == 5'd14)) ||
    (pre_regs[14] == h3_ghost_regs[14]);

logic h3_cti_reg_match_v2_15;
assign h3_cti_reg_match_v2_15 =
    !h3_ghost_has_reg[15] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd15) && (h3_fol_spec_wX_addr == 5'd15)) ||
    (pre_regs[15] == h3_ghost_regs[15]);

logic h3_cti_reg_match_v2_16;
assign h3_cti_reg_match_v2_16 =
    !h3_ghost_has_reg[16] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd16) && (h3_fol_spec_wX_addr == 5'd16)) ||
    (pre_regs[16] == h3_ghost_regs[16]);

logic h3_cti_reg_match_v2_17;
assign h3_cti_reg_match_v2_17 =
    !h3_ghost_has_reg[17] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd17) && (h3_fol_spec_wX_addr == 5'd17)) ||
    (pre_regs[17] == h3_ghost_regs[17]);

logic h3_cti_reg_match_v2_18;
assign h3_cti_reg_match_v2_18 =
    !h3_ghost_has_reg[18] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd18) && (h3_fol_spec_wX_addr == 5'd18)) ||
    (pre_regs[18] == h3_ghost_regs[18]);

logic h3_cti_reg_match_v2_19;
assign h3_cti_reg_match_v2_19 =
    !h3_ghost_has_reg[19] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd19) && (h3_fol_spec_wX_addr == 5'd19)) ||
    (pre_regs[19] == h3_ghost_regs[19]);

logic h3_cti_reg_match_v2_20;
assign h3_cti_reg_match_v2_20 =
    !h3_ghost_has_reg[20] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd20) && (h3_fol_spec_wX_addr == 5'd20)) ||
    (pre_regs[20] == h3_ghost_regs[20]);

logic h3_cti_reg_match_v2_21;
assign h3_cti_reg_match_v2_21 =
    !h3_ghost_has_reg[21] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd21) && (h3_fol_spec_wX_addr == 5'd21)) ||
    (pre_regs[21] == h3_ghost_regs[21]);

logic h3_cti_reg_match_v2_22;
assign h3_cti_reg_match_v2_22 =
    !h3_ghost_has_reg[22] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd22) && (h3_fol_spec_wX_addr == 5'd22)) ||
    (pre_regs[22] == h3_ghost_regs[22]);

logic h3_cti_reg_match_v2_23;
assign h3_cti_reg_match_v2_23 =
    !h3_ghost_has_reg[23] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd23) && (h3_fol_spec_wX_addr == 5'd23)) ||
    (pre_regs[23] == h3_ghost_regs[23]);

logic h3_cti_reg_match_v2_24;
assign h3_cti_reg_match_v2_24 =
    !h3_ghost_has_reg[24] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd24) && (h3_fol_spec_wX_addr == 5'd24)) ||
    (pre_regs[24] == h3_ghost_regs[24]);

logic h3_cti_reg_match_v2_25;
assign h3_cti_reg_match_v2_25 =
    !h3_ghost_has_reg[25] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd25) && (h3_fol_spec_wX_addr == 5'd25)) ||
    (pre_regs[25] == h3_ghost_regs[25]);

logic h3_cti_reg_match_v2_26;
assign h3_cti_reg_match_v2_26 =
    !h3_ghost_has_reg[26] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd26) && (h3_fol_spec_wX_addr == 5'd26)) ||
    (pre_regs[26] == h3_ghost_regs[26]);

logic h3_cti_reg_match_v2_27;
assign h3_cti_reg_match_v2_27 =
    !h3_ghost_has_reg[27] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd27) && (h3_fol_spec_wX_addr == 5'd27)) ||
    (pre_regs[27] == h3_ghost_regs[27]);

logic h3_cti_reg_match_v2_28;
assign h3_cti_reg_match_v2_28 =
    !h3_ghost_has_reg[28] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd28) && (h3_fol_spec_wX_addr == 5'd28)) ||
    (pre_regs[28] == h3_ghost_regs[28]);

logic h3_cti_reg_match_v2_29;
assign h3_cti_reg_match_v2_29 =
    !h3_ghost_has_reg[29] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd29) && (h3_fol_spec_wX_addr == 5'd29)) ||
    (pre_regs[29] == h3_ghost_regs[29]);

logic h3_cti_reg_match_v2_30;
assign h3_cti_reg_match_v2_30 =
    !h3_ghost_has_reg[30] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd30) && (h3_fol_spec_wX_addr == 5'd30)) ||
    (pre_regs[30] == h3_ghost_regs[30]);

logic h3_cti_reg_match_v2_31;
assign h3_cti_reg_match_v2_31 =
    !h3_ghost_has_reg[31] ||
    (h3_fol_pending_write && (cpu.core.xm_rd == 5'd31) && (h3_fol_spec_wX_addr == 5'd31)) ||
    (pre_regs[31] == h3_ghost_regs[31]);
`include "h3_cti_round29.svh"
