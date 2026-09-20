// ===========================================================================
// Round 12.  A full batch: the compressed predecode twins, the spec-side
// frames for mepc/mcause, and three ghost ties tried directly on their frames.
//
// The DUT-side trap-aware frames for mepc/mcause/mstatus ALREADY EXIST and are
// PROVED at low steps (MepcChangeHasCause proof:72, McauseChangeHasCause :133,
// McauseChangeHasCauseFull :219, MstatusChangeHasCause :220), so this round
// does not restate them.  mepc has exactly two RTL writers (hazard3_csr.v:313
// trap entry, :315 CSR write); mcause is written at :369-370 from
// mcause_*_next.  Both checked before writing anything (the mie lesson).
// ===========================================================================

// --- R12.1/R12.2  the compressed twins of round 9's predecode-agreement rungs
// Round 9 proved d_rs{1,2}_predecoded == fd_cir_raw[19:15]/[24:20] for a
// 32-bit CIR.  A compressed CIR holds the EXPANDED word in fd_cir while the
// predecode saw the 16-bit halfword, so the twin compares against
// fd_cir_raw[15:0] and transcribes hazard3_frontend.v:737-746 (coarse rs1),
// :748-760 (coarse rs2) and :771-789 (fine) with the dead ZCMP/ZILSD/ZCLSD
// arms omitted (all three extensions are 0 in this build).  Arm order is the
// RTL's casez priority.  REGADDR_MASK is 5'h1f (EXTENSION_E = 0).
logic [15:0] h3_cir16;
assign h3_cir16 = cpu.core.fd_cir_raw[15:0];

logic [4:0] h3_c_rs1_coarse;
assign h3_c_rs1_coarse =
    (h3_cir16[1:0] == 2'b00 && h3_cir16[15:14] == 2'b00) ? 5'd2            : // c.addi4spn
    (h3_cir16[1:0] == 2'b01 && !h3_cir16[15])            ? h3_cir16[11:7]  : // c.addi, c.li, c.jal ...
    (h3_cir16[1:0] == 2'b10 &&  h3_cir16[14])            ? 5'd2            : // c.lwsp, c.swsp
    (h3_cir16[1:0] == 2'b10 && h3_cir16[14:13] == 2'b00) ? h3_cir16[11:7]  : // c.slli, c.mv, c.add
                                                            {2'b01, h3_cir16[9:7]}; // rs1' (c.sw, c.lw, c.beqz ...)
logic [4:0] h3_c_rs1_fine;
assign h3_c_rs1_fine =
    (h3_cir16[15:13] == 3'b010  && h3_cir16[1:0] == 2'b01)                     ? 5'd0 : // C.LI  -> addi rd, x0, imm
    (h3_cir16[15:12] == 4'b1000 && h3_cir16[1:0] == 2'b10 && |h3_cir16[6:2])   ? 5'd0 : // C.MV  -> add rd, x0, rs2 (C.JR keeps rs1)
                                                                                 h3_c_rs1_coarse;
logic h3_cti_rs1_predecode_agrees_cir16;
assign h3_cti_rs1_predecode_agrees_cir16 =
    cpu.core.fd_cir_is_32bit || !cpu.core.fd_cir_vld[0] ||
    (cpu.core.d_rs1_predecoded == h3_c_rs1_fine);

logic [4:0] h3_c_rs2_coarse;
assign h3_c_rs2_coarse =
    (h3_cir16[1:0] == 2'b10 && !h3_cir16[13]) ? h3_cir16[6:2]            // c.add, c.swsp, c.mv
                                              : {2'b01, h3_cir16[4:2]};  // rs2' (c.sw ...)
logic [4:0] h3_c_rs2_fine;
assign h3_c_rs2_fine =
    (h3_cir16[15:13] == 3'b110 && h3_cir16[1:0] == 2'b01) ? 5'd0 :   // C.BEQZ -> beq rs1, x0
    (h3_cir16[15:13] == 3'b111 && h3_cir16[1:0] == 2'b01) ? 5'd0 :   // C.BNEZ -> bne rs1, x0
                                                             h3_c_rs2_coarse;
logic h3_cti_rs2_predecode_agrees_cir16;
assign h3_cti_rs2_predecode_agrees_cir16 =
    cpu.core.fd_cir_is_32bit || !cpu.core.fd_cir_vld[0] ||
    (cpu.core.d_rs2_predecoded == h3_c_rs2_fine);

// --- R12.3/R12.4  spec-side frames for the trap CSRs --------------------------
// The proven mscratch/mie/mtvec frames excuse only a CSR write to the register.
// mepc and mcause are ALSO written by trap entry, and the spec exposes no trap
// flag -- but RISC-V semantics supply one: on ANY trap the spec sets mepc to
// the trapping pc, so (spec_post_mepc == pre_pc) is the trap indicator.  Both
// frames use it as their extra excuse.  If either refutes, the witness will say
// which case is missing.
logic h3_cti_spec_mepc_frame;
assign h3_cti_spec_mepc_frame =
    !h3_spec_en ||
    (h3_spec_mode == H3_MAIN_IFERR) ||
    ((h3_spec_mode == H3_MAIN_IDEX) &&
     (h3_x_instr[6:0]   == 7'h73)   &&
     (h3_x_instr[14:12] != 3'b000)  &&
     (h3_x_instr[31:20] == 12'h341)) ||
    (spec_post_mepc == pre_pc) ||
    (spec_post_mepc == pre_mepc);

logic h3_cti_spec_mcause_frame;
assign h3_cti_spec_mcause_frame =
    !h3_spec_en ||
    (h3_spec_mode == H3_MAIN_IFERR) ||
    ((h3_spec_mode == H3_MAIN_IDEX) &&
     (h3_x_instr[6:0]   == 7'h73)   &&
     (h3_x_instr[14:12] != 3'b000)  &&
     (h3_x_instr[31:20] == 12'h342)) ||
    (spec_post_mepc == pre_pc) ||
    (spec_post_mcause == pre_mcause);

// --- R12.5-R12.7  ghost ties, tried directly on the frames -------------------
// mie and mtvec both proved their ghost tie with NO link rung.  Same shape,
// each the goal in strengthened form (the goal adds an !h3_spec_en disjunct).
// mstatus is deliberately omitted: WrapMstatus is refuted from reset by the
// MPRV/TW divergences, so its tie is false.
logic h3_cti_ghost_tracks_mepc;
assign h3_cti_ghost_tracks_mepc   = !h3_has_ghost || (pre_mepc   == h3_ghost_mepc);
logic h3_cti_ghost_tracks_mcause;
assign h3_cti_ghost_tracks_mcause = !h3_has_ghost || (pre_mcause == h3_ghost_mcause);
logic h3_cti_ghost_tracks_pc;
assign h3_cti_ghost_tracks_pc     = !h3_has_ghost || (pre_pc     == h3_ghost_pc);
`include "h3_cti_round13.svh"
