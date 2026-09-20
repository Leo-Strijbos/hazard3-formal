// ===========================================================================
// check/peek/h3_cti_round1.svh -- CTI-derived lemmas, batch round 1.
//
// Every lemma here was written from a counterexample-to-induction extracted
// from one of the 18 goals.  All 12 CTIs examined share ONE control state:
//   h3_spec_en=1 h3_has_ghost=1 h3_fol_valid=1 h3_retire=1 h3_x_advance=1
// with the solver setting exactly one ghost CSR to a value pre_* cannot hold.
// The 18 goals are one missing invariant seen from 18 angles.
//
// Each lemma cites the RTL line that makes it true.  RTL quotations were
// checked against hdl/ directly, not against prose.
// ===========================================================================

// --- L1.1  The two "past state is valid" flags are the same flag -----------
// h3_abs.svh:456 and h3_commit.svh:349 both assign `<= rst_ni`, so these are
// provably equal -- yet in every CTI they read 1 and 0, because in an inductive
// start state they are independent latches.  That silently voids EVERY lemma
// guarded by !h3_commit_past_valid (RetireAgreesRvfiValid, PcChangeHasCommit,
// McauseChangeHasCause, MstatusMieChangeHasCause and six more).  One line
// restores the whole family.  Found independently from two different CTIs.
logic h3_cti_past_valid_agree;
assign h3_cti_past_valid_agree = (h3_abs_past_valid == h3_commit_past_valid);

// --- L1.2  A CSR write only happens on a specification query ---------------
// hazard3_core.v:1186  wen = d_csr_wen && !m_csr_access_mask
// hazard3_core.v:1146  m_csr_access_mask = m_trap_enter_soon || fd_cir_break_any || x_stall
// hazard3_decode.v:559 d_csr_wen is forced 0 for a starved slot
// With XAdvanceIsNoStall (step 0) this gives wen -> h3_x_advance && !m_trap_enter_soon,
// which is h3_x_progress.  This is the base of the CSR staircase: it serves
// mscratch, mtvec, mie, mepc, mcause and mstatus at once.
// The write enable appears only on the LEFT, which is the direction
// h3_commit.svh:41-48 explicitly sanctions.
logic h3_cti_csr_wen_is_query;
assign h3_cti_csr_wen_is_query = !cpu.core.csr_u.wen || h3_x_progress;

// --- L1.3  A bus request up on an advancing cycle was accepted -------------
// hazard3_core.v:484 puts `bus_aph_req_d && !bus_aph_ready_d` inside x_stall,
// and XAdvanceIsNoStall gives h3_x_advance == !(x_stall || d_starved).
// This is the exact converse of MemAphIsProgress (h3_goals.svh:214), which is
// the only member of this family the harness had, and points the wrong way.
logic h3_cti_aph_req_accepted;
assign h3_cti_aph_req_accepted = !h3_x_advance || !h3_mem_aph_req || h3_mem_aph_rdy;

