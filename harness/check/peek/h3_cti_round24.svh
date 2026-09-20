// ===========================================================================
// Round 24.  The register-file agreement layer (Ibex's RegMatch).
//
// results/icti/round21-WrapRegA (k=1): a progressing query with d_rs1 = x16,
// h3_ghost_has_reg[16] set, and the follower record claiming the spec wrote
// x31 (h3_fol_spec_wX_addr = 0x1f) while the pipe carries xm_rd = x15.
// FollowerRdMatchesPipe (step 0) ties h3_fol_rd to xm_rd; nothing ties the
// specification's destination to either.  Two decode-agreement rungs first:
//   R24.1  the spec's write address is the instruction's rd
//   R24.2  the spec writes iff rd != 0 (Sail's wX(0) is a no-op and
//          GhostX0Unknown, step 0, says has_reg[0] is never set; the DUT
//          forces rd = x0 for stores/branches/fences and traps are excused)
// then, one layer up, RegMatch per architectural register i = 1..31:
//   the DUT's register equals the ghost's whenever the ghost knows it, except
//   while M holds a pending write to it (pre_regs forwards m_result only in
//   the landing cycle, h3_abs.svh:224; the ghost took the value at X-exit).
// At the landing edge the value is the class lemma's (xm_result ==
// h3_fol_spec_wX) via GhostRegMatchesFollower (step 0).  Classes not yet
// covered (loads, CSR reads, M-extension, compressed until round 23) will
// show up as CTIs of the RegMatch lemmas -- that is the point of running it.
// ===========================================================================
logic h3_fol_clean_write;
assign h3_fol_clean_write =
    h3_fol_valid && !h3_fol_except && !h3_fol_fetch_err && !h3_fol_spec_int_err;
logic h3_cti_fol_spec_wx_addr_is_rd;
assign h3_cti_fol_spec_wx_addr_is_rd =
    !h3_fol_clean_write || !h3_fol_spec_wX_en || (h3_fol_spec_wX_addr == h3_fol_rd);
logic h3_cti_fol_spec_wx_en_is_rd;
assign h3_cti_fol_spec_wx_en_is_rd =
    !h3_fol_clean_write || (h3_fol_spec_wX_en == (|h3_fol_rd));
