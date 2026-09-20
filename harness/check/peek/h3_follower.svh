// ===========================================================================
// check/peek/h3_follower.svh -- THE PIPELINE FOLLOWER AND THE GHOST STATE.
//   Gate 4 of the bring-up.
//
// `include`d by check/h3_core_common.svh, AFTER h3_commit.svh (which defines
// the events) and h3_abs.svh (which defines the pre-state), so it is present
// identically in BOTH models.
// ===========================================================================
//
// WHAT THIS FILE IS FOR
// ---------------------------------------------------------------------------
// Hazard3 does not commit an instruction's architectural effects on a single
// cycle (gate 3): the CSR file and the PC are written when the instruction
// leaves X, the register file and the store data phase when it leaves M.  The
// specification, by contrast, answers in one step.  So the harness has to ask
// the specification its question at ONE cycle (h3_spec_en, the X->M handoff)
// and check the answer at ANOTHER (h3_cmp_en, the M->W crossing).  Something
// has to hold the answer in between.  That something is the follower.
//
// There are two distinct pieces of state here and it is worth being clear
// about which is which, because Ibex has both and they are easy to conflate:
//
//   THE FOLLOWER (h3_fol_*)  -- per instruction.  Loaded when an instruction
//       leaves X, cleared when it retires.  Holds what the SPECIFICATION said
//       that instruction would do, plus enough of what the PIPELINE thinks it
//       is (PC, instruction bits, destination register) to prove the two are
//       tracking the same instruction.  This is Ibex's wbexc_* bundle.
//
//   THE GHOST (h3_ghost_*)   -- architectural, not per instruction.  Updated on
//       EVERY specification query, including the instruction-less interrupt
//       query, and never cleared.  It is the specification's running copy of
//       the architectural state, and it is what design (b) of the abstraction
//       leans on: because the harness never computes a DUT post-state, the only
//       way the specification's answer is ever checked against the DUT is by
//       carrying it forward to the next query and meeting the DUT's own
//       post-state there, as that state's PRE-state.  This is Ibex's
//       spec_past_*, and it is what gate 5's `Wrap` will be stated over.
//
// HOW THIS DIFFERS FROM IBEX'S check/peek/follower.sv
// ---------------------------------------------------------------------------
// 1. IT IS SMALLER, because the commit point is simpler.  Ibex's follower
//    carries ex_has_branched_q, wbexc_csr_pipe_flush, wbexc_is_wfi,
//    wbexc_compressed_illegal and a second-granule memory bundle, all of which
//    exist to paper over Ibex's controller FSM, its CSR pipe flush, and its
//    misaligned-access splitting.  Hazard3 traps misaligned accesses instead of
//    splitting them (so there is no second granule), routes its pipeline flush
//    through the same trap handshake as everything else, and decompresses in
//    the frontend.  None of that machinery ports.
//
// 2. IT CARRIES NO DUT POST-STATE.  Ibex's follower snapshots wbexc_dut_post_*
//    alongside wbexc_post_* because Ibex's abstraction can compute a post-state
//    from the CSR file's _d/_en pairs.  Hazard3's cannot -- that is design (b),
//    settled at gate 2 -- so there is nothing to snapshot.  What replaces it is
//    the observation that Hazard3's CSR file ALREADY holds the retiring
//    instruction's post-state during its retire cycle: a CSR write lands at the
//    X->M handoff, and the next instruction cannot leave X until the one in M
//    retires (h3_x_progress -> !x_stall -> !m_stall), so no younger write can
//    have landed yet.  The comparison gate 5 will make is therefore against
//    pre_*, one query later, not against a snapshot.
//
// 3. ITS OCCUPANCY AND THE PIPELINE'S ARE DERIVED SEPARATELY AND THEN PROVED
//    EQUAL.  h3_m_valid (h3_commit.svh) follows the X/M pipe register's own
//    bubble condition; h3_fol_valid below is set and cleared by the follower's
//    own events, exactly as Ibex sets and clears wbexc_exists.  FollowerMatchesMValid
//    is the obligation that the two agree, which is Ibex's ValidExists.
//
// 4. THE INTERRUPT QUERY CAN COINCIDE WITH A RETIREMENT.  Ibex proves
//    NoFinishingIRQ (wbexc_exists |-> ~wbexc_handling_irq): its IRQ_TAKEN state
//    is a cycle with nothing in WB.  In Hazard3 that lemma is FALSE, and
//    deliberately so -- hdl/hazard3_core.v:1504-1507, "Interrupt entry does not
//    prevent writeback, because the interrupt is notionally inserted in between
//    the instruction in M and the instruction in X."  Gate 3's
//    NegRetireTrapExclusive is the measurement.  So the ghost can be updated by
//    an interrupt query on the same cycle the follower is cleared by a
//    retirement, and GhostMatchesFollower* below has to survive that.  It does,
//    because both are registers: on the coincident cycle the ghost still holds
//    the pre-interrupt value, and on the next cycle the follower is empty.
//
// WHAT IS DELIBERATELY NOT DONE HERE
// ---------------------------------------------------------------------------
// The register file is NOT snapshotted.  Its write port (h3_reg_write / xm_rd /
// m_result) is compared live at h3_retire, which is where Ibex compares it too
// (check/peek/compare_helper.sv:38-43).  Snapshotting it would mean predicting
// the write, which means modelling the bypass network, which
// hazard3_rvfi_monitor.vh:223-224 warns against in the author's own words.
// ===========================================================================