// --- L1.4  The decompressor passes 32-bit instructions through unchanged ---
// fd_cir and fd_cir_raw are separate wires (hazard3_core.v:125-126, ports
// :196-197) and NOTHING in the harness relates them, so induction may start
// from a state where the expanded and raw forms disagree.  Every CTI does
// exactly that: h3_x_instr (from fd_cir_raw) decodes to one instruction while
// d_rs1/d_rs2 (from fd_cir) name registers belonging to another.
logic h3_cti_cir_raw_passthrough;
assign h3_cti_cir_raw_passthrough =
    (cpu.core.fd_cir_raw[1:0] != 2'b11) ||
    (cpu.core.fd_cir == cpu.core.fd_cir_raw);

// --- L1.5  The registered DUT mtvec also has its reserved bit clear --------
// pre_mtvec (h3_abs.svh:103) splices a literal 1'b0 into bit 1, and
// h3_past_pre_mtvec <= pre_mtvec unconditionally (h3_abs.svh:459).  The CTI
// holds h3_past_pre_mtvec = 0x7fffffff, a past CSR state that never existed.
logic h3_cti_past_pre_mtvec_reserved_zero;
assign h3_cti_past_pre_mtvec_reserved_zero =
    !h3_abs_past_valid || (h3_past_pre_mtvec[1] == 1'b0);

// --- L1.6  A known ghost register implies a live ghost ---------------------
// h3_follower.svh:424-465: every path that clears h3_has_ghost clears the mask
// on the same evaluation (:425, :443-446, :462-464), and the mask is set only
// at :441 inside the h3_spec_en branch.  Harness well-formedness only.
logic h3_cti_has_reg_implies_has_ghost;
assign h3_cti_has_reg_implies_has_ghost = !(|h3_ghost_has_reg) || h3_has_ghost;

// --- L1.7  The specification's mtvec never sets the reserved bit ----------
// h3_top.sv drives .mtvec_i(pre_mtvec), whose bit 1 is the literal 1'b0 above.
// riscv_sys_regs.sail:468 legalizes a write as (v & wmask) | (o.bits & ~wmask)
// with sys_tvec_wmask() = 32'hfffffffd (spec/stub.sv:92), so bit 1 of the
// output is bit 1 of the input.  Spec-side twin of MtvecReservedBitHardwired.
// Constrains only the specification's own output -- no DUT term.
logic h3_cti_spec_post_mtvec_reserved_zero;
assign h3_cti_spec_post_mtvec_reserved_zero = (spec_post_mtvec[1] == 1'b0);

// --- L1.8  A follower holding a spec non-answer is a fetch error ----------
// The follower loads only on h3_x_progress (h3_follower.svh:318), which implies
// h3_spec_en; SpecEnUnreachIdex proves spec_en && mode != IFERR -> !int_err,
// and mode == IFERR iff h3_x_fetch_err (:172-176), latched at :326.
// The CTI has fol_spec_int_err=1 with fol_fetch_err=0, which lets every other
// h3_fol_spec_* field be arbitrary.
logic h3_cti_fol_int_err_is_fetch_err;
assign h3_cti_fol_int_err_is_fetch_err =
    !h3_fol_valid || !h3_fol_spec_int_err || h3_fol_fetch_err;

// --- L1.9  A decoded memory op on a progressing cycle raises a bus request -
// hazard3_core.v:779-788.  In this configuration every suppressor is dead or
// excluded: x_loadstore_pmp_fail is tied 0 (PMP_REGIONS=0), debug and AMO are
// elaborated away (DEBUG_SUPPORT=0, EXTENSION_A=0), m_trap_enter_soon and
// d_starved are false under h3_x_progress, and x_unaligned_addr always
// co-occurs with x_except != NONE, which the guard carves out.
// DUT-only: says nothing about address, direction or data.
logic h3_cti_memop_raises_aph;
assign h3_cti_memop_raises_aph =
    !h3_x_progress ||
    (cpu.core.d_memop == H3_MEMOP_NONE) ||
    (cpu.core.x_except != H3_EXCEPT_NONE) ||
    h3_mem_aph_req;

// --- L1.10  The follower's rd is the register the spec says it wrote -------
// h3_fol_rd <= cpu.core.d_rd and h3_fol_spec_wX_addr <= spec_post_wX_addr are
// latched from the SAME query on the same cycle (h3_follower.svh:325, :332).
// Compares register NUMBERS only, never a value, so WrapRegA's value equality
// is untouched: a core writing the right register with wrong data still fails.
logic h3_cti_fol_rd_matches_spec_write;
assign h3_cti_fol_rd_matches_spec_write =
    !h3_fol_valid || !h3_fol_spec_real_write || h3_fol_except ||
    (h3_fol_rd == h3_fol_spec_wX_addr);

// ===========================================================================
// Layer 2 -- these depend on a layer-1 fact, so they must sit strictly above.
// ===========================================================================

// --- L2.1  The ghost's mtvec has its reserved bit clear -------------------
// The ghost's only writer is h3_ghost_mtvec = spec_post_mtvec under h3_spec_en
// (h3_follower.svh:453), and h3_has_ghost is raised in the same branch (:428).
// DEPENDS ON L1.7.  This is the exact witness the WrapMtvec CTI uses:
// ghost = 0x0000000f has bit 1 set, and pre_mtvec[1] is hardwired 0, so the
// comparison is unsatisfiable by construction.
logic h3_cti_ghost_mtvec_reserved_zero;
assign h3_cti_ghost_mtvec_reserved_zero =
    !h3_has_ghost || (h3_ghost_mtvec[1] == 1'b0);

// --- L2.2  The ghost's mie has no unimplemented bit set -------------------
// hazard3_csr.v:322 MIE_WMASK = 32'h00000888 (meie, mtie, msie), and Sail's
// legalize_mie (riscv_sys_regs.sail:398-408) writes bits 11/7/3 only, its
// U-mode arm dead because misa = 0x4080_1104 has neither U nor N.  So the
// writable sets agree bit-for-bit and a ghost holding 0xf is unreachable.
// MieReservedZero (h3_abs.svh:665) already proves the DUT half.
// Says nothing about bits 3/7/11, which is where WrapMie's content lives.
logic h3_cti_ghost_mie_reserved_zero;
assign h3_cti_ghost_mie_reserved_zero =
    !h3_has_ghost || ((h3_ghost_mie & ~32'h0000_0888) == 32'h0);

// --- L2.3  A bus request on a progressing cycle reaches address phase ------
// DEPENDS ON L1.3; h3_x_progress -> h3_x_advance.
logic h3_cti_x_progress_aph_accepted;
assign h3_cti_x_progress_aph_accepted =
    !h3_x_progress || !h3_mem_aph_req || h3_mem_aph;

// ===========================================================================
// Layer 3 -- the inductive strengthening the goals actually need.
//
// NOTE ON SOUNDNESS.  This is WrapMscratch with its h3_spec_en guard dropped,
// i.e. STRICTLY STRONGER than the goal.  It is stated as `have`, which is an
// obligation to PROVE, not an assumption.  Proving a strengthened invariant and
// deriving the goal from it is exactly what k-induction strengthening is, and
// it cannot make the proof vacuous: a core whose mscratch disagreed with the
// specification's would fail this first and harder than it fails the goal.
// (One writer declined to propose this on vacuity grounds; that caution applies
// to ASSUMING the conclusion, not to proving a stronger one.)
// ===========================================================================
logic h3_cti_ghost_tracks_mscratch;
assign h3_cti_ghost_tracks_mscratch =
    !h3_has_ghost || (pre_mscratch == h3_ghost_mscratch);
`include "h3_cti_round2.svh"
