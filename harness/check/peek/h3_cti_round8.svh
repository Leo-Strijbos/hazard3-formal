// ===========================================================================
// check/peek/h3_cti_round8.svh -- round 8: no breakpoint-trigger flags.
//
// results/icti/round6-WrapRegA and round6-WrapRegB (k=1): the goal breaks
// together with WrapPc/WrapMepc/WrapMcause/WrapMie/WrapMstatus in a state
// with cpu.core.x_except == EXCEPT_EBREAK while d_except == EXCEPT_NONE and
// the follower sees no exception.  hazard3_core.v:1113-1114 puts
// `x_trig_break ? EXCEPT_EBREAK` at the top of the exception priority, and
// :491 has x_trig_break = fd_cir_break_any || x_trig_step_break.
//
// This build has BREAKPOINT_TRIGGERS = 0 and DEBUG_SUPPORT = 0
// (hazard3_config.vh:166,170), so the frontend's `no_triggers` branch
// hardwires mem_break_any = mem_break_d_mode = 2'b00
// (hazard3_frontend.v:549-553).  The flags nevertheless travel through
// REGISTERS: fifo_break_any/fifo_break_d_mode[0..FIFO_DEPTH-1] (:151-152,
// reset 0, loaded only from mem_break_* or from the next-higher entry,
// :207-208) and the three CIR buffer slots of buf_contents (:589; slot bits
// SLOT_BREAK_ANY_BIT = 19, SLOT_BREAK_D_MODE_BIT = 18 of W_SLOT = 20,
// :583-587), loaded only from those FIFO entries (:597-598, :601-614).
// cir_break_any/cir_break_d_mode are slot 0's bits (:694-696).  Every
// source is zero and every load copies a source, so "all flags zero" is
// an inductive fact of the RTL; it is free in an induction state, and the
// CTI above is exactly that freedom.
//
// The same CIR-flag class as rounds 3b/7 (a registered description of the
// CIR must agree with the CIR): here the description is "a trigger matched
// this halfword", and no trigger exists.
// ===========================================================================

logic h3_cti_no_break_flags;
assign h3_cti_no_break_flags =
    (cpu.core.frontend.fifo_break_any[0]    == 2'b00) &&
    (cpu.core.frontend.fifo_break_any[1]    == 2'b00) &&
    (cpu.core.frontend.fifo_break_d_mode[0] == 2'b00) &&
    (cpu.core.frontend.fifo_break_d_mode[1] == 2'b00) &&
    !cpu.core.frontend.buf_contents[0*20 + 19] &&
    !cpu.core.frontend.buf_contents[1*20 + 19] &&
    !cpu.core.frontend.buf_contents[2*20 + 19] &&
    !cpu.core.frontend.buf_contents[0*20 + 18] &&
    !cpu.core.frontend.buf_contents[1*20 + 18] &&
    !cpu.core.frontend.buf_contents[2*20 + 18] &&
    !cpu.core.x_trig_break;

// ===========================================================================
// results/icti/round7-CtiStoreDataIsRegfile (k=1): a `sw` in M whose data
// phase completes in frame 0 (bus_dph_ready_d = 1) -- so m_bus_stall drops,
// m_reg_wen_if_nonzero = !m_bus_stall && xm_except == NONE (core.v:1509)
// fires and mw_rd <= xm_rd = 0 (:1559-1560), removing m_wdata's forwarding
// source (:1430-1434) -- yet the store stays in M because m_stall (:1391-1393)
// is held by xm_sleep_wfi = 1.  With DEBUG_SUPPORT = 0 and xm_except == NONE
// the sleep flags are the only non-bus stall of a memory instruction in M.
// xm_sleep_wfi/xm_sleep_block are pipe registers loaded from
// x_except == NONE && d_sleep_wfi/d_sleep_block (:1274-1275), cleared on
// flush (:1286-1287); d_sleep_* come from the decoder's WFI / H3.BLOCK cases
// (decode.v:552-553), whose memop is MEMOP_NONE.  Pipe-register IMAGE class
// (round 6): a sleeping instruction in M is never a memory operation.
// ===========================================================================

logic h3_cti_xm_sleep_implies_no_memop;
assign h3_cti_xm_sleep_implies_no_memop =
    !(cpu.core.xm_sleep_wfi || cpu.core.xm_sleep_block) ||
    (cpu.core.xm_memop == H3_MEMOP_NONE);
`include "h3_cti_round9.svh"