// ---------------------------------------------------------------------------
// 0.  Constants
// ---------------------------------------------------------------------------
localparam [4:0] H3_MEMOP_NONE          = 5'h10;  // hazard3_ops.vh:78
localparam [3:0] H3_EXCEPT_INSTR_FAULT  = 4'h1;   // hazard3_ops.vh:98

// The three modes of spec/main.sail's `main`.  Encoded as plain bits here
// because t_MainMode is a Sail type and only exists in build/all.aig;
// check/h3_top.sv converts.  Order matches the enum in spec/main.sail:37.
localparam [1:0] H3_MAIN_IDEX  = 2'd0;
localparam [1:0] H3_MAIN_IFERR = 2'd1;
localparam [1:0] H3_MAIN_IRQ   = 2'd2;

// ===========================================================================
// 1.  THE SPECIFICATION INTERFACE
// ===========================================================================
// These wires are the boundary between the harness and the Sail model.
//
//   in build/all.aig  they are DRIVEN by the spec_api instance in check/h3_top.sv;
//   in build/core.aig they are UNDRIVEN, so `setundef -undriven -anyseq` makes
//                     them free inputs.
//
// That is deliberate, and it is what lets the identical property set be built
// into both models (which `make check-env` requires: same B, same C, same L).
// A follower-integrity property does not mention them and means exactly the
// same thing in both models; a property that does mention them is being
// developed against a free specification on core.aig and only becomes a real
// statement on all.aig.  Which properties are which is recorded in
// thm/hazard3.proof.
//
// NOTE ON NAMING: these are the only harness signals that deliberately do NOT
// carry the `h3_` prefix.  check_env.sh's signal comparison keys on that prefix
// (plus `cpu.` and the bus wires), so the prefix is what says "this signal is
// part of the core's environment and must be identical in both models".  These
// are not: they are the specification's outputs, driven in one model and free
// in the other, and giving them the prefix would make check-env fail for a
// reason that has nothing to do with the core.  Everything downstream of them
// -- the follower and the ghost -- IS prefixed, is latched, and is identical.

logic        spec_int_err;            // the specification could not execute this

logic        spec_post_wX_en;
logic [4:0]  spec_post_wX_addr;
logic [31:0] spec_post_wX;

logic [31:0] spec_post_pc;            // nextPC_out
logic [31:0] spec_post_mstatus;       // packed as pre_mstatus is
logic [31:0] spec_post_mie;
logic [31:0] spec_post_mcause;
logic [31:0] spec_post_mtvec;
logic [31:0] spec_post_mscratch;
logic [31:0] spec_post_mepc;

logic        spec_mem_read;
logic        spec_mem_read_snd;
logic [31:0] spec_mem_read_fst_addr;
logic [31:0] spec_mem_read_snd_addr;

logic        spec_mem_write;
logic        spec_mem_write_snd;
logic [31:0] spec_mem_write_fst_addr;
logic [31:0] spec_mem_write_snd_addr;
logic [31:0] spec_mem_write_fst_wdata;
logic [3:0]  spec_mem_write_fst_be;

// ===========================================================================
// 2.  WHAT THE SPECIFICATION IS ASKED, AND WHEN
// ===========================================================================
// h3_spec_en / h3_cmp_en are defined in check/peek/h3_commit.svh:
//
//   h3_spec_en = h3_x_progress || (h3_trap_entry && h3_trap_is_irq)
//   h3_cmp_en  = h3_retire
//
// Three modes, for the three architectural reasons gate 3 identified:
//   * an instruction advances -- the specification executes it, and an
//     EXCEPTION, if any, is produced by that same execution (which is why
//     exception trap entry is NOT a separate query: ExceptionTrapRetires);
//   * an interrupt is taken -- nothing retires architecturally on the
//     interrupt's own account, so it needs its own, instruction-less query;
//   * the instruction in X carries a fetch fault -- the specification is told
//     to take the fetch error rather than execute the bits.
logic h3_x_fetch_err;
assign h3_x_fetch_err = cpu.core.decode_u.d_except_instr_bus_fault;

logic [1:0] h3_spec_mode;
assign h3_spec_mode =
    (h3_trap_entry && h3_trap_is_irq) ? H3_MAIN_IRQ  :
    h3_x_fetch_err                    ? H3_MAIN_IFERR:
                                        H3_MAIN_IDEX;

