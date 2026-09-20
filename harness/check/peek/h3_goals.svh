// ===========================================================================
// check/peek/h3_goals.svh -- THE CORRECTNESS GOALS.  Gate 5 of the bring-up.
//
// `include`d by check/h3_core_common.svh LAST, after h3_commit.svh (the events),
// h3_abs.svh (the pre-state), h3_mem.svh (the bus view) and h3_follower.svh (the
// follower and the ghost), because it uses all four.  Present identically in
// BOTH models -- and unlike everything before it, the properties in this file
// are ONLY statements about Hazard3 on build/all.aig.  On build/core.aig the
// `spec_*` wires are free, so they are satisfiable-but-meaningless there; that
// is the development model, not the claim.
// ===========================================================================
//
// WHAT THIS FILE CLAIMS
// ---------------------------------------------------------------------------
// Everything before this gate was machinery: a commit point, an abstraction, a
// follower, a ghost.  None of it says Hazard3 is correct.  This file does, and
// it does so in the four properties Ibex's dv/formal/README.md identifies as
// sufficient (minus liveness, see below):
//
//   Wrap   At each specification query, the specification's INPUTS equal its own
//          OUTPUTS from the previous query.  In the README's notation this is
//              Spec(abs(a), i) == abs(Hazard3(a, i))
//          and it is the property that turns a per-instruction check into a
//          trace-equivalence argument: by induction over n queries,
//              Spec^n(abs(a0), I) == abs(Hazard3^n(a0, I)).
//
//   Load   The memory READ requests Hazard3 makes are exactly the ones the
//   Store  specification makes, at the same addresses, with the same write data
//          and the same byte lanes.  In the README's notation,
//              SpecOut(abs(a), i) == Hazard3Out(a, i).
//          Note that Load/Store need NO ghost guard: they compare the
//          specification's output against the DUT's output for the SAME
//          architectural state, because the specification is fed that state
//          directly.  It is Wrap that then says the state was right.
//
//   NoMem  An instruction the specification says performs no memory operation
//          causes Hazard3 to issue no data-side bus transfer.
//
// WHAT IT DOES NOT CLAIM, AND THIS IS THE HONEST BIT
// ---------------------------------------------------------------------------
// LIVENESS IS OUT OF SCOPE, BY DECISION (plan section 6).  Ibex's fifth goal,
// `Live`, proves `always (##[0:212] spec_en)` -- that comparison points keep
// happening.  It is commented out by default in Oxford's own flow and only ever
// worked with their memory response bound set to 1, which this harness does not
// have (MAX_BUS_STALL = -1, stalls unbounded).  Without it, the composition in
// the README stops one step short:
//
//   * WITH liveness, the four goals give: for every n, the nth memory operation
//     Hazard3 performs is the nth memory operation the specification performs,
//     i.e. full trace equivalence.
//   * WITHOUT it, they give: for every n, IF Hazard3 performs an nth
//     specification query, then its architectural state and its memory
//     operations up to that point agree with the specification's.  A Hazard3
//     that stopped retiring instructions for ever -- deadlocked in a stall, or
//     starved by a bus that never responds -- would satisfy all four.
//
// So the claim is CONDITIONAL ON INSTRUCTIONS CONTINUING TO RETIRE.  It is
// exactly the caveat Oxford's default flow carries, and it is in BRINGUP.md's
// assumption list rather than being papered over.  What is NOT conditional is
// that the model can reach these states at all: NegNeverRetire, NegNeverIrqTrap
// and NegNeverMemAph are the controls that queries, traps and memory operations
// all happen.
// ===========================================================================

// ===========================================================================
// 1.  SUPPORT
// ===========================================================================

// Ibex's spec_mem_en (check/top.sv:414).  "The specification performs a memory
// operation for this query."
logic h3_spec_mem_en;
assign h3_spec_mem_en = spec_mem_read || spec_mem_write;

