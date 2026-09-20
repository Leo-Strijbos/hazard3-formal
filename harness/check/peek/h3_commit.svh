// ===========================================================================
// check/peek/h3_commit.svh -- THE COMMIT POINT.  Gate 3 of the bring-up.
//
// This file answers one question: *when* does the harness compare Hazard3
// against the RISC-V Sail specification?
//
// `include`d by check/h3_core_common.svh, BEFORE check/peek/h3_abs.svh (which
// uses the events defined here), so it is present identically in both models.
// Everything below mentions only signals inside `cpu`, plus the RVFI bundle
// the core itself drives.
// ===========================================================================
//
// THE ANSWER, IN ONE PARAGRAPH
// ---------------------------------------------------------------------------
// Hazard3 does NOT commit an instruction's architectural effects on a single
// cycle.  The CSR file and the architectural PC are written when the
// instruction leaves stage X; the register file is written when it leaves
// stage M, one or more cycles later.  So the commit point is a *per
// instruction* notion realised at two pipeline boundaries, exactly as Ibex's
// is (`instr_will_progress` at ID/EX, `wbexc_finishing` at WB), plus a third,
// instruction-independent event for trap entry.  The three are:
//
//   h3_x_advance   the X->M handoff.   CSR writes and the PC land here.
//                  This is Ibex's `instr_will_progress`: the cycle on which
//                  the specification is queried (`spec_en`).
//   h3_retire      the M->W crossing.  The register file write and the store
//                  data phase land here, and the instruction can no longer be
//                  squashed.  This is Ibex's `wbexc_finishing`: the cycle on
//                  which the comparison is made.  It is also exactly what the
//                  core's author calls retirement.
//   h3_trap_entry  an exception or interrupt commits mepc / mcause /
//                  mstatus.{mie,mpie} and redirects the PC.  This is Ibex's
//                  `wbexc_handling_irq` generalised to exceptions.
//
// h3_retire and h3_trap_entry are NOT mutually exclusive and must not be --
// see "MUTUAL EXCLUSION" below.  Neither subsumes the other (gate 2 proved
// that with NegMepcOnlyTrap / NegMepcOnlyCsr).
//
// WHAT IS DELIBERATELY NOT READ
// ---------------------------------------------------------------------------
// No CSR write-enable (`csr_u.wen`, `wen_m_mode`, `trapreg_update*`) and no
// register-file write port index appear in the *definition* of a commit event.
// Reading the CSR file's own enable would make "the CSR changed at a commit
// point" tautological, which is the trap gate 2 flagged.  The definitions
// below are built from pipeline control -- stall, starve, pipe-register bubble
// and the trap handshake -- and the CSR/regfile write enables appear only on
// the *left* of the coverage obligations, never on the right.

// ---------------------------------------------------------------------------
// 0.  Constants lifted from hdl/hazard3_ops.vh
// ---------------------------------------------------------------------------
localparam [3:0] H3_EXCEPT_NONE    = 4'hf;   // hazard3_ops.vh:95
localparam [3:0] H3_EXCEPT_MRET    = 4'ha;   // hazard3_ops.vh:107
localparam [3:0] H3_EXCEPT_REFETCH = 4'he;   // hazard3_ops.vh:113

// ===========================================================================
// 1.  The X->M handoff
// ===========================================================================
// hdl/hazard3_decode.v:138-144
//     d_starved  = ~|fd_cir_vld || fd_cir_vld[0] && fd_cir_is_32bit;
//     d_stall    = x_stall || d_starved || fd_cir_uop_nonfinal || d_lspair_nonfinal;
//     df_cir_use = d_starved || d_stall ? 2'h0 : fd_cir_is_32bit ? 2'h2 : 2'h1;
//
// so |df_cir_use is literally "the decoder consumed the instruction in the CIR
// this cycle", i.e. an instruction slot leaves stage X.  It is the same signal
// the core uses for its own retired-instruction counter
// (hdl/hazard3_core.v:1134) and the same one hazard3_rvfi_monitor.vh:57 uses to
// fill the M-stage valid flag.
//
// This is where a CSR instruction's write lands: hdl/hazard3_core.v:1186 wires
// csr_u.wen to `d_csr_wen && !m_csr_access_mask`, and :1146 gives
// m_csr_access_mask = m_trap_enter_soon || fd_cir_break_any || x_stall.  It is
// also where the architectural PC advances (hdl/hazard3_decode.v:220-225,
// guarded by `!d_stall && !cir_lock`).
logic h3_x_advance;
assign h3_x_advance = |cpu.core.df_cir_use;