// The instruction bits handed to the specification.  spec/main.sail:41-47 takes
// a 32-bit word, decides RVC from bits [1:0], and uses the upper half only for
// a 32-bit instruction -- so the raw CIR is exactly the right thing and no
// decompression is needed on this side (Sail has its own).
//
// fd_cir_raw, NOT fd_cir: hdl/hazard3_frontend.v:51 documents cir_raw as
// "Unexpanded instruction data" while `cir` is the post-decompression form
// (:844-885).  Handing the expanded form to a specification that decompresses
// for itself would compare Hazard3's decompressor against nothing.
//
// The upper half is masked off for a compressed instruction, matching
// hazard3_rvfi_monitor.vh:58 exactly, which is what makes
// FollowerInstrMatchesMonitor a same-value equality.
logic [31:0] h3_x_instr;
assign h3_x_instr = {
    cpu.core.fd_cir_raw[31:16] & {16{cpu.core.df_cir_use[1]}},
    cpu.core.fd_cir_raw[15:0]
};

// ===========================================================================
// 3.  THE FOLLOWER
// ===========================================================================
logic        h3_fol_valid;       // an instruction is in flight in M

// --- what the PIPELINE says about it (for the integrity obligations) --------
logic [31:0] h3_fol_pc;          // its architectural PC
logic [31:0] h3_fol_nextpc;      // the sequentially-next PC at query time
logic [31:0] h3_fol_instr;       // its instruction bits, as handed to the spec
logic [4:0]  h3_fol_rd;          // its destination register
logic        h3_fol_x_except;    // it left X already carrying an exception
logic        h3_fol_fetch_err;   // it left X carrying a fetch fault
logic [1:0]  h3_fol_mode;        // which question the specification was asked

// GATE 5.  h3_fol_x_except above is a SNAPSHOT taken at the X->M handoff, and
// gate 4 measured (NegFollowerExceptExact, at BMC depth 6) that a snapshot is
// not enough: an instruction can leave X with x_except == EXCEPT_NONE and
// acquire an exception LATER, in M, from a data-phase bus fault.  h3_fol_except
// is the EXACT record -- the snapshot, plus the exception the instruction picks
// up while the follower is holding it.  See section 3b below.
logic        h3_fol_except;

// --- what the SPECIFICATION said it would do --------------------------------
logic        h3_fol_spec_int_err;
logic        h3_fol_spec_wX_en;
logic [4:0]  h3_fol_spec_wX_addr;
logic [31:0] h3_fol_spec_wX;

logic [31:0] h3_fol_spec_post_pc;
logic [31:0] h3_fol_spec_post_mstatus;
logic [31:0] h3_fol_spec_post_mie;
logic [31:0] h3_fol_spec_post_mcause;
logic [31:0] h3_fol_spec_post_mtvec;
logic [31:0] h3_fol_spec_post_mscratch;
logic [31:0] h3_fol_spec_post_mepc;

logic        h3_fol_spec_mem_read;
logic        h3_fol_spec_mem_write;
logic [31:0] h3_fol_spec_mem_read_addr;
logic [31:0] h3_fol_spec_mem_write_addr;
logic [31:0] h3_fol_spec_mem_write_wdata;
logic [3:0]  h3_fol_spec_mem_write_be;
logic        h3_fol_spec_mem_snd;   // the spec wanted a second granule

// GATE 5.  The word the specification was TOLD the memory returned.  It is a
// free wire at query time (check/peek/h3_mem.svh, section 3) and this is the
// latched copy the bus is then constrained to deliver, one or more cycles later,
// when the data phase completes.  Ibex's wbexc_spec_mem_read_fst_rdata.
logic [31:0] h3_fol_spec_rdata;

initial begin
    h3_fol_valid                = 1'b0;
    h3_fol_pc                   = 32'h0;
    h3_fol_nextpc               = 32'h0;
    h3_fol_instr                = 32'h0;
    h3_fol_rd                   = 5'h0;
    h3_fol_x_except             = 1'b0;
    h3_fol_except               = 1'b0;
    h3_fol_fetch_err            = 1'b0;
    h3_fol_mode                 = H3_MAIN_IDEX;
    h3_fol_spec_rdata           = 32'h0;
    h3_fol_spec_int_err         = 1'b0;
    h3_fol_spec_wX_en           = 1'b0;
    h3_fol_spec_wX_addr         = 5'h0;
    h3_fol_spec_wX              = 32'h0;
    h3_fol_spec_post_pc         = 32'h0;
    h3_fol_spec_post_mstatus    = 32'h0;
    h3_fol_spec_post_mie        = 32'h0;
    h3_fol_spec_post_mcause     = 32'h0;
    h3_fol_spec_post_mtvec      = 32'h0;
    h3_fol_spec_post_mscratch   = 32'h0;
    h3_fol_spec_post_mepc       = 32'h0;
    h3_fol_spec_mem_read        = 1'b0;
    h3_fol_spec_mem_write       = 1'b0;
    h3_fol_spec_mem_read_addr   = 32'h0;
    h3_fol_spec_mem_write_addr  = 32'h0;
    h3_fol_spec_mem_write_wdata = 32'h0;
    h3_fol_spec_mem_write_be    = 4'h0;
    h3_fol_spec_mem_snd         = 1'b0;
end