// Ibex's fst_mask (check/top.sv:420-424): the specification's byte enables,
// expanded to a 32-bit bitmask, taken from the follower because the write data
// is compared one cycle after the query (see h3_mem.svh's header).
logic [31:0] h3_fol_wmask;
assign h3_fol_wmask = {
    {8{h3_fol_spec_mem_write_be[3]}}, {8{h3_fol_spec_mem_write_be[2]}},
    {8{h3_fol_spec_mem_write_be[1]}}, {8{h3_fol_spec_mem_write_be[0]}}
};

// ===========================================================================
// 2.  GOAL 1 -- Wrap
// ===========================================================================
// Ibex's thm/riscv.proof:168-176, one property per ghosted register plus the two
// register-read lanes.  `in (spec_en) ... have (has_spec_past |-> pre_X ==
// spec_past_X)`, verbatim in shape.
//
// The guard is h3_has_ghost, which is 0 until the first query and dropped again
// whenever the harness cannot interpret a query (an uncheckable CSR access, a
// fetch error, or -- new at this gate -- an instruction that took a data-phase
// bus fault).  Dropping it only ever weakens the claim; NegHasGhostNever is the
// control that it is not dropped always.
//
// THERE IS NO INITIAL-STATE ASSUMPTION HERE, AND NONE IS NEEDED.  The plan
// (section 7) reserved one -- "assume the DUT's and the specification's initial
// register state agree" -- for this gate, because RESET_REGFILE = 0 means
// Hazard3's GPRs have no reset value.  Measured, that assumption is unnecessary
// and would be vacuous, and BRINGUP.md's gate-5 section says why at length: the
// specification instance is STATELESS (sail is built with --sv-inregs
// --sv-outregs, so every architectural register is a port), and check/h3_top.sv
// drives every one of those ports from the abstraction -- from the DUT -- on
// every query.  The specification therefore has no initial state of its own to
// disagree with, and h3_has_ghost / h3_ghost_has_reg starting at zero means
// nothing is compared until the harness has itself watched the specification
// produce a value.  Ibex's harness contains no such assumption either, for the
// same reason, even though its own register file happens to reset to zero.
logic h3_wrap_pc;
logic h3_wrap_mstatus;
logic h3_wrap_mie;
logic h3_wrap_mcause;
logic h3_wrap_mtvec;
logic h3_wrap_mscratch;
logic h3_wrap_mepc;

assign h3_wrap_pc       = !h3_spec_en || !h3_has_ghost || (pre_pc       == h3_ghost_pc);
assign h3_wrap_mstatus  = !h3_spec_en || !h3_has_ghost || (pre_mstatus  == h3_ghost_mstatus);
assign h3_wrap_mie      = !h3_spec_en || !h3_has_ghost || (pre_mie      == h3_ghost_mie);
assign h3_wrap_mcause   = !h3_spec_en || !h3_has_ghost || (pre_mcause   == h3_ghost_mcause);
assign h3_wrap_mtvec    = !h3_spec_en || !h3_has_ghost || (pre_mtvec    == h3_ghost_mtvec);
assign h3_wrap_mscratch = !h3_spec_en || !h3_has_ghost || (pre_mscratch == h3_ghost_mscratch);
assign h3_wrap_mepc     = !h3_spec_en || !h3_has_ghost || (pre_mepc     == h3_ghost_mepc);

// The register file, on the two lanes the instruction actually reads.  Ibex's
// RegA/RegB (thm/riscv.proof:175-176).  Note the guard is h3_ghost_has_reg and
// NOT h3_has_ghost: a register the specification has never written has no ghost
// value to compare against, which with RESET_REGFILE = 0 is the only honest
// statement available -- and it is also exactly Ibex's.
//
// pre_regs, not pre_regs_cut, because pre_regs_cut is declared [1:31] and d_rs1
// can be 0; the `|d_rs1` term is what makes the two the same statement, and x0
// is excluded on both sides (GhostX0Unknown proves the ghost never claims it).
logic h3_wrap_reg_a;
logic h3_wrap_reg_b;