// The trap handshake.  hdl/hazard3_csr.v:66-68 states the contract in words:
// "Once trap_enter_vld && _rdy, mepc_in is copied to mepc, and other trap
// state is set."  hdl/hazard3_core.v:391 wires m_trap_enter_rdy = f_jump_rdy,
// so the handshake completing also means the frontend accepted the redirect.
logic h3_trap_handshake;
assign h3_trap_handshake = cpu.core.m_trap_enter_vld && cpu.core.m_trap_enter_rdy;

// An instruction slot leaves X *and is not squashed*, i.e. a real instruction
// (not a bubble) is loaded into the X/M pipe registers.
//
// DERIVED FROM THE PIPE REGISTER, NOT FROM THE MONITOR.  hdl/hazard3_core.v
// :1264 loads the xm_* registers when !m_stall, and :1280 overwrites them with
// a bubble when
//     x_stall || d_starved || m_trap_enter_soon
// so the negation of that expression is the RTL's own definition of "stage M
// is being given a real instruction".  Two of its three terms are already
// implied by |df_cir_use (d_stall at :140 contains both), which leaves the
// trap term:
logic h3_x_progress;
assign h3_x_progress = h3_x_advance && !cpu.core.m_trap_enter_soon;

// The same thing written the way hazard3_rvfi_monitor.vh:57 writes it.  These
// two must be equal -- XProgressMatchesMonitor -- and the equality is not
// syntactic: it needs |df_cir_use -> (m_trap_enter_soon <-> trap handshake),
// which comes from the two halves of x_stall_on_trap at hdl/hazard3_core.v
// :414-415 killing df_cir_use in every other case.
logic h3_x_progress_monitor_form;
assign h3_x_progress_monitor_form = h3_x_advance && !h3_trap_handshake;

// ===========================================================================
// 2.  Stage M occupancy, and the retire event
// ===========================================================================
// Hazard3 has no xm_valid register: xm_rd, xm_memop and xm_except are all
// zeroed on a bubble (hdl/hazard3_core.v:1282-1288) but all three legitimately
// take those values for a real instruction too (`add x0,..`, a branch, a
// non-excepting op).  So M-stage occupancy has to be followed, exactly as
// Ibex's harness follows it with `wbexc_exists` (check/peek/follower.sv:116-138).
//
// Load condition = the xm_* pipe register's own load condition (!m_stall),
// value = h3_x_progress above.  Note h3_x_progress -> !x_stall -> !m_stall
// (hdl/hazard3_core.v:477 makes x_stall a superset of m_stall), so the "load a
// bubble" case is covered by the same line.
logic h3_m_valid;

initial h3_m_valid = 1'b0;

always @ (posedge clk_i) begin
    if (!rst_ni)
        h3_m_valid <= 1'b0;
    else if (!cpu.core.m_stall)
        h3_m_valid <= h3_x_progress;
end

