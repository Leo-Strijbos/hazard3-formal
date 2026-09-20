// ===========================================================================
// Hazard3 harness: the core and its environment.
//
// This file is `include`d, verbatim and identically, by BOTH tops:
//   check/h3_top.sv       -> build/all.aig   (core + environment + Sail spec)
//   check/h3_core_top.sv  -> build/core.aig  (core + environment only)
//
// That is the mechanism by which the two models are guaranteed to constrain
// the core identically, which is what makes a lemma proved on build/core.aig
// usable on build/all.aig.  Do not add anything core-side to one top without
// adding it here.  (`make check-env` diffs the two models' environments.)
// ===========================================================================

// ---------------------------------------------------------------------------
// Reset
// ---------------------------------------------------------------------------
// Yosys-based tools have no notion of a reset signal, so (exactly as the Ibex
// harness does) we build one: low in the initial state, high forever after.
logic rst_ni;
initial rst_ni = 1'b0;
always @(posedge clk_i) rst_ni = 1'b1;

// ---------------------------------------------------------------------------
// Hazard3 instance
// ---------------------------------------------------------------------------

// AHB5 master port.  hready/hresp/hexokay/hrdata are driven by nothing and so
// become free inputs (`setundef -undriven -anyseq`); they are constrained by
// the ahbl_slave_assumptions instance below.
logic [31:0] haddr;
logic        hwrite;
logic [1:0]  htrans;
logic [2:0]  hsize;
logic [2:0]  hburst;
logic [3:0]  hprot;
logic        hmastlock;
logic [7:0]  hmaster;
logic        hexcl;
logic        hready;   // free, constrained
logic        hresp;    // free, constrained
logic        hexokay;  // free, unconstrained (EXTENSION_A=0, so unused)
logic [31:0] hwdata;
logic [31:0] hrdata;   // free, unconstrained (data, not protocol)

// Power control.  pwrup_ack/unblock_in are free.  With EXTENSION_XH3POWER=0
// the msleep CSR fields are hardwired 0, so hazard3_power_ctrl never leaves
// S_AWAKE and never looks at pwrup_ack -- see the PowerStateAwake lemma.
logic        pwrup_req;
logic        pwrup_ack;   // free
logic        clk_en;
logic        unblock_out;
logic        unblock_in;  // free

// Memory ordering
logic        fence_i_vld;
logic        fence_d_vld;
logic        fence_rdy;   // free

// Debug.  DEBUG_SUPPORT=0, so no debug module is attached in this
// configuration and every dbg_* input is tied off rather than left free.
//
// This is NOT cosmetic.  hazard3_cpu_1port's bus arbiter grants the debug
// system-bus port (`bus_gnt_s`) with *no* DEBUG_SUPPORT guard -- see
// hdl/hazard3_cpu_1port.v:232 -- so a free `dbg_sbus_vld` puts a completely
// unconstrained second master (address, size, write data) onto the AHB port,
// and the AHB5 master contract is then violated immediately and for reasons
// that have nothing to do with the core.  Hazard3's own bus_compliance_1port
// testbench handles this by instantiating test/formal/common/sbus_assumptions.v;
// that file cannot be used here because it uses `always assume(...)` (an
// immediate assumption with no event control), which segfaults yosys-slang.
// Tying the port off is the stronger and simpler statement for DEBUG_SUPPORT=0.
logic        dbg_req_halt;
logic        dbg_req_halt_on_reset;
logic        dbg_req_resume;
logic        dbg_halted;
logic        dbg_running;
logic [31:0] dbg_data0_rdata;
logic [31:0] dbg_data0_wdata;
logic        dbg_data0_wen;
logic [31:0] dbg_instr_data;
logic        dbg_instr_data_vld;
logic        dbg_instr_data_rdy;
logic        dbg_instr_caught_exception;
logic        dbg_instr_caught_ebreak;
logic [31:0] dbg_sbus_addr;
logic        dbg_sbus_write;
logic [1:0]  dbg_sbus_size;
logic        dbg_sbus_vld;
logic        dbg_sbus_rdy;
logic        dbg_sbus_err;
logic [31:0] dbg_sbus_wdata;
logic [31:0] dbg_sbus_rdata;