logic h3_cti_reg_match_1;
assign h3_cti_reg_match_1 =
    !h3_ghost_has_reg[1] || (h3_m_valid && (cpu.core.xm_rd == 5'd1)) ||
    (pre_regs[1] == h3_ghost_regs[1]);

logic h3_cti_reg_match_2;
assign h3_cti_reg_match_2 =
    !h3_ghost_has_reg[2] || (h3_m_valid && (cpu.core.xm_rd == 5'd2)) ||
    (pre_regs[2] == h3_ghost_regs[2]);

logic h3_cti_reg_match_3;
assign h3_cti_reg_match_3 =
    !h3_ghost_has_reg[3] || (h3_m_valid && (cpu.core.xm_rd == 5'd3)) ||
    (pre_regs[3] == h3_ghost_regs[3]);

logic h3_cti_reg_match_4;
assign h3_cti_reg_match_4 =
    !h3_ghost_has_reg[4] || (h3_m_valid && (cpu.core.xm_rd == 5'd4)) ||
    (pre_regs[4] == h3_ghost_regs[4]);

logic h3_cti_reg_match_5;
assign h3_cti_reg_match_5 =
    !h3_ghost_has_reg[5] || (h3_m_valid && (cpu.core.xm_rd == 5'd5)) ||
    (pre_regs[5] == h3_ghost_regs[5]);

logic h3_cti_reg_match_6;
assign h3_cti_reg_match_6 =
    !h3_ghost_has_reg[6] || (h3_m_valid && (cpu.core.xm_rd == 5'd6)) ||
    (pre_regs[6] == h3_ghost_regs[6]);

logic h3_cti_reg_match_7;
assign h3_cti_reg_match_7 =
    !h3_ghost_has_reg[7] || (h3_m_valid && (cpu.core.xm_rd == 5'd7)) ||
    (pre_regs[7] == h3_ghost_regs[7]);

logic h3_cti_reg_match_8;
assign h3_cti_reg_match_8 =
    !h3_ghost_has_reg[8] || (h3_m_valid && (cpu.core.xm_rd == 5'd8)) ||
    (pre_regs[8] == h3_ghost_regs[8]);

logic h3_cti_reg_match_9;
assign h3_cti_reg_match_9 =
    !h3_ghost_has_reg[9] || (h3_m_valid && (cpu.core.xm_rd == 5'd9)) ||
    (pre_regs[9] == h3_ghost_regs[9]);

logic h3_cti_reg_match_10;
assign h3_cti_reg_match_10 =
    !h3_ghost_has_reg[10] || (h3_m_valid && (cpu.core.xm_rd == 5'd10)) ||
    (pre_regs[10] == h3_ghost_regs[10]);

logic h3_cti_reg_match_11;
assign h3_cti_reg_match_11 =
    !h3_ghost_has_reg[11] || (h3_m_valid && (cpu.core.xm_rd == 5'd11)) ||
    (pre_regs[11] == h3_ghost_regs[11]);

logic h3_cti_reg_match_12;
assign h3_cti_reg_match_12 =
    !h3_ghost_has_reg[12] || (h3_m_valid && (cpu.core.xm_rd == 5'd12)) ||
    (pre_regs[12] == h3_ghost_regs[12]);

logic h3_cti_reg_match_13;
assign h3_cti_reg_match_13 =
    !h3_ghost_has_reg[13] || (h3_m_valid && (cpu.core.xm_rd == 5'd13)) ||
    (pre_regs[13] == h3_ghost_regs[13]);

logic h3_cti_reg_match_14;
assign h3_cti_reg_match_14 =
    !h3_ghost_has_reg[14] || (h3_m_valid && (cpu.core.xm_rd == 5'd14)) ||
    (pre_regs[14] == h3_ghost_regs[14]);

logic h3_cti_reg_match_15;
assign h3_cti_reg_match_15 =
    !h3_ghost_has_reg[15] || (h3_m_valid && (cpu.core.xm_rd == 5'd15)) ||
    (pre_regs[15] == h3_ghost_regs[15]);

logic h3_cti_reg_match_16;
assign h3_cti_reg_match_16 =
    !h3_ghost_has_reg[16] || (h3_m_valid && (cpu.core.xm_rd == 5'd16)) ||
    (pre_regs[16] == h3_ghost_regs[16]);

logic h3_cti_reg_match_17;
assign h3_cti_reg_match_17 =
    !h3_ghost_has_reg[17] || (h3_m_valid && (cpu.core.xm_rd == 5'd17)) ||
    (pre_regs[17] == h3_ghost_regs[17]);

logic h3_cti_reg_match_18;
assign h3_cti_reg_match_18 =
    !h3_ghost_has_reg[18] || (h3_m_valid && (cpu.core.xm_rd == 5'd18)) ||
    (pre_regs[18] == h3_ghost_regs[18]);

logic h3_cti_reg_match_19;
assign h3_cti_reg_match_19 =
    !h3_ghost_has_reg[19] || (h3_m_valid && (cpu.core.xm_rd == 5'd19)) ||
    (pre_regs[19] == h3_ghost_regs[19]);

logic h3_cti_reg_match_20;
assign h3_cti_reg_match_20 =
    !h3_ghost_has_reg[20] || (h3_m_valid && (cpu.core.xm_rd == 5'd20)) ||
    (pre_regs[20] == h3_ghost_regs[20]);

logic h3_cti_reg_match_21;
assign h3_cti_reg_match_21 =
    !h3_ghost_has_reg[21] || (h3_m_valid && (cpu.core.xm_rd == 5'd21)) ||
    (pre_regs[21] == h3_ghost_regs[21]);

logic h3_cti_reg_match_22;
assign h3_cti_reg_match_22 =
    !h3_ghost_has_reg[22] || (h3_m_valid && (cpu.core.xm_rd == 5'd22)) ||
    (pre_regs[22] == h3_ghost_regs[22]);

logic h3_cti_reg_match_23;
assign h3_cti_reg_match_23 =
    !h3_ghost_has_reg[23] || (h3_m_valid && (cpu.core.xm_rd == 5'd23)) ||
    (pre_regs[23] == h3_ghost_regs[23]);

logic h3_cti_reg_match_24;
assign h3_cti_reg_match_24 =
    !h3_ghost_has_reg[24] || (h3_m_valid && (cpu.core.xm_rd == 5'd24)) ||
    (pre_regs[24] == h3_ghost_regs[24]);

logic h3_cti_reg_match_25;
assign h3_cti_reg_match_25 =
    !h3_ghost_has_reg[25] || (h3_m_valid && (cpu.core.xm_rd == 5'd25)) ||
    (pre_regs[25] == h3_ghost_regs[25]);

logic h3_cti_reg_match_26;
assign h3_cti_reg_match_26 =
    !h3_ghost_has_reg[26] || (h3_m_valid && (cpu.core.xm_rd == 5'd26)) ||
    (pre_regs[26] == h3_ghost_regs[26]);

logic h3_cti_reg_match_27;
assign h3_cti_reg_match_27 =
    !h3_ghost_has_reg[27] || (h3_m_valid && (cpu.core.xm_rd == 5'd27)) ||
    (pre_regs[27] == h3_ghost_regs[27]);

logic h3_cti_reg_match_28;
assign h3_cti_reg_match_28 =
    !h3_ghost_has_reg[28] || (h3_m_valid && (cpu.core.xm_rd == 5'd28)) ||
    (pre_regs[28] == h3_ghost_regs[28]);

logic h3_cti_reg_match_29;
assign h3_cti_reg_match_29 =
    !h3_ghost_has_reg[29] || (h3_m_valid && (cpu.core.xm_rd == 5'd29)) ||
    (pre_regs[29] == h3_ghost_regs[29]);

logic h3_cti_reg_match_30;
assign h3_cti_reg_match_30 =
    !h3_ghost_has_reg[30] || (h3_m_valid && (cpu.core.xm_rd == 5'd30)) ||
    (pre_regs[30] == h3_ghost_regs[30]);

logic h3_cti_reg_match_31;
assign h3_cti_reg_match_31 =
    !h3_ghost_has_reg[31] || (h3_m_valid && (cpu.core.xm_rd == 5'd31)) ||
    (pre_regs[31] == h3_ghost_regs[31]);
`include "h3_cti_round25.svh"