// THE RETIRE EVENT.  The instruction in M crosses the M/W pipe register.
//
// hazard3_rvfi_monitor.vh:12 -- "We consider instructions to retire as they
// cross the M/W pipe register" -- and :62 builds rvfi_valid from exactly
// `rvfm_m_valid && !m_stall`.  Everything that makes an instruction's effects
// final happens on this cycle:
//
//   * the register file write.  hdl/hazard3_core.v:1509-1510,
//     m_reg_wen = |xm_rd && !m_bus_stall && xm_except == EXCEPT_NONE, and
//     m_stall (:1391) contains m_bus_stall, so h3_retire -> !m_bus_stall.
//   * the store data phase has completed (m_bus_stall is the "dphase still in
//     flight" term).
//   * the instruction can no longer be squashed: the two ways it could be --
//     an X-sourced exception, and a data-phase bus fault turning into
//     xm_except at :1290-1296 -- both hold m_stall high until the trap entry
//     goes through.
logic h3_retire;
assign h3_retire = h3_m_valid && !cpu.core.m_stall;

// ===========================================================================
// 3.  Trap entry, trap exit, and refetch
// ===========================================================================
// The trap handshake carries THREE different things, and the CSR file itself
// separates them at hdl/hazard3_csr.v:180-182:
//
//     trapreg_update       = trap_enter_vld && trap_enter_rdy && !debug_suppresses_trap_update;
//     trapreg_update_enter = trapreg_update && except != EXCEPT_MRET && except != EXCEPT_REFETCH;
//     trapreg_update_exit  = trapreg_update && except == EXCEPT_MRET;
//
// (`except` is the port fed by xm_except, hdl/hazard3_core.v:1217, and
// debug_suppresses_trap_update is constant 0 here -- hdl/hazard3_csr.v:178,
// `DEBUG_SUPPORT && (...)`, with DEBUG_SUPPORT = 0.)
//
// So the harness must make the same three-way split, and the events below are
// that split restated from xm_except.  This is NOT reading a CSR write enable:
// xm_except is a pipeline register holding the decoded exception cause, and
// the classification below is by instruction semantics, not by "did the CSR
// file enable a write".

// ARCHITECTURAL TRAP ENTRY.  mepc <- mepc_in (hdl/hazard3_csr.v:312-313),
// {mcause_irq, mcause_code} <- cause (:368-370), mstatus.mpie <- mstatus.mie
// and mstatus.mie <- 0 (:231-233), and the PC is redirected to
// mtvec | vector_sel (:1464-1468).  Covers both exceptions (xm_except is a
// real cause) and interrupts (xm_except == EXCEPT_NONE and trap_is_irq).
logic h3_trap_entry;
assign h3_trap_entry = h3_trap_handshake &&
    cpu.core.xm_except != H3_EXCEPT_MRET &&
    cpu.core.xm_except != H3_EXCEPT_REFETCH;

// ARCHITECTURAL TRAP EXIT -- MRET.  mstatus.mie <- mstatus.mpie,
// mstatus.mpie <- 1 (hdl/hazard3_csr.v:221-223), PC <- mepc (:1465).  mepc and
// mcause are NOT touched.
//
// DECISION (see BRINGUP.md, gate 3): MRET IS ARCHITECTURAL, BUT IT IS NOT A
// TRAP.  It is an ordinary RV32 instruction (hdl/hazard3_decode.v:517 decodes
// RVOPC_MRET into d_except = EXCEPT_MRET) that Hazard3 routes down the
// exception channel purely to reuse the f_jump_req / trap_enter handshake for
// the PC redirect.  Consequences for the harness:
//   * it RETIRES.  hdl/hazard3_core.v:1127-1134 counts it in x_instr_ret via
//     x_except_counts_as_retire, and hazard3_rvfi_monitor.vh raises rvfi_valid
//     for it (the REFETCH/MRET exclusions at :30-31 are on rvfm_m_take_exception,
//     which feeds rvfi_TRAP, not rvfi_valid).  TrapExitRetires is the proof.
//   * it is NOT a trap-entry commit event: including it would tell the
//     specification to take a trap that the architecture says did not happen,
//     and would let mepc appear to move "for a cause" when it cannot.
logic h3_trap_exit;
assign h3_trap_exit = h3_trap_handshake && cpu.core.xm_except == H3_EXCEPT_MRET;