assign dbg_req_halt          = 1'b0;
assign dbg_req_halt_on_reset = 1'b0;
assign dbg_req_resume        = 1'b0;
assign dbg_data0_rdata       = 32'h0;
assign dbg_instr_data        = 32'h0;
assign dbg_instr_data_vld    = 1'b0;
assign dbg_sbus_addr         = 32'h0;
assign dbg_sbus_write        = 1'b0;
assign dbg_sbus_size         = 2'h0;
assign dbg_sbus_vld          = 1'b0;
assign dbg_sbus_wdata        = 32'h0;

// Interrupts.  Left free: the IRQ environment is a later gate.
logic        irq;          // free (NUM_IRQS == 1)
logic        soft_irq;     // free
logic        timer_irq;    // free

// ---------------------------------------------------------------------------
// RVFI port bundle (gate 3)
// ---------------------------------------------------------------------------
// Outputs of hdl/hazard3_rvfi_monitor.vh, which hazard3_core.v:1582-1584
// includes under `ifdef RISCV_FORMAL and hazard3_cpu_1port.v:138-140 forwards.
// The build scripts now pass -DHAZARD3_RVFI_STANDALONE, Hazard3's own switch
// for exposing the RVFI trace port outside the riscv-formal harness: it makes
// hazard3_core.v:6-8 and hazard3_cpu_1port.v:10-12 include
// hdl/hazard3_rvfi_standalone_defs.vh, which defines RISCV_FORMAL and the
// `RVFI_OUTPUTS / `RVFI_CONN port macros.  The harness writes no RVFI
// boilerplate of its own -- the monitor is the author's file, verbatim.
//
// AUDIT: what else does that define drag in?  Three `ifdef sites, and all
// three are safe:
//   * hdl/hazard3_rvfi_monitor.vh:329-332, a non-synthesisable
//     `assert(!m_stall)` inside `if (xm_memop == MEMOP_AMO)`.  It is inside
//     `ifndef HAZARD3_RVFI_STANDALONE, so this define REMOVES it.  That
//     matters mechanically as well as semantically: a live $assert cell would
//     add a bad-state output and shift the property set that `aig-manip
//     select` and check_env.sh count.
//   * hdl/hazard3_rvfi_monitor.vh:374-386, an `assume` bounding sleep
//     duration, under RISCV_FORMAL_FAIRNESS.  NOT defined by
//     hazard3_rvfi_standalone_defs.vh and never to be defined here: it is the
//     liveness fairness constraint the harness plan deliberately does without.
//   * hdl/hazard3_csr.v:1550-1572, two riscv-formal convenience `assume`s
//     ("no nested exceptions", "IRQs are not deasserted").  They are nested
//     inside `ifdef HAZARD3_ASSERTIONS (:1537), which this flow does not
//     define, so they are absent.  NegNestedTrapAssume in thm/hazard3.proof is
//     the mechanical check that they really are absent: it is the body of the
//     first one and it must FAIL.
//
// These are the CORE AUTHOR'S definition of retirement.  Nothing in the
// harness drives them and nothing may constrain them; they exist solely so
// that check/peek/h3_commit.svh can cross-check our commit point against them
// (RetireAgreesRvfiValid / MValidAgreesRvfi in thm/hazard3.proof).
logic        h3_rvfi_valid;
logic [63:0] h3_rvfi_order;
logic [31:0] h3_rvfi_insn;
logic        h3_rvfi_trap;
logic        h3_rvfi_halt;
logic        h3_rvfi_intr;
logic [1:0]  h3_rvfi_mode;
logic [1:0]  h3_rvfi_ixl;
logic [4:0]  h3_rvfi_rs1_addr;
logic [4:0]  h3_rvfi_rs2_addr;
logic [31:0] h3_rvfi_rs1_rdata;
logic [31:0] h3_rvfi_rs2_rdata;
logic [4:0]  h3_rvfi_rd_addr;
logic [31:0] h3_rvfi_rd_wdata;
logic [31:0] h3_rvfi_pc_rdata;
logic [31:0] h3_rvfi_pc_wdata;
logic [31:0] h3_rvfi_mem_addr;
logic [3:0]  h3_rvfi_mem_rmask;
logic [3:0]  h3_rvfi_mem_wmask;
logic [31:0] h3_rvfi_mem_rdata;
logic [31:0] h3_rvfi_mem_wdata;
logic        h3_rvfi_mem_fault;
logic [3:0]  h3_rvfi_mem_fault_rmask;
logic [3:0]  h3_rvfi_mem_fault_wmask;