assign h3_wrap_reg_a = !h3_spec_en || !(|cpu.core.d_rs1) ||
    !h3_ghost_has_reg[cpu.core.d_rs1] ||
    (pre_regs[cpu.core.d_rs1] == h3_ghost_regs[cpu.core.d_rs1]);

assign h3_wrap_reg_b = !h3_spec_en || !(|cpu.core.d_rs2) ||
    !h3_ghost_has_reg[cpu.core.d_rs2] ||
    (pre_regs[cpu.core.d_rs2] == h3_ghost_regs[cpu.core.d_rs2]);

// ===========================================================================
// 3.  THE SPECIFICATION MUST BE ABLE TO ANSWER
// ===========================================================================
// Ibex's SpecEnUnreach (thm/ibex.proof:299): `spec_en |-> ~spec_int_err`.  It is
// an ASSERTION, not a guard -- Ibex never masks a property with spec_int_err,
// it proves the specification always has an answer.  Two forms here, because
// this configuration cannot have the strong one:
//
//   SpecEnUnreach      the Ibex-strength statement, over every query.  It is
//                      expected to FAIL, and the reason is the MAIN_IFERR gap
//                      documented in h3_follower.svh: spec/main.sail:68-81
//                      returns MAINRES_NOIFERR whenever the Sail fetch succeeds,
//                      and riscv_mem.sail:168-183's mem_read_i is a PMP and
//                      alignment check that, with an empty PMP and an aligned
//                      PC, always succeeds.  So asking MAIN_IFERR always sets
//                      int_err.  It is stated anyway, because a failing goal
//                      with a known reason is worth more than a goal quietly
//                      weakened until it passes.
//
//   SpecEnUnreachIdex  the same restricted to the instruction-executing and
//                      interrupt queries, which is what this configuration can
//                      actually claim.
logic h3_spec_en_unreach;
assign h3_spec_en_unreach = !h3_spec_en || !spec_int_err;

logic h3_spec_en_unreach_idex;
assign h3_spec_en_unreach_idex =
    !h3_spec_en || (h3_spec_mode == H3_MAIN_IFERR) || !spec_int_err;

// ===========================================================================
// 4.  GOALS 2 and 3 -- Load and Store
// ===========================================================================
// Ibex's thm/riscv.proof:180-194 (the `Mem` block) plus thm/mem.proof's `load`
// and `store` lemmas, collapsed.  Two structural facts do the collapsing, and
// both are proved rather than assumed:
//
//   * MemAphIsProgress -- a data-side address phase is accepted ONLY on a cycle
//     where the instruction that issued it leaves X, i.e. on the query cycle.
//     hdl/hazard3_core.v:484 puts `bus_aph_req_d && !bus_aph_ready_d` inside
//     x_stall, and :779-788 suppresses bus_aph_req_d for every other reason the
//     instruction might not progress.  This is what removes Ibex's separate
//     `FstEnd: spec_en & spec_mem_en |-> mem_gnt_fst_d`.
//   * MemNoSecondGranule -- Hazard3 traps misaligned accesses, so the
//     specification never asks for a second granule.  This is what removes every
//     `Snd*` property, and with them alt_lsu.
logic h3_mem_aph_is_progress;
assign h3_mem_aph_is_progress = !h3_mem_aph || h3_x_progress;