// REFETCH.  hdl/hazard3_csr.v:181-182 exclude it from BOTH trapreg updates, so
// it writes no CSR at all; hdl/hazard3_csr.v:1462-1466 sends the redirect to
// debug_dpc_rdata, which hdl/hazard3_decode.v:186 aliases to the architectural
// pc itself ("we're relying on the aliasing of dpc and pc ... the intent is to
// fetch the sequentially-next instruction again").
//
// DECISION: REFETCH IS PURELY MICROARCHITECTURAL, AND IS NOT A COMMIT EVENT.
// It is the pipeline saying "the CSR write I just retired invalidated the
// instructions I have already fetched, re-fetch them".  The CSR instruction
// that raised it retires normally at its own X->M handoff and its write
// commits; nothing else changes, not even the PC.
//
// In THIS configuration it is also unreachable, twice over, which
// NoRefetchException proves:
//   * hdl/hazard3_csr.v:1275-1281 makes write_is_fetch_ordered a disjunction of
//     four terms all multiplied by PMP_REGIONS > 0 or DEBUG_SUPPORT > 0, and
//     both are 0 here;
//   * hdl/hazard3_decode.v:514, the other producer, is guarded by
//     EXTENSION_ZIFENCEI, which is also 0.
logic h3_refetch;
assign h3_refetch = h3_trap_handshake && cpu.core.xm_except == H3_EXCEPT_REFETCH;

// Is this trap an interrupt rather than an exception?  hdl/hazard3_csr.v:1472,
// which with DEBUG_SUPPORT = 0 reduces to !exception_req_any.
logic h3_trap_is_irq;
assign h3_trap_is_irq = cpu.core.m_trap_is_irq;

// ===========================================================================
// 4.  The commit points, in Ibex's use_curr_dut / use_curr_spec shape
// ===========================================================================
// Gate 4 owns the follower; these are the hooks it will attach to, named after
// their Ibex counterparts so that check/peek/follower.sv reads across.
//
//   h3_spec_en   == Ibex `spec_en`             (check/peek/follower.sv:159)
//   h3_cmp_en    == Ibex `wbexc_finishing`     (check/peek/follower.sv:40)
//   h3_use_curr  == Ibex `use_curr_dut`        (check/peek/compare_helper.sv:56)
//
// Query the specification when an instruction leaves X, or when an interrupt
// is taken (an interrupt has no instruction, so it needs its own query -- this
// is Ibex's `wbexc_handling_irq | instr_will_progress`, verbatim in shape).
logic h3_spec_en;
assign h3_spec_en = h3_x_progress || (h3_trap_entry && h3_trap_is_irq);

// Compare when the instruction's effects are final.
logic h3_cmp_en;
assign h3_cmp_en = h3_retire;

// Use the DUT's *live* architectural state rather than the snapshot taken at
// the X->M handoff, in the cases where the state changes after that handoff:
// a trap entry writes mepc/mcause/mstatus on the retire cycle itself.
logic h3_use_curr_dut;
assign h3_use_curr_dut = h3_trap_entry || h3_trap_exit;

logic h3_use_curr_spec;
assign h3_use_curr_spec = h3_trap_entry && h3_trap_is_irq;

// Every cycle on which some architectural state may legitimately move.
logic h3_commit_any;
assign h3_commit_any = h3_x_advance || h3_trap_entry || h3_trap_exit;

// ===========================================================================
// 5.  Architectural state the coverage obligations watch
// ===========================================================================

// THE REGISTER FILE WRITE PORT.  hdl/hazard3_core.v:1577-1579 wires the
// regfile's waddr/wdata/wen to xm_rd / m_result / m_reg_wen, so m_reg_wen is
// the one and only way the architectural register file can change.  (Ibex's
// harness compares the same thing -- the write port, not the file contents --
// at check/peek/compare_helper.sv:38-43, which is also how it avoids
// reimplementing the bypass network.  hazard3_rvfi_monitor.vh:223-224 gives
// the reason in the author's words: "Do not reimplement internal bypassing
// logic. Danger of implementing it correctly here but incorrectly in core.")
logic h3_reg_write;
assign h3_reg_write = cpu.core.m_reg_wen;