// ---------------------------------------------------------------------------
// Identification inputs: ARBITRARY BUT CONSTANT  (gate 2)
// ---------------------------------------------------------------------------
// mhartid_val and eco_version are tie-off ports.  They are not protocol
// signals and not data returned by a transaction: they are the value that a
// containing SoC straps onto the core once, at instantiation.  In the RTL they
// have exactly one reader each and both are read-only CSR fields:
//
//   mhartid_val  -> hdl/hazard3_csr.v:770   rdata = mhartid_val;          (MHARTID)
//   eco_version  -> hdl/hazard3_csr.v:401   mimpid_rdata[7:4]             (MIMPID)
//
// Left undriven they become FREE SIGNALS RE-CHOSEN EVERY CYCLE (see BRINGUP.md,
// "Free state"), so two reads of mhartid in the same program could return
// different values.  No real instantiation behaves that way, and the
// specification has one mhartid, so the comparison would be unprovable for a
// reason that has nothing to do with the core.
//
// This is fixed WITHOUT an assumption: the value is sampled from a free wire
// during the reset cycle and held forever after.  The solver still gets to
// choose the hart ID -- the theorem is "for every hart ID", not "for hart 0" --
// but it must choose once.  Note there is deliberately no `assume` here; the
// constancy is structural, so it cannot be accidentally dropped.
logic [31:0] h3_mhartid_free;      // undriven -> free every cycle
logic [3:0]  h3_eco_version_free;  // undriven -> free every cycle
logic [31:0] mhartid_val;
logic [3:0]  eco_version;

initial begin
    mhartid_val = 32'h0;
    eco_version = 4'h0;
end

always @ (posedge clk_i) begin
    // rst_ni is low only in the initial state, so this samples once.
    mhartid_val <= rst_ni ? mhartid_val : h3_mhartid_free;
    eco_version <= rst_ni ? eco_version : h3_eco_version_free;
end