// Ibex `En` (riscv.proof:182), contrapositive.  THIS IS GOAL 4, NoMem: if the
// specification performs no memory operation for this query, Hazard3 issues no
// data-side transfer.
//
// DELIBERATE DEVIATION FROM IBEX, AND WHY.  Ibex states NoMem over a DECODE
// predicate -- ex_is_mem_instr, built in check/peek/compare_helper.sv:23-34 from
// the encodings.sv macros over `CR.instr_rdata_id.  Transcribing that here would
// mean re-implementing RVC decompression in the harness, because the instruction
// Hazard3 hands the specification is the RAW CIR (h3_fol_instr / fd_cir_raw --
// Sail decompresses for itself) and c.lw / c.sw / c.lwsp / c.swsp are memory
// instructions whose 32-bit macros do not match.  Decoding them a second time in
// the harness is exactly the "copy of the design" the plan rejects at every other
// opportunity.  So "non-memory instruction" is adjudicated by the SPECIFICATION,
// which does its own decompression.  The statement is the same and the evidence
// is better.
logic h3_no_mem;
assign h3_no_mem = !h3_mem_aph || h3_spec_mem_en;

// Ibex `We` (riscv.proof:184).  The direction of the transfer is the one the
// specification chose.
logic h3_mem_we_matches;
assign h3_mem_we_matches = !h3_mem_aph ||
    ((h3_mem_write == spec_mem_write) && (h3_mem_write == !spec_mem_read));

// --- Load -------------------------------------------------------------------
// Ibex `load.En` + `load.NoWe` + `load.End.Fst`, in one: the specification says
// this instruction reads memory, so Hazard3 issues a read address phase on this
// very cycle.
logic h3_load_en;
assign h3_load_en = !h3_spec_en || !spec_mem_read || (h3_mem_aph && !h3_mem_write);

// Ibex `load.FstAddr` (mem.proof:147).  Sail aligns the physical address before
// calling read_ram (riscv_mem.sail:96, `let aligned = [paddr with 1..0 = 0b00]`),
// Hazard3 puts the byte address on HADDR and selects the lane with HSIZE, so the
// comparison is against the word address.  h3_mem_be is compared separately.
logic h3_load_addr;
assign h3_load_addr = !h3_mem_aph || h3_mem_write ||
    (spec_mem_read_fst_addr == h3_mem_addr_word);

// --- Store ------------------------------------------------------------------
logic h3_store_en;
assign h3_store_en = !h3_spec_en || !spec_mem_write || (h3_mem_aph && h3_mem_write);

logic h3_store_addr;
assign h3_store_addr = !h3_mem_aph || !h3_mem_write ||
    (spec_mem_write_fst_addr == h3_mem_addr_word);

// STRONGER THAN IBEX.  Ibex never compares data_be_o against the specification
// at all (check/top.sv:420-428 uses the spec's byte enables only to MASK the
// data comparison), so an Ibex that asserted extra byte lanes would not be
// caught by its goals.  AHB5 has no byte-enable signal, so h3_mem_be is
// reconstructed from HSIZE and the low address bits (h3_mem.svh section 1) and
// compared directly.  Kept as its own property so that, if it fails, it does not
// drag StoreWData down with it.
logic h3_store_be;
assign h3_store_be = !h3_mem_aph || !h3_mem_write ||
    (spec_mem_write_fst_be == h3_mem_be);

// Ibex `store.FstWData` (mem.proof:165).  THE ONE COMPARISON THAT IS NOT MADE AT
// THE ADDRESS PHASE: hdl/hazard3_core.v:1435-1441 drives bus_wdata_d from
// xm_memop and m_wdata, i.e. from stage M, one cycle after the address phase.
// So this is made during the data phase against the follower's latched copy of
// what the specification said -- the "latch the write data comparison one cycle"
// of plan section 1.  FollowerOwnsDphase is what says the data phase in flight
// belongs to the instruction the follower is holding.
logic h3_store_wdata;
assign h3_store_wdata = !h3_fol_valid || !h3_fol_spec_mem_write || !h3_mem_dph_active ||
    ((h3_fol_spec_mem_write_wdata & h3_fol_wmask) == (h3_mem_wdata & h3_fol_wmask));