// THE ARCHITECTURAL PC.  hdl/hazard3_decode.v:179-227.  `pc` holds the address
// of the instruction in D/X; d_pc and debug_dpc_rdata are both aliases of it
// (:185-186).  With DEBUG_SUPPORT = 0 the debug_dpc_wen and debug_mode arms are
// dead and with EXTENSION_ZCMP/ZILSD = 0 the uop arm is too, leaving
//     pc <= f_jump_now ? f_jump_target : (!d_stall && !cir_lock) ? pc_seq_next : pc
// i.e. it moves on a redirect or on an X->M handoff, and on nothing else.
logic [31:0] h3_pc;
assign h3_pc = cpu.core.decode_u.pc;

// mcause, as the CSR file stores it (hdl/hazard3_csr.v:354-355).  Gate 4 will
// widen this to the architectural {irq, 27'h0, code} form (:838-840); for the
// coverage obligation the raw five bits are what matters.
logic [4:0] h3_mcause_raw;
assign h3_mcause_raw = {cpu.core.csr_u.mcause_irq, cpu.core.csr_u.mcause_code};

// mstatus.MIE -- the one mstatus bit that all three events write, which makes
// it the sharpest test of the MRET decision.  hdl/hazard3_csr.v:223 (trap
// exit), :233 (trap entry), :240 (CSR write to 0x300).
logic h3_mstatus_mie;
assign h3_mstatus_mie = cpu.core.csr_u.mstatus_mie;

// "The instruction leaving X is a CSR write naming <addr>".  INSTRUCTION
// DECODE, not the CSR file's enable: hdl/hazard3_core.v:1182 wires csr_u.addr
// to fd_cir[31:20] (the I-type immediate of the instruction in the CIR) and
// d_csr_wen is the decoder's "this instruction writes a CSR" bit
// (hdl/hazard3_decode.v:506-511, forced to 0 for an invalid or starved slot at
// :558-565).
localparam [11:0] H3_CSR_MSTATUS = 12'h300;
localparam [11:0] H3_CSR_MCAUSE  = 12'h342;

logic h3_x_csr_wen;
assign h3_x_csr_wen = cpu.core.d_csr_wen;

logic [11:0] h3_x_csr_addr;
assign h3_x_csr_addr = cpu.core.fd_cir[31:20];

logic h3_x_writes_mstatus;
assign h3_x_writes_mstatus = h3_x_csr_wen && (h3_x_csr_addr == H3_CSR_MSTATUS);

logic h3_x_writes_mcause;
assign h3_x_writes_mcause = h3_x_csr_wen && (h3_x_csr_addr == H3_CSR_MCAUSE);

// ===========================================================================
// 6.  One-cycle history
// ===========================================================================
// This flow has no $past in continuous assignments, so history is explicit.
// h3_commit_past_valid is low for the first two cycles, so nothing below is
// ever evaluated across the reset edge.
logic        h3_commit_past_valid;
logic        h3_past_retire;
logic        h3_past_x_advance;
logic        h3_past_trap_handshake;
logic        h3_past_trap_entry;
logic        h3_past_trap_exit;
logic [31:0] h3_past_pc;
logic [4:0]  h3_past_mcause_raw;
logic        h3_past_mstatus_mie;
logic        h3_past_x_advance_writes_mstatus;
logic        h3_past_x_advance_writes_mcause;

initial begin
    h3_commit_past_valid             = 1'b0;
    h3_past_retire                   = 1'b0;
    h3_past_x_advance                = 1'b0;
    h3_past_trap_handshake           = 1'b0;
    h3_past_trap_entry               = 1'b0;
    h3_past_trap_exit                = 1'b0;
    h3_past_pc                       = 32'h0;
    h3_past_mcause_raw               = 5'h0;
    h3_past_mstatus_mie              = 1'b0;
    h3_past_x_advance_writes_mstatus = 1'b0;
    h3_past_x_advance_writes_mcause  = 1'b0;