hazard3_cpu_1port #(
    .RESET_VECTOR        (32'h0000_0000),
    .MTVEC_INIT          (32'h0000_0000),
    // ISA
    .EXTENSION_A         (0),  // NOTE: defaults to 1 upstream, must be zeroed
    .EXTENSION_C         (1),
    .EXTENSION_E         (0),
    .EXTENSION_M         (1),
    .EXTENSION_ZBA       (0),
    .EXTENSION_ZBB       (0),
    .EXTENSION_ZBC       (0),
    .EXTENSION_ZBKB      (0),
    .EXTENSION_ZBKX      (0),
    .EXTENSION_ZBS       (0),
    .EXTENSION_ZCB       (0),
    .EXTENSION_ZCLSD     (0),
    .EXTENSION_ZCMP      (0),
    .EXTENSION_ZIFENCEI  (0),
    .EXTENSION_ZILSD     (0),
    // Custom extensions all off
    .EXTENSION_XH3BEXTM  (0),
    .EXTENSION_XH3IRQ    (0),
    .EXTENSION_XH3PMPM   (0),
    .EXTENSION_XH3POWER  (0),
    // CSRs: M-mode only
    .CSR_M_MANDATORY     (1),
    .CSR_M_TRAP          (1),
    .CSR_COUNTER         (0),
    .U_MODE              (0),
    .PMP_REGIONS         (0),
    .DEBUG_SUPPORT       (0),
    .BREAKPOINT_TRIGGERS (0),
    .NUM_IRQS            (1),
    .IRQ_PRIORITY_BITS   (0),
    // Microarchitecture (matches test/formal/riscv-formal defaults)
    .REDUCED_BYPASS      (0),
    .MULDIV_UNROLL       (1),
    .MUL_FAST            (0),
    .MUL_FASTER          (0),
    .MULH_FAST           (0),
    .FAST_BRANCHCMP      (1),
    .BRANCH_PREDICTOR    (0),
    .RESET_REGFILE       (0)
) cpu (
    .clk                        (clk_i),
    .clk_always_on              (clk_i),
    .rst_n                      (rst_ni),

    .pwrup_req                  (pwrup_req),
    .pwrup_ack                  (pwrup_ack),
    .clk_en                     (clk_en),
    .unblock_out                (unblock_out),
    .unblock_in                 (unblock_in),

    .haddr                      (haddr),
    .hwrite                     (hwrite),
    .htrans                     (htrans),
    .hsize                      (hsize),
    .hburst                     (hburst),
    .hprot                      (hprot),
    .hmastlock                  (hmastlock),
    .hmaster                    (hmaster),
    .hexcl                      (hexcl),
    .hready                     (hready),
    .hresp                      (hresp),
    .hexokay                    (hexokay),
    .hwdata                     (hwdata),
    .hrdata                     (hrdata),

    .fence_i_vld                (fence_i_vld),
    .fence_d_vld                (fence_d_vld),
    .fence_rdy                  (fence_rdy),

    .dbg_req_halt               (dbg_req_halt),
    .dbg_req_halt_on_reset      (dbg_req_halt_on_reset),
    .dbg_req_resume             (dbg_req_resume),
    .dbg_halted                 (dbg_halted),
    .dbg_running                (dbg_running),
    .dbg_data0_rdata            (dbg_data0_rdata),
    .dbg_data0_wdata            (dbg_data0_wdata),
    .dbg_data0_wen              (dbg_data0_wen),
    .dbg_instr_data             (dbg_instr_data),
    .dbg_instr_data_vld         (dbg_instr_data_vld),
    .dbg_instr_data_rdy         (dbg_instr_data_rdy),
    .dbg_instr_caught_exception (dbg_instr_caught_exception),
    .dbg_instr_caught_ebreak    (dbg_instr_caught_ebreak),

    .dbg_sbus_addr              (dbg_sbus_addr),
    .dbg_sbus_write             (dbg_sbus_write),
    .dbg_sbus_size              (dbg_sbus_size),
    .dbg_sbus_vld               (dbg_sbus_vld),
    .dbg_sbus_rdy               (dbg_sbus_rdy),
    .dbg_sbus_err               (dbg_sbus_err),
    .dbg_sbus_wdata             (dbg_sbus_wdata),
    .dbg_sbus_rdata             (dbg_sbus_rdata),

    .mhartid_val                (mhartid_val),
    .eco_version                (eco_version),

    .irq                        (irq),
    .soft_irq                   (soft_irq),
    .timer_irq                  (timer_irq),

    // RVFI (gate 3 cross-check only -- see above)
    .rvfi_valid                 (h3_rvfi_valid),
    .rvfi_order                 (h3_rvfi_order),
    .rvfi_insn                  (h3_rvfi_insn),
    .rvfi_trap                  (h3_rvfi_trap),
    .rvfi_halt                  (h3_rvfi_halt),
    .rvfi_intr                  (h3_rvfi_intr),
    .rvfi_mode                  (h3_rvfi_mode),
    .rvfi_ixl                   (h3_rvfi_ixl),
    .rvfi_rs1_addr              (h3_rvfi_rs1_addr),
    .rvfi_rs2_addr              (h3_rvfi_rs2_addr),
    .rvfi_rs1_rdata             (h3_rvfi_rs1_rdata),
    .rvfi_rs2_rdata             (h3_rvfi_rs2_rdata),
    .rvfi_rd_addr               (h3_rvfi_rd_addr),
    .rvfi_rd_wdata              (h3_rvfi_rd_wdata),
    .rvfi_pc_rdata              (h3_rvfi_pc_rdata),
    .rvfi_pc_wdata              (h3_rvfi_pc_wdata),
    .rvfi_mem_addr              (h3_rvfi_mem_addr),
    .rvfi_mem_rmask             (h3_rvfi_mem_rmask),
    .rvfi_mem_wmask             (h3_rvfi_mem_wmask),
    .rvfi_mem_rdata             (h3_rvfi_mem_rdata),
    .rvfi_mem_wdata             (h3_rvfi_mem_wdata),
    .rvfi_mem_fault             (h3_rvfi_mem_fault),
    .rvfi_mem_fault_rmask       (h3_rvfi_mem_fault_rmask),
    .rvfi_mem_fault_wmask       (h3_rvfi_mem_fault_wmask)
);

// ===========================================================================
// Bus environment (gate 1)
// ===========================================================================
// Hazard3's own AHB-Lite slave assumptions, instantiated verbatim from
// hazard3/test/formal/common/ahbl_slave_assumptions.v and wired exactly as
// hazard3/test/formal/bus_compliance_1port/tb.v:159-179 wires them (note
// dst_hready_resp and dst_hready both come from the single hready, because
// there is one slave and no HREADY mux).
//
// MAX_BUS_STALL = -1: stalls are UNBOUNDED.  Do not change this without saying
// so in the result: any value >= 0 is a fairness assumption that weakens every
// proof made against this model.
localparam int H3_MAX_BUS_STALL = -1;

ahbl_slave_assumptions #(
    .W_ADDR          (32),
    .W_DATA          (32),
    .MAX_BUS_STALL   (H3_MAX_BUS_STALL)
) ahbl_slave_assumptions_i (
    .clk             (clk_i),
    .rst_n           (rst_ni),

    .dst_hready_resp (hready),
    .dst_hready      (hready),
    .dst_hresp       (hresp),
    .dst_hexokay     (hexokay),
    .dst_haddr       (haddr),
    .dst_hwrite      (hwrite),
    .dst_htrans      (htrans),
    .dst_hsize       (hsize),
    .dst_hburst      (hburst),
    .dst_hprot       (hprot),
    .dst_hmastlock   (hmastlock),
    .dst_hexcl       (hexcl),
    .dst_hwdata      (hwdata),
    .dst_hrdata      (hrdata)
);