// --- No second granule -------------------------------------------------------
// Gate 4's handoff item 7.  Hazard3 traps misaligned accesses and spec/stub.sv
// now reports sail_plat_enable_misaligned_access = 0, so Sail's checked_mem_read
// and checked_mem_write can never take their `4 - unsigned(paddr[1..0]) < width`
// branch.  If this fails, something about the alignment configuration is wrong
// rather than the core.
logic h3_mem_no_second_granule;
assign h3_mem_no_second_granule =
    !h3_spec_en || (!spec_mem_read_snd && !spec_mem_write_snd);

// ===========================================================================
// 5.  THE MEMORY ASSUMPTION
// ===========================================================================
// Ibex's check/peek/mem.sv:37-39 (LoadMemLateRespFirst).  See h3_mem.svh
// section 3 for the full argument; in one line: h3_spec_rdata is a free input
// the solver picks at the query cycle, and this makes the bus deliver exactly
// that word to the core when the data phase completes, which is a renaming of an
// already-unconstrained free input rather than a restriction of the environment.
//
// IT IS THE ONLY ASSUMPTION GATE 5 ADDS.  C goes 5 -> 6, and check_env.sh will
// say so on both models.  Written in the style of Hazard3's own
// ahbl_slave_assumptions.v -- an immediate assume inside a clocked always with
// an rst_n guard -- because that is the form yosys-slang accepts here (a bare
// `always assume(...)` segfaults it; see BRINGUP.md, gate 1).
//
// The constraint fires only on a cycle where the D-side owns the data phase.
// BusDphMutex (gate 2) proves the I-side does not, so instruction fetches are
// left entirely free even though hrdata is physically shared
// (hdl/hazard3_cpu_1port.v:318-319).
always @ (posedge clk_i) if (rst_ni) begin: h3_mem_data_assumption
    if (h3_fol_valid && h3_fol_spec_mem_read && h3_mem_dph_active && h3_mem_dph_end) begin
        assume (h3_mem_rdata == h3_fol_spec_rdata);
    end
end

// ===========================================================================
// 6.  NON-VACUITY (step 1 of thm/hazard3.proof -- these MUST FAIL)
// ===========================================================================
// EVERY goal above is an implication whose antecedent must be reachable, or the
// goal is true for the wrong reason.  A goal that proves trivially is a red flag,
// so each of the four gets at least one control.

// Wrap: the ghost must be valid at a query, or every Wrap property is 0 -> x.
logic h3_neg_never_wrap_point;
assign h3_neg_never_wrap_point = !(h3_spec_en && h3_has_ghost);

// Wrap's register lanes: an instruction must read a register the ghost knows.
logic h3_neg_never_wrap_reg;
assign h3_neg_never_wrap_reg =
    !(h3_spec_en && (|cpu.core.d_rs1) && h3_ghost_has_reg[cpu.core.d_rs1]);

// Load / Store: the specification must actually ask for each.
logic h3_neg_spec_never_reads;
assign h3_neg_spec_never_reads = !(h3_spec_en && spec_mem_read);

logic h3_neg_spec_never_writes;
assign h3_neg_spec_never_writes = !(h3_spec_en && spec_mem_write);

// StoreWData is guarded three deep; this is the witness for the conjunction.
logic h3_neg_never_store_dphase;
assign h3_neg_never_store_dphase =
    !(h3_fol_valid && h3_fol_spec_mem_write && h3_mem_dph_active);

// NoMem: there must be an instruction that makes NO memory request, or NoMem is
// `!h3_mem_aph` being true because h3_mem_aph is always true.  (The other half,
// "a request is ever made", is NegNeverMemAph in h3_mem.svh.)
logic h3_neg_always_mem_aph;
assign h3_neg_always_mem_aph = !(h3_spec_en && !h3_spec_mem_en);

// The memory assumption must not be vacuous either: if its antecedent were
// unreachable, the specification would never be told anything about memory and
// every load would compare against a free word.
logic h3_neg_never_load_dphase_end;
assign h3_neg_never_load_dphase_end =
    !(h3_fol_valid && h3_fol_spec_mem_read && h3_mem_dph_active && h3_mem_dph_end);
`include "h3_spike.svh"