end

always @ (posedge clk_i) begin
    h3_commit_past_valid             <= rst_ni;
    h3_past_retire                   <= h3_retire;
    h3_past_x_advance                <= h3_x_advance;
    h3_past_trap_handshake           <= h3_trap_handshake;
    h3_past_trap_entry               <= h3_trap_entry;
    h3_past_trap_exit                <= h3_trap_exit;
    h3_past_pc                       <= h3_pc;
    h3_past_mcause_raw               <= h3_mcause_raw;
    h3_past_mstatus_mie              <= h3_mstatus_mie;
    h3_past_x_advance_writes_mstatus <= h3_x_advance && h3_x_writes_mstatus;
    h3_past_x_advance_writes_mcause  <= h3_x_advance && h3_x_writes_mcause;
end

// ===========================================================================
// 7.  Obligations -- "is this definition right?"
// ===========================================================================

// --- 7a. The derivation lemmas ---------------------------------------------

// The uop and load/store-pair terms of d_stall (hdl/hazard3_decode.v:140) are
// dead in this configuration (EXTENSION_ZCMP = EXTENSION_ZILSD =
// EXTENSION_ZCLSD = 0; hdl/hazard3_decode.v:311 ties d_lspair_nonfinal to 0),
// so |df_cir_use collapses to the first two terms of the X/M bubble condition
// at hdl/hazard3_core.v:1280.  If this ever fails, h3_x_progress below is
// missing a term.
logic h3_x_advance_is_no_stall;
assign h3_x_advance_is_no_stall =
    h3_x_advance == !(cpu.core.x_stall || cpu.core.d_starved);

// EXCEPT_REFETCH is unreachable here -- see the h3_refetch comment.  This is
// what makes the REFETCH question moot in practice while leaving the decision
// on record for a configuration where it is not.
logic h3_no_refetch_exception;
assign h3_no_refetch_exception =
    cpu.core.x_except  != H3_EXCEPT_REFETCH &&
    cpu.core.xm_except != H3_EXCEPT_REFETCH;

// Our pipe-register-derived progress condition equals the monitor's.
logic h3_x_progress_matches_monitor;
assign h3_x_progress_matches_monitor =
    h3_x_progress == h3_x_progress_monitor_form;

// --- 7b. Agreement with the core author's monitor --------------------------
// hazard3_rvfi_monitor.vh:54-62:
//     if (!x_stall)      rvfm_m_valid <= |df_cir_use && !(trap_vld && trap_rdy);
//     else if (!m_stall) rvfm_m_valid <= 1'b0;
//     rvfi_valid_r <= rvfm_m_valid && !m_stall;
// so rvfm_m_valid is our h3_m_valid and rvfi_valid is our h3_retire delayed by
// exactly ONE register.  (BRINGUP.md's gate-2 note says "two registers behind
// the handoff", which is the same statement measured from h3_x_advance.)
logic h3_m_valid_agrees_rvfi;
assign h3_m_valid_agrees_rvfi = h3_m_valid == cpu.core.rvfm_m_valid;

logic h3_retire_agrees_rvfi_valid;
assign h3_retire_agrees_rvfi_valid =
    !h3_commit_past_valid || (h3_rvfi_valid == h3_past_retire);

// The exclusions BRINGUP.md warned about are on rvfi_TRAP, not rvfi_valid:
// hazard3_rvfi_monitor.vh:28-32 removes EXCEPT_REFETCH and EXCEPT_MRET from
// rvfm_m_take_exception, which :69 registers into rvfi_trap.  Stated here so
// that the claim is proved rather than asserted in prose: a retiring MRET is
// reported valid and NOT trapped.
logic h3_rvfi_trap_excludes_mret;
assign h3_rvfi_trap_excludes_mret =
    !h3_commit_past_valid || !h3_past_trap_exit || !h3_rvfi_trap;

// --- 7c. Coverage: no architectural change outside a commit event ----------