// Harness self-check: the AHB5 *master* contract.  Same wiring as tb.v:181-198.
// These are not assumptions -- every ok_* is a proof obligation, declared in
// thm/hazard3.proof.  If one fails, the harness (or the core) is wrong.
logic h3_ahb_aph_aligned;
logic h3_ahb_aph_size;
logic h3_ahb_aph_stable;
logic h3_ahb_seq_after_active;
logic h3_ahb_seq_addr;
logic h3_ahb_excl_no_pipeline;
logic h3_ahb_dph_wdata_stable;
logic h3_ahb_dph_excl_reserved;

h3_ahbl_master_props #(
    .W_ADDR               (32),
    .W_DATA               (32)
) ahbl_master_props_i (
    .clk                  (clk_i),
    .rst_n                (rst_ni),

    .src_hready           (hready),
    .src_hresp            (hresp),
    .src_hexokay          (hexokay),
    .src_haddr            (haddr),
    .src_hwrite           (hwrite),
    .src_htrans           (htrans),
    .src_hsize            (hsize),
    .src_hburst           (hburst),
    .src_hprot            (hprot),
    .src_hmastlock        (hmastlock),
    .src_hexcl            (hexcl),
    .src_hwdata           (hwdata),
    .src_hrdata           (hrdata),

    .ok_aph_aligned       (h3_ahb_aph_aligned),
    .ok_aph_size          (h3_ahb_aph_size),
    .ok_aph_stable        (h3_ahb_aph_stable),
    .ok_seq_after_active  (h3_ahb_seq_after_active),
    .ok_seq_addr          (h3_ahb_seq_addr),
    .ok_excl_no_pipeline  (h3_ahb_excl_no_pipeline),
    .ok_dph_wdata_stable  (h3_ahb_dph_wdata_stable),
    .ok_dph_excl_reserved (h3_ahb_dph_excl_reserved)
);

// ===========================================================================
// Core-only lemma support wires (gate 2)
// ===========================================================================
// Every wire below mentions ONLY signals inside `cpu`, so every property built
// from them is meaningful in both models.  Each is annotated with the RTL fact
// it restates; most are Hazard3's own `ifdef HAZARD3_ASSERTIONS` assertions,
// which this flow does not compile (HAZARD3_ASSERTIONS is undefined), restated
// as psgen properties.

// hazard3_frontend.fetch_addr is the fetch address counter.  Reset to
// RESET_VECTOR (0) and thereafter only ever {jump_target[31:2],2'b00}+{..,2'b00},
// {btb_target_addr[31:2],2'b00} or fetch_addr+4.  hdl/hazard3_frontend.v:326-350.
logic h3_fetch_addr_word_aligned;
assign h3_fetch_addr_word_aligned = cpu.core.frontend.fetch_addr[1:0] == 2'b00;

// At most two instruction fetches in flight.  fetch_stall gates a third.
// Restates hdl/hazard3_frontend.v:447.
logic h3_pending_fetches_bounded;
assign h3_pending_fetches_bounded = cpu.core.frontend.pending_fetches < 2'd3;

// Fetches to be discarded after a jump cannot exceed fetches in flight.
// Restates hdl/hazard3_frontend.v:446.
logic h3_flush_le_pending;
assign h3_flush_le_pending =
    cpu.core.frontend.ctr_flush_pending <= cpu.core.frontend.pending_fetches;