// The two events, in Ibex's order (check/peek/follower.sv:116-142): clear on
// finish, then load on progress, so that a cycle which is both -- the common
// case in a full pipeline, since h3_x_progress -> !m_stall -> the M instruction
// retires -- ends up loaded, not empty.
//
// NOTE the load condition is h3_x_progress and NOT h3_spec_en.  An interrupt
// query is instruction-less: it updates the ghost but must not put anything
// into the follower, and it cannot, because h3_x_progress is false on a trap
// handshake cycle (m_trap_enter_soon kills it).  This is the one place where
// Hazard3's "the interrupt query may coincide with a retirement" differs
// visibly from Ibex's "the IRQ cycle is empty".
always @ (posedge clk_i) begin
    if (!rst_ni) begin
        h3_fol_valid  <= 1'b0;
        h3_fol_except <= 1'b0;
    end else begin
        if (h3_cmp_en) begin
            h3_fol_valid <= 1'b0;
        end
        // GATE 5, AND THE POINT OF THE WHOLE MEMORY PEEK.  The exception record
        // is updated LATE as well as at load time.  hdl/hazard3_core.v:1289-1296:
        //
        //     end else if (bus_dph_err_d) begin
        //         // First phase of 2-phase AHB5 error response. ...
        //         xm_except <= ... EXCEPT_LOAD_FAULT : EXCEPT_STORE_FAULT;
        //
        // -- an instruction that left X clean acquires an exception while it is
        // sitting in M, on the first phase of the two-phase AHB5 error response.
        // This is Hazard3's analogue of Ibex's wbexc_err.
        //
        // NOTE WHAT IS *NOT* WRITTEN HERE.  The condition is the follower's own
        // (it is holding an instruction, and the bus reported a D-side error),
        // NOT a copy of the RTL's `!m_stall ? ... : bus_dph_err_d` structure.
        // Copying the RTL would make FollowerExceptExact tautological -- the
        // trap gate 2 flagged for CSR write enables, in a different dress.  The
        // harness says "a fault landed on my instruction"; the obligation is
        // that this coincides with the pipe register's own state.
        if (h3_fol_valid && h3_mem_fault) begin
            h3_fol_except <= 1'b1;
        end
        if (h3_x_progress) begin
            h3_fol_except               <= cpu.core.x_except != H3_EXCEPT_NONE;
            h3_fol_valid                <= 1'b1;

            h3_fol_pc                   <= pre_pc;
            h3_fol_nextpc               <= pre_nextpc;
            h3_fol_instr                <= h3_x_instr;
            h3_fol_rd                   <= cpu.core.d_rd;
            h3_fol_x_except             <= cpu.core.x_except != H3_EXCEPT_NONE;
            h3_fol_fetch_err            <= h3_x_fetch_err;
            h3_fol_mode                 <= h3_spec_mode;

            h3_fol_spec_int_err         <= spec_int_err;
            h3_fol_spec_wX_en           <= spec_post_wX_en;
            h3_fol_spec_wX_addr         <= spec_post_wX_addr;
            h3_fol_spec_wX              <= spec_post_wX;

            h3_fol_spec_post_pc         <= spec_post_pc;
            h3_fol_spec_post_mstatus    <= spec_post_mstatus;
            h3_fol_spec_post_mie        <= spec_post_mie;
            h3_fol_spec_post_mcause     <= spec_post_mcause;
            h3_fol_spec_post_mtvec      <= spec_post_mtvec;
            h3_fol_spec_post_mscratch   <= spec_post_mscratch;
            h3_fol_spec_post_mepc       <= spec_post_mepc;

            h3_fol_spec_mem_read        <= spec_mem_read;
            h3_fol_spec_mem_write       <= spec_mem_write;
            h3_fol_spec_mem_read_addr   <= spec_mem_read_fst_addr;
            h3_fol_spec_mem_write_addr  <= spec_mem_write_fst_addr;
            h3_fol_spec_mem_write_wdata <= spec_mem_write_fst_wdata;
            h3_fol_spec_mem_write_be    <= spec_mem_write_fst_be;
            h3_fol_spec_mem_snd         <= spec_mem_read_snd || spec_mem_write_snd;

            // GATE 5.  The free word the specification was told the memory
            // returned (check/peek/h3_mem.svh section 3).  MemRdataIsSpecData
            // then makes the bus deliver it.
            h3_fol_spec_rdata           <= h3_spec_rdata;
        end
    end
end

// ===========================================================================
// 4.  THE GHOST
// ===========================================================================
// Ibex's spec_past_*, check/peek/follower.sv:160-179, including its use of
// BLOCKING assignments so that the "clear everything" case can undo the
// register write in the same evaluation.
//
// h3_has_ghost is Ibex's has_spec_past: 0 until the first query, and dropped
// again whenever a query is made for an instruction whose CSR access the
// harness cannot check (h3_x_query_checkable, defined in h3_abs.svh).  Dropping
// it only weakens what gate 5 can conclude; NegHasGhostNever is the control
// that it is not dropped always.
logic        h3_has_ghost;
logic [31:0] h3_ghost_pc;
logic [31:0] h3_ghost_mstatus;
logic [31:0] h3_ghost_mie;
logic [31:0] h3_ghost_mcause;
logic [31:0] h3_ghost_mtvec;
logic [31:0] h3_ghost_mscratch;
logic [31:0] h3_ghost_mepc;

