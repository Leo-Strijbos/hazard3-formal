// ===========================================================================
// check/peek/h3_cti_round6.svh -- round 6: pipe registers stay inside the
// decoder's image; the follower lemma gets its fetch-error guard.
//
// Round 5's parallel induction-CTIs for both operand lemmas
// (results/icti/round5-CtiRs1BypassIsPreRegs, -CtiRs2BypassIsPreRegsV2) show
// a LOAD completing in M into the very register X reads, with X progressing.
// The interlock (core.v:445-470) fires only if m_generating_result, i.e.
// xm_memop < MEMOP_SW (a load) or an LR/SC/mul.  With EXTENSION_A = 0 the
// decoder can only ever emit loads (0..4), SW/SH/SB (5..7) or NONE (0x10);
// but xm_memop is a free 5-bit latch, so an induction state can hold an
// LR/SC/AMO code: m_dphase_in_flight is true (!= NONE, != AMO), the interlock
// is silent (not < SW, the A terms are gated off), m_result is
// m_rdata_pick_sext's default 32'hxxxx (FREE), and m_reg_wen writes it to
// xm_rd.  Same class as the store-rd hole: a pipe register outside the
// decoder's image.  Stated as the image, not as "no A ops".
// ===========================================================================
localparam [4:0] H3_MEMOP_LEGAL_MAX = 5'h07;   // hazard3_ops.vh: MEMOP_SB

logic h3_cti_d_memop_legal;          // combinational: the decoder's image
assign h3_cti_d_memop_legal =
    (cpu.core.d_memop <= H3_MEMOP_LEGAL_MAX) || (cpu.core.d_memop == H3_MEMOP_NONE);

logic h3_cti_xm_memop_legal;         // one step above: xm_memop <= d_memop
assign h3_cti_xm_memop_legal =
    (cpu.core.xm_memop <= H3_MEMOP_LEGAL_MAX) || (cpu.core.xm_memop == H3_MEMOP_NONE);

// --- follower mscratch link, with the guard the goal itself has ------------
// results/icti/round5-CtiFollowerPostIsDutMscratch: the instruction at the
// query excepted on FETCH; Sail's answer for a fetch-error query is
// unconstrained by design (SpecEnUnreachIdex / IFERR mode), the ghost is not
// loaded for it (h3_query_specifiable), so the goal is vacuous there -- and
// the follower lemma must be too.  Only fetch errors are excused: for an
// ordinary exception Sail does answer (mscratch unchanged) and the lemma
// stays live.  CtiFolIntErrIsFetchErr (proved) ties int_err to fetch_err.
logic h3_cti_follower_post_is_dut_mscratch_v2;
assign h3_cti_follower_post_is_dut_mscratch_v2 =
    !h3_fol_valid || h3_fol_fetch_err ||
    (pre_mscratch == h3_fol_spec_post_mscratch);

// --- the other member of the class: xm_except stays in its image ----------
// hazard3_ops.vh:95-113 defines the EXCEPT_* codes. In this configuration no
// path assigns ECALL_U (8: misa has no U-mode, the decoder picks ECALL_M) and
// nothing defines 9, c, d.  x_except (core.v:1113-1124) is the decoder's
// d_except or one of the listed codes; xm_except <= x_except.  Stated as the
// image, one combinational rung and one registered rung above it, exactly
// like the memop pair.  (REFETCH, e, is already excluded by the proved
// NoRefetchException at step 0 and is left out here.)
logic h3_cti_d_except_legal;
assign h3_cti_d_except_legal =
    (cpu.core.d_except != 4'h8) && (cpu.core.d_except != 4'h9) &&
    (cpu.core.d_except != 4'hc) && (cpu.core.d_except != 4'hd);

logic h3_cti_xm_except_legal;
assign h3_cti_xm_except_legal =
    (cpu.core.xm_except != 4'h8) && (cpu.core.xm_except != 4'h9) &&
    (cpu.core.xm_except != 4'hc) && (cpu.core.xm_except != 4'hd);
`include "h3_cti_round7.svh"