// Fetch data only arrives for a fetch that was actually issued.  This is the
// one lemma here that genuinely depends on the bus environment: mem_data_vld is
// core_dph_ready_i = bus_active_dph_i && hready.
// Restates hdl/hazard3_frontend.v:448.
logic h3_data_vld_implies_pending;
assign h3_data_vld_implies_pending =
    !(cpu.core.frontend.mem_data_vld && ~|cpu.core.frontend.pending_fetches);

// The CIR holds 0, 1 or 2 valid halfwords, never 3.
// Restates hdl/hazard3_frontend.v:674.
logic h3_cir_vld_bounded;
assign h3_cir_vld_bounded = cpu.core.frontend.cir_vld <= 2'd2;

// The operand-bypass selects are one-hot-or-zero: a 3-bit register whose only
// legal values are the four in hdl/hazard3_core.v:536-543 (regfile / XM / MW /
// none).  This is the "register only ever holds values from its enum" lemma.
logic h3_bypass_sel1_legal;
logic h3_bypass_sel2_legal;
assign h3_bypass_sel1_legal =
    cpu.core.x_rs1_select_regs_xm_mw == 3'b000 ||
    cpu.core.x_rs1_select_regs_xm_mw == 3'b001 ||
    cpu.core.x_rs1_select_regs_xm_mw == 3'b010 ||
    cpu.core.x_rs1_select_regs_xm_mw == 3'b100;
assign h3_bypass_sel2_legal =
    cpu.core.x_rs2_select_regs_xm_mw == 3'b000 ||
    cpu.core.x_rs2_select_regs_xm_mw == 3'b001 ||
    cpu.core.x_rs2_select_regs_xm_mw == 3'b010 ||
    cpu.core.x_rs2_select_regs_xm_mw == 3'b100;

// At most one of the three bus data phases (instruction fetch / load-store /
// debug sbus) can be outstanding at a time: mutual exclusion of flags that are
// registered from the one-hot arbiter grant.  hdl/hazard3_cpu_1port.v:228-248.
logic h3_bus_dph_mutex;
assign h3_bus_dph_mutex =
    !(cpu.bus_active_dph_i && cpu.bus_active_dph_d) &&
    !(cpu.bus_active_dph_i && cpu.bus_active_dph_s) &&
    !(cpu.bus_active_dph_d && cpu.bus_active_dph_s);

// EXTENSION_XH3POWER=0 hardwires msleep.{deepsleep,powerdown,sleeponblock} to 0
// (hdl/hazard3_csr.v:497-505), so hazard3_power_ctrl's state machine can never
// leave S_AWAKE (hdl/hazard3_power_ctrl.v:85).  A state register that is
// constant in this configuration.
logic h3_power_state_awake;
assign h3_power_state_awake = cpu.core.power_ctrl.state == 2'h0;

// WAS MEASURED FALSE UNTIL GATE 2, NOW TRUE BY CONSTRUCTION.
// EXTENSION_A=0 makes the whole guard of the x_amo_phase update constant-false
// (hdl/hazard3_core.v:645), so yosys left the register with NO DRIVER and
// `setundef -undriven -anyseq` turned it into a free 3-bit signal.  The RTL's
// own semantics hold it at its reset value 3'h0 forever, so the build scripts
// now `connect -set` it to 0 before setundef runs -- see BRINGUP.md, "Free
// state", and the `connect -set` block in build_h3_core.ys.  This lemma is the
// regression test for that fix: it is in step 0 and must PROVE.
logic h3_amo_phase_zero;
assign h3_amo_phase_zero = cpu.core.x_amo_phase == 3'h0;

// SAME, AND THE ONE THAT MATTERS.  hazard3_csr.v:165 only updates `debug_mode`
// under `else if (DEBUG_SUPPORT)`, so with DEBUG_SUPPORT=0 it too was undriven
// and free.  Unlike x_amo_phase it is NOT inert: gate 2's audit found 17 reads
// that carry no DEBUG_SUPPORT factor, several of them functionally live --
// hazard3_csr.v:1484/:1490 (a stuck-1 blocks ALL IRQ trap entry, since
// CSR_M_TRAP=1), :701 (a CSR write to DPC would overwrite the architectural PC
// via hazard3_decode.v:210-211), hazard3_frontend.v:592 and
// hazard3_decode.v:212.  Also driven to 0 by `connect -set` now; this lemma is
// the regression test, in step 0, and must PROVE.
//
// Correction to BRINGUP.md gate 1: hazard3_core.v:967 is NOT an ungated read.
// It lives inside `generate if (PMP_REGIONS > 0) begin: have_pmp`
// (hdl/hazard3_core.v:963-964) and is elaborated away here; the no_pmp branch
// ties x_loadstore_pmp_fail to 1'b0 at :1001.  The ungated reads are the ones
// listed above.
logic h3_debug_mode_zero;
assign h3_debug_mode_zero = !cpu.core.csr_u.debug_mode;