// The specification's running copy of the register file.  Only registers the
// specification has actually written have a value, which is what
// h3_ghost_has_reg records -- with RESET_REGFILE = 0 there is no start value to
// compare against, so "has been written since the trace began" is the only
// honest guard, and it is also exactly Ibex's (spec_past_has_reg).
logic [31:0] h3_ghost_regs [32];
logic [31:0] h3_ghost_has_reg;

initial begin
    h3_has_ghost      = 1'b0;
    h3_ghost_pc       = 32'h0;
    h3_ghost_mstatus  = 32'h0;
    h3_ghost_mie      = 32'h0;
    h3_ghost_mcause   = 32'h0;
    h3_ghost_mtvec    = 32'h0;
    h3_ghost_mscratch = 32'h0;
    h3_ghost_mepc     = 32'h0;
    h3_ghost_has_reg  = 32'h0;
end

// GATE 5.  "This query leaves the ghost trustworthy" now has a SECOND term.
//
// h3_x_query_checkable (h3_abs.svh) covers the CSR side: an access to an address
// where Hazard3 and Sail disagree about legality.  The fetch-error side is new,
// and it is the "MAIN_IFERR one level up" gap gate 4 named:
//
//   the Sail fetch is spec/main.sail:30-34's altFetch, which calls
//   mem_read_i(Execute(), PC, size).  riscv_mem.sail:168-183 shows mem_read_i is
//   a PMP AND ALIGNMENT CHECK ONLY -- it never touches read_ram, so it has no
//   channel through which a bus error could be reported.  With an empty PMP and
//   an aligned PC it always returns MemValue(()), so MAIN_IFERR always yields
//   MAINRES_NOIFERR and hence spec_int_err.  The specification in this
//   configuration simply CANNOT express an instruction-fetch bus fault.
//
// So a fetch-error query is not comparable, and the honest thing is to drop the
// ghost for it rather than to assume fetch errors away.  That costs coverage
// (Ibex checks FetchErr; we do not) and costs no soundness, and it adds no
// assumption -- NegNeverIferrQuery still fails, i.e. fetch errors still happen
// in the model and the AHB master contract is still checked across them.
logic h3_query_specifiable;
assign h3_query_specifiable = h3_x_query_checkable && !h3_x_fetch_err;

always @ (posedge clk_i) begin
    if (!rst_ni) begin
        h3_has_ghost     = 1'b0;
        h3_ghost_has_reg = 32'h0;
    end else begin
      if (h3_spec_en) begin
        h3_has_ghost = h3_query_specifiable;

        // A write to x0 is recorded for NOBODY.  Sail's wX to register 0 is a
        // no-op and Hazard3's m_reg_wen is gated on |xm_rd
        // (hdl/hazard3_core.v:1510), so both sides agree that x0 is hardwired
        // zero -- but spec_post_wX_en can still assert with address 0, and
        // letting that set h3_ghost_has_reg[0] would make the ghost claim to
        // know a value for a register that has none.  Ibex applies the same
        // filter one stage later, at comparison time
        // (check/peek/compare_helper.sv:40-41, `spec_real_write`); applying it
        // here keeps the ghost itself well-formed, which GhostX0Unknown proves.
        if (spec_post_wX_en && |spec_post_wX_addr) begin
            h3_ghost_regs[spec_post_wX_addr]    = spec_post_wX;
            h3_ghost_has_reg[spec_post_wX_addr] = 1'b1;
        end
        if (!h3_query_specifiable) begin
            // We no longer know what has been written to anything.  Could be
            // stricter; there is little point (Ibex's comment, and it holds).
            h3_ghost_has_reg = 32'h0;
        end

        h3_ghost_pc       = spec_post_pc;
        h3_ghost_mstatus  = spec_post_mstatus;
        h3_ghost_mie      = spec_post_mie;
        h3_ghost_mcause   = spec_post_mcause;
        h3_ghost_mtvec    = spec_post_mtvec;
        h3_ghost_mscratch = spec_post_mscratch;
        h3_ghost_mepc     = spec_post_mepc;
      end
      // GATE 5, THE DATA-SIDE HALF OF THE SAME GAP -- see the note below.  This
      // sits AFTER the query block, and uses blocking assignments like it, so
      // that a fault coinciding with a query clears the ghost the query had just
      // set rather than the other way round.
      if (h3_fol_valid && h3_mem_fault) begin
        h3_has_ghost     = 1'b0;
        h3_ghost_has_reg = 32'h0;
      end
    end
end