// THE REGISTER FILE.  Every write to it happens on a retire cycle.  This is
// the obligation that the X->M handoff alone could not discharge, and the
// reason the definition needs two boundaries.
logic h3_reg_write_at_retire;
assign h3_reg_write_at_retire = !h3_reg_write || h3_retire;

// THE PC.  Moves only on an X->M handoff or a trap-machinery redirect.
logic h3_pc_change_has_commit;
assign h3_pc_change_has_commit =
    !h3_commit_past_valid || (h3_pc == h3_past_pc) ||
    h3_past_x_advance || h3_past_trap_handshake;

// The stronger form: REFETCH excluded, so only the two architectural redirect
// events are allowed.  If REFETCH were reachable AND moved the PC this would
// fail while the weaker form held, which is the discriminating test of the
// REFETCH decision.
logic h3_pc_change_has_arch_commit;
assign h3_pc_change_has_arch_commit =
    !h3_commit_past_valid || (h3_pc == h3_past_pc) ||
    h3_past_x_advance || h3_past_trap_entry || h3_past_trap_exit;

// mcause.  Moves only on a trap entry or a retiring CSR write to 0x342.
// NOTE the absence of h3_past_trap_exit: MRET must not touch mcause, so if the
// MRET decision were wrong this would fail.
logic h3_mcause_change_has_cause;
assign h3_mcause_change_has_cause =
    !h3_commit_past_valid || (h3_mcause_raw == h3_past_mcause_raw) ||
    h3_past_trap_entry || h3_past_x_advance_writes_mcause;

// mstatus.MIE.  The one bit all three architectural events write, so all three
// terms have to be here -- and that is the positive half of the MRET decision.
logic h3_mstatus_mie_change_has_cause;
assign h3_mstatus_mie_change_has_cause =
    !h3_commit_past_valid || (h3_mstatus_mie == h3_past_mstatus_mie) ||
    h3_past_trap_entry || h3_past_trap_exit || h3_past_x_advance_writes_mstatus;

// --- 7d. Mutual exclusion, and what is true instead ------------------------
// h3_retire and h3_trap_entry are NOT exclusive, and NegRetireTrapExclusive in
// step 1 proves it.  Two separate reasons, both architectural:
//
//   * INTERRUPT.  hdl/hazard3_core.v:1504-1507: "Interrupt entry does not
//     prevent writeback, because the interrupt is notionally inserted in
//     between the instruction in M and the instruction in X."  The M
//     instruction retires and the trap is entered on the same cycle, with
//     mepc taking the *X* instruction's PC (:1400).
//   * EXCEPTION.  The excepting instruction's slot is what completes: m_stall
//     (:1391-1392) holds it in M until the handshake goes through, so the
//     handshake cycle is also the M->W crossing.
//
// What IS exclusive is the *effect*: an exception replaces the instruction in
// M, so it must suppress that instruction's register write.
// hdl/hazard3_core.v:1509, xm_except != EXCEPT_NONE, is the RTL's mechanism;
// this states it as an architectural fact about the two events.
logic h3_exception_suppresses_write;
assign h3_exception_suppresses_write =
    !(h3_trap_entry && !h3_trap_is_irq) || !h3_reg_write;

// An exception trap always coincides with the completion of the instruction
// that raised it: the M slot is occupied and crosses M/W on the handshake
// cycle.  (This is why rvfi_valid && rvfi_trap is a single report, and why the
// harness must not treat exception-trap entry as an instruction-less event the
// way it must treat an interrupt.)
logic h3_exception_trap_retires;
assign h3_exception_trap_retires =
    !(h3_trap_entry && !h3_trap_is_irq) || h3_retire;

// MRET commits its trap-exit effects on the cycle it retires as an
// instruction.  Positive half of "MRET is architectural but is not a trap".
logic h3_trap_exit_retires;
assign h3_trap_exit_retires = !h3_trap_exit || h3_retire;