// "Unit busy implies an instruction is present": the sequential multiplier /
// divider only stalls stage X while stage X is actually executing a MULDIV.
// Restates hdl/hazard3_core.v:892.  ALUOP_MULDIV == 6'h0c (hdl/hazard3_ops.vh:18).
logic h3_muldiv_busy_implies_op;
assign h3_muldiv_busy_implies_op =
    !cpu.core.x_stall_muldiv || cpu.core.d_aluop == 6'h0c;

// DEBUG_SUPPORT=0 masks every write to dcsr.{ebreakm,ebreaku,step} with
// {3{|DEBUG_SUPPORT}} (hdl/hazard3_csr.v:684-688) and the reset value is 0, so
// all three are constants.  They are read by irq_active (hdl/hazard3_csr.v:1435)
// and pwr_wfi_wakeup_req (:1443), which is exactly the door the Ibex solver
// walked through, so this is worth pinning down rather than assuming.
logic h3_dcsr_debug_bits_zero;
assign h3_dcsr_debug_bits_zero =
    !cpu.core.csr_u.dcsr_step &&
    !cpu.core.csr_u.dcsr_ebreakm &&
    !cpu.core.csr_u.dcsr_ebreaku;

// ---------------------------------------------------------------------------
// Deliberate negative control (step 1 of thm/hazard3.proof).  This must FAIL:
// fetch_addr[2] toggles as soon as the frontend gets one fetch granted.  If it
// were ever proved, something would be wrong with the harness -- most likely
// rst_ni never going high, which makes every `disable iff (~rst_ni)` vacuous.
logic h3_neg_control;
assign h3_neg_control = ~cpu.core.frontend.fetch_addr[2];

// ===========================================================================
// Abstraction function (gate 2)
// ===========================================================================
// pre_mepc and the commit-point wires it needs.  Kept in its own file because
// it is the thing that will grow: gate 4 adds the rest of the architectural
// state to it.  Included HERE, not in the tops, so that both models get it.
//
// ORDER MATTERS: h3_commit.svh defines the commit events, h3_abs.svh uses
// them.
`include "peek/h3_commit.svh"
`include "peek/h3_abs.svh"

// ===========================================================================
// The data-side memory view (gate 5)
// ===========================================================================
// check/peek/h3_mem.svh is the Hazard3 analogue of Ibex's check/peek/mem.sv: the
// core's D-side AHB5 port as the goals need to see it (address phase, data
// phase, byte lanes), plus the free wire through which the specification is told
// what a load returned.  It is included BEFORE the follower because the follower
// latches that wire and tracks the late exception the data phase can produce.
`include "peek/h3_mem.svh"

// ===========================================================================
// The follower and the ghost state (gate 4)
// ===========================================================================
// check/peek/h3_follower.svh tracks one instruction from the X->M handoff to
// its retirement, holding what the specification said it would do, and keeps
// the ghost copy of architectural state that carries the specification's answer
// from one query to the next.
//
// It declares the `spec_*` boundary wires, which are DRIVEN by the spec_api
// instance in check/h3_top.sv (build/all.aig) and left UNDRIVEN -- hence free --
// in check/h3_core_top.sv (build/core.aig).  That is what lets the identical
// property set be built into both models.  See the file header.
//
// ORDER MATTERS: h3_commit.svh defines the events, h3_abs.svh the pre-state,
// h3_mem.svh the bus view, h3_follower.svh uses all three.
`include "peek/h3_follower.svh"

// ===========================================================================
// THE CORRECTNESS GOALS (gate 5)
// ===========================================================================
// check/peek/h3_goals.svh -- Wrap, Load, Store, NoMem.  Everything above this
// line is machinery; this is the claim.  It goes last because it uses all of it.
`include "peek/h3_goals.svh"