// GATE 5, THE DATA-SIDE HALF OF THE SAME GAP.  A data-phase bus fault is
// discovered AFTER the specification has answered, so unlike the fetch-error
// case it cannot be handled at query time.  It is handled here instead: the
// ghost is dropped on the cycle the fault lands.
//
// WHY THIS AND NOT AN ASSUMPTION.  Ibex's proof hole #2 is "bus errors are
// assumed not to occur" -- check/protocol/mem.sv:38, `NoErr: assume property
// (~err_i)`, with the comment "Sail does not specify what happens on bus
// errors."  That is exactly right about Sail: riscv_mem.sail's read_ram /
// write_ram (which --sv-fun2wires turns into spec_api's mem_read_*_rdata_i /
// mem_write_* ports) carry DATA and no error, and the MemException arms of
// phys_mem_read_word_aligned are reachable only from read_kind_of_flags, i.e.
// from illegal aq/rl/res combinations, never from a bus response.  So there is
// no wire on which to tell the specification, and no amount of harness work
// changes that without editing the specification itself.
//
// But "assume it away" and "do not compare across it" are different statements,
// and the second is strictly weaker.  Dropping the ghost keeps bus faults
// REACHABLE: the core still takes them, the AHB5 master contract is still proved
// across them, FollowerExceptExact still has to be exactly right about them, and
// NegNeverMemFault is the control that they still happen.  What is given up is
// only the architectural comparison for the one instruction that faulted and the
// trap it causes -- which is precisely the part the specification cannot express.
// No AIGER constraint is added: C is unchanged by this block.
//
// It is the last statement of the ghost's own always block above, not a second
// block, so that there is one driver and the ordering is explicit.

// ===========================================================================
// 5.  OBLIGATIONS -- "is the follower following?"
// ===========================================================================
// These are the properties that make everything gate 5 builds on top
// non-vacuous.  A follower that is never occupied, or that is occupied while
// the pipeline is empty, or that holds a different instruction from the one in
// M, makes every correctness goal true for the wrong reason.

// --- 5a. Occupancy ----------------------------------------------------------
// The follower is occupied exactly when the pipeline is.  h3_m_valid is derived
// from the X/M pipe register's own bubble condition (h3_commit.svh); h3_fol_valid
// is set and cleared by the follower's own events.  They are different
// formulations and this is the obligation that they agree -- Ibex's ValidExists.
logic h3_follower_matches_m_valid;
assign h3_follower_matches_m_valid = h3_fol_valid == h3_m_valid;

// NOTHING IS FOLLOWED FOR A BUBBLE.  When the follower is empty, the X/M pipe
// register really is holding the bubble pattern hdl/hazard3_core.v:1281-1288
// writes: no destination register, no memory operation, no exception.  This is
// the converse of gate 3's reason for needing h3_m_valid at all (those three
// values are legitimately reachable by a REAL instruction, so they cannot
// define occupancy -- but they are forced when it is absent).
logic h3_follower_empty_is_bubble;
assign h3_follower_empty_is_bubble = h3_fol_valid || (
    cpu.core.xm_rd     == 5'h0             &&
    cpu.core.xm_memop  == H3_MEMOP_NONE    &&
    cpu.core.xm_except == H3_EXCEPT_NONE
);

// --- 5b. It is following the RIGHT instruction ------------------------------
// hazard3_rvfi_monitor.vh keeps its own copies of the M-stage instruction's PC
// (rvfm_xm_pc, :171-186) and bits (rvfm_m_instr, :58).  They are loaded on
// `!x_stall`, ours on h3_x_progress, and they are written by the core's author
// for a different purpose -- so an equality between them and the follower is a
// real cross-check of the load condition, not a restatement.
logic h3_follower_pc_matches_monitor;
assign h3_follower_pc_matches_monitor =
    !h3_fol_valid || (h3_fol_pc == cpu.core.rvfm_xm_pc);

logic h3_follower_instr_matches_monitor;
assign h3_follower_instr_matches_monitor =
    !h3_fol_valid || (h3_fol_instr == cpu.core.rvfm_m_instr);

// The destination register the follower recorded is the one the pipe register
// is carrying.  This one is against the CORE, not the monitor: xm_rd is what
// actually drives the register file's write address (hdl/hazard3_core.v:1577).
logic h3_follower_rd_matches_pipe;
assign h3_follower_rd_matches_pipe =
    !h3_fol_valid || (h3_fol_rd == cpu.core.xm_rd);

// The PC the follower recorded is the one the trap machinery will return to.
// hdl/hazard3_core.v:1400-1404: an exception's mepc is d_pc walked back over
// the M instruction, so for the M instruction's own exception it must be the M
// instruction's PC.  Stated as the weaker, decidable form: on an exception trap
// (which always coincides with the M instruction's retirement --
// ExceptionTrapRetires), the follower's PC is what the frontend is redirecting
// away from.  Gate 5 needs this to compare mepc.
logic h3_follower_pc_is_exception_return;
assign h3_follower_pc_is_exception_return =
    !(h3_trap_entry && !h3_trap_is_irq) || !h3_fol_valid ||
    (cpu.core.m_exception_return_addr == h3_fol_pc);

// An interrupt's return address is the X instruction's PC, NOT the follower's.
// The other half of the same RTL comment, and the reason the interrupt needs
// its own query with the live pre-state rather than the follower's snapshot.
logic h3_irq_return_is_pre_pc;
assign h3_irq_return_is_pre_pc =
    !(h3_trap_entry && h3_trap_is_irq) ||
    (cpu.core.m_exception_return_addr == pre_pc);