// A trap handshake is exactly one of entry / exit / refetch.  True by
// construction of the three wires above; kept as a cheap regression against
// someone editing the EXCEPT_* constants.
logic h3_trap_kinds_partition;
assign h3_trap_kinds_partition =
    (h3_trap_handshake == (h3_trap_entry || h3_trap_exit || h3_refetch)) &&
    !(h3_trap_entry && h3_trap_exit) &&
    !(h3_trap_entry && h3_refetch)   &&
    !(h3_trap_exit  && h3_refetch);

// --- 7e. Did enabling the RVFI monitor bring in an assumption? --------------
// hdl/hazard3_csr.v:1554-1555 would
//     if (in_trap) assume(except == EXCEPT_NONE || except == EXCEPT_MRET);
// which makes nested traps unreachable and would quietly gut every property
// about exception entry.  hdl/hazard3_csr.v:1570-1571 would likewise assume
// IRQs are never deasserted.  Both sit inside `ifdef RISCV_FORMAL, which
// -DHAZARD3_RVFI_STANDALONE now defines -- but that `ifdef is itself nested
// inside `ifdef HAZARD3_ASSERTIONS (:1537), which this flow does not define,
// so neither should be in the model.
//
// There are two independent checks that they are not.
//
//   (1) STRUCTURAL, and the stronger of the two: the AIGER constraint count.
//       Assumptions become AIGER constraints, and the header's C field is 5
//       both before and after this gate.  check_env.sh compares it across the
//       two models on every build.
//
//   (2) BEHAVIOURAL, below.  in_trap is the CSR file's own flag
//       (hdl/hazard3_csr.v:1540-1547), reproduced here because it lives inside
//       the `ifdef and so is absent from the model.  h3_neg_nested_trap_assume
//       is the body of the first assumption, restricted to the state that
//       assumption talks about.  If the assumption got into the model this
//       would be PROVABLE; it is in step 1 and must FAIL.
logic h3_in_trap;

initial h3_in_trap = 1'b0;

always @ (posedge clk_i) begin
    if (!rst_ni)
        h3_in_trap <= 1'b0;
    else
        h3_in_trap <= (h3_in_trap || h3_trap_handshake) && !h3_trap_exit;
end

logic h3_neg_nested_trap_assume;
assign h3_neg_nested_trap_assume =
    !h3_in_trap ||
    cpu.core.xm_except == H3_EXCEPT_NONE ||
    cpu.core.xm_except == H3_EXCEPT_MRET;

// ===========================================================================
// 8.  Non-vacuity controls (step 1 of thm/hazard3.proof -- these MUST FAIL)
// ===========================================================================
// Every property in 7c-7d is an implication guarded by a commit event.  An
// event that can never fire makes its guard vacuous, so each event needs a
// witness.  Each wire below says "this event never happens"; each must produce
// a counterexample under BMC.
logic h3_neg_never_retire;
assign h3_neg_never_retire = !h3_retire;

logic h3_neg_never_trap_entry;
assign h3_neg_never_trap_entry = !h3_trap_entry;

logic h3_neg_never_irq_trap;
assign h3_neg_never_irq_trap = !(h3_trap_entry && h3_trap_is_irq);

logic h3_neg_never_exc_trap;
assign h3_neg_never_exc_trap = !(h3_trap_entry && !h3_trap_is_irq);

logic h3_neg_never_trap_exit;
assign h3_neg_never_trap_exit = !h3_trap_exit;

logic h3_neg_never_reg_write;
assign h3_neg_never_reg_write = !h3_reg_write;

logic h3_neg_never_rvfi_valid;
assign h3_neg_never_rvfi_valid = !h3_rvfi_valid;

// THE IMPORTANT ONE.  If this PROVED, retire and trap entry would be mutually
// exclusive, one commit predicate would do, and the whole two-event structure
// above would be unnecessary machinery.  It must fail.
logic h3_neg_retire_trap_exclusive;
assign h3_neg_retire_trap_exclusive = !(h3_retire && h3_trap_entry);