// --- 5c. Exceptions ---------------------------------------------------------
// If the follower recorded that the instruction left X carrying an exception,
// the pipe register still says so.
logic h3_follower_except_implies_pipe;
assign h3_follower_except_implies_pipe =
    !h3_fol_valid || !h3_fol_x_except || (cpu.core.xm_except != H3_EXCEPT_NONE);

// A fetch fault recorded by the follower is an EXCEPT_INSTR_FAULT in the pipe.
logic h3_follower_fetch_err_is_instr_fault;
assign h3_follower_fetch_err_is_instr_fault =
    !h3_fol_valid || !h3_fol_fetch_err ||
    (cpu.core.xm_except == H3_EXCEPT_INSTR_FAULT);

// GATE 5 CLOSES THE LATE-EXCEPTION GAP.  At gate 4 this obligation was stated
// over the SNAPSHOT h3_fol_x_except, it was in step 1, and it FAILED at BMC
// depth 6: an instruction can leave X with xm_except == EXCEPT_NONE and acquire
// an exception LATER, in M, from a data-phase bus fault
// (hdl/hazard3_core.v:1289-1296, the first phase of the two-phase AHB5 error
// response).  h3_fol_except (section 3) now tracks that acquisition, so the
// follower's record is EXACT and this belongs in step 0.
//
// The old, snapshot-only form is kept as h3_neg_follower_except_snapshot below
// and must STILL FAIL, which is what says the late term is load-bearing rather
// than decorative: the flip is because the follower got better, not because the
// bus fault became unreachable (NegNeverMemFault is the control for that).
logic h3_follower_except_exact;
assign h3_follower_except_exact =
    !h3_fol_valid ||
    (h3_fol_except == (cpu.core.xm_except != H3_EXCEPT_NONE));

// A data phase in flight belongs to the instruction the follower is holding.
// This is what entitles the memory goals to read h3_fol_spec_mem_* against the
// live bus during the data phase: hdl/hazard3_core.v:1136 makes
// m_dphase_in_flight a function of xm_memop, i.e. of the M-stage pipe register,
// and FollowerMatchesMValid already ties the follower to M-stage occupancy --
// but xm_memop is one of the three fields a BUBBLE also zeroes, so this needs
// saying separately (it is the memory-side twin of FollowerEmptyIsBubble).
logic h3_follower_owns_dphase;
assign h3_follower_owns_dphase = !h3_mem_dph_active || h3_fol_valid;

// Everything the follower holds was recorded from an instruction, never from a
// query with no instruction: the interrupt query cannot load the follower.
logic h3_irq_query_loads_nothing;
assign h3_irq_query_loads_nothing =
    !(h3_trap_entry && h3_trap_is_irq) || !h3_x_progress;

// THE LEMMA THAT REPLACES IBEX'S DUT POST-STATE SNAPSHOT.
//
// The whole of point 2 in this file's header rests on one claim: when an
// instruction retires, the CSR file still holds ITS post-state, because no
// younger instruction can have written a CSR in between.  This is that claim,
// and it is the Hazard3 form of Ibex's
//     instr_will_progress = (~wbexc_exists | wbexc_finishing) & ...
// (check/peek/follower.sv:42) -- in Ibex it is part of the DEFINITION of
// progress, here it is a theorem about the stall logic:
//
//   h3_x_progress -> !x_stall  (XAdvanceIsNoStall)
//   x_stall       -> ... contains m_stall (hdl/hazard3_core.v:1391 feeding :477)
//   so h3_x_progress -> !m_stall, and if M is occupied, h3_retire.
//
// Consequently a CSR write (which needs h3_x_progress: csr_u.wen is masked by
// x_stall and m_trap_enter_soon at :1145-1146) can only land on a cycle where
// the instruction in M is simultaneously retiring.  So during the retire cycle
// itself, pre_* is still the retiring instruction's post-state -- which is what
// gate 5 will compare against, one query later, in place of the snapshot Ibex
// takes.
logic h3_x_progress_empties_m;
assign h3_x_progress_empties_m = !h3_x_progress || !h3_m_valid || h3_retire;

// --- 5d. Ghost carry: the ghost holds the in-flight instruction's answer -----
// Ibex's SpecPastWbexc (thm/ibex.proof:113-118).  While an instruction is in
// flight, the ghost and the follower hold the same specification post-state --
// i.e. no query has happened in between that the follower did not see.  This is
// exactly where Hazard3's coincident interrupt query could have broken things
// (see the header, point 4); it does not, because both sides are registers.
logic h3_ghost_matches_follower_pc;
logic h3_ghost_matches_follower_mstatus;
logic h3_ghost_matches_follower_mie;
logic h3_ghost_matches_follower_mcause;
logic h3_ghost_matches_follower_mtvec;
logic h3_ghost_matches_follower_mscratch;
logic h3_ghost_matches_follower_mepc;

assign h3_ghost_matches_follower_pc =
    !h3_fol_valid || (h3_ghost_pc == h3_fol_spec_post_pc);
assign h3_ghost_matches_follower_mstatus =
    !h3_fol_valid || (h3_ghost_mstatus == h3_fol_spec_post_mstatus);
assign h3_ghost_matches_follower_mie =
    !h3_fol_valid || (h3_ghost_mie == h3_fol_spec_post_mie);
assign h3_ghost_matches_follower_mcause =
    !h3_fol_valid || (h3_ghost_mcause == h3_fol_spec_post_mcause);
assign h3_ghost_matches_follower_mtvec =
    !h3_fol_valid || (h3_ghost_mtvec == h3_fol_spec_post_mtvec);
assign h3_ghost_matches_follower_mscratch =
    !h3_fol_valid || (h3_ghost_mscratch == h3_fol_spec_post_mscratch);
assign h3_ghost_matches_follower_mepc =
    !h3_fol_valid || (h3_ghost_mepc == h3_fol_spec_post_mepc);

// The register-file half of the same statement.  Ibex's SpecPastReg
// (thm/ibex.proof:112).
// "The specification wrote a register that exists."  Ibex's spec_real_write.
logic h3_fol_spec_real_write;
assign h3_fol_spec_real_write = h3_fol_spec_wX_en && |h3_fol_spec_wX_addr;

logic h3_ghost_reg_matches_follower;
assign h3_ghost_reg_matches_follower =
    !h3_fol_valid || !h3_fol_spec_real_write ||
    (h3_ghost_regs[h3_fol_spec_wX_addr] == h3_fol_spec_wX);

// x0 is never claimed to be known.  MEASURED, NOT ASSUMED: without the
// |spec_post_wX_addr filter above this property FAILS at BMC depth 3 on
// build/core.aig, because the free spec_post_wX_addr can be 0 with
// spec_post_wX_en high.  That is what the filter is for, and this is the
// regression that it is still there.
logic h3_ghost_x0_unknown;
assign h3_ghost_x0_unknown = !h3_ghost_has_reg[0];

// ===========================================================================
// 6.  Non-vacuity controls (step 1 of thm/hazard3.proof -- these MUST FAIL)
// ===========================================================================
// Every obligation in section 5 is guarded by h3_fol_valid.  A follower that is
// never occupied makes all of them, and everything gate 5 builds on them,
// vacuously true.  These say the guards are reachable.
logic h3_neg_follower_never_valid;
assign h3_neg_follower_never_valid = !h3_fol_valid;

logic h3_neg_follower_never_excepts;
assign h3_neg_follower_never_excepts = !(h3_fol_valid && h3_fol_x_except);

// GATE 5.  FollowerExceptExact stated over the gate-4 SNAPSHOT instead of the
// exact record.  This is the property that failed at gate 4 and it must STILL
// fail, or the late term added to h3_fol_except is dead machinery and the flip
// of FollowerExceptExact would mean nothing.
logic h3_neg_follower_except_snapshot;
assign h3_neg_follower_except_snapshot =
    !h3_fol_valid ||
    (h3_fol_x_except == (cpu.core.xm_except != H3_EXCEPT_NONE));

logic h3_neg_follower_never_writes_reg;
assign h3_neg_follower_never_writes_reg = !(h3_fol_valid && h3_fol_spec_real_write);

logic h3_neg_has_ghost_never;
assign h3_neg_has_ghost_never = !h3_has_ghost;

logic h3_neg_ghost_reg_never_known;
assign h3_neg_ghost_reg_never_known = !(|h3_ghost_has_reg);

// "This ghost register never takes a non-reset value."  Each must fail, or the
// corresponding ghost is dead weight and every comparison against it is
// trivially satisfied.  No history latches needed: the reset value is zero, so
// reaching a non-zero value is enough to show the ghost is alive.
logic h3_neg_ghost_pc_always_zero;
logic h3_neg_ghost_mstatus_always_zero;
logic h3_neg_ghost_mie_always_zero;
logic h3_neg_ghost_mcause_always_zero;
logic h3_neg_ghost_mtvec_always_zero;
logic h3_neg_ghost_mscratch_always_zero;
logic h3_neg_ghost_mepc_always_zero;

assign h3_neg_ghost_pc_always_zero       = h3_ghost_pc       == 32'h0;
assign h3_neg_ghost_mstatus_always_zero  = h3_ghost_mstatus  == 32'h0;
assign h3_neg_ghost_mie_always_zero      = h3_ghost_mie      == 32'h0;
assign h3_neg_ghost_mcause_always_zero   = h3_ghost_mcause   == 32'h0;
assign h3_neg_ghost_mtvec_always_zero    = h3_ghost_mtvec    == 32'h0;
assign h3_neg_ghost_mscratch_always_zero = h3_ghost_mscratch == 32'h0;
assign h3_neg_ghost_mepc_always_zero     = h3_ghost_mepc     == 32'h0;

// The specification is queried in each of its three modes.  If MAIN_IFERR were
// unreachable, the fetch-error half of the harness would be untested; if
// MAIN_IRQ were, gate 3's whole second commit event would be.
logic h3_neg_never_iferr_query;
assign h3_neg_never_iferr_query = !(h3_spec_en && h3_spec_mode == H3_MAIN_IFERR);

logic h3_neg_never_irq_query;
assign h3_neg_never_irq_query = !(h3_spec_en && h3_spec_mode == H3_MAIN_IRQ);
