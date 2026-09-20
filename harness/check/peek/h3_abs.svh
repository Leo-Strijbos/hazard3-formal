// ===========================================================================
// check/peek/h3_abs.svh -- Hazard3 abstraction function.
//
//   GATE 4: extended from the gate-2 prototype (mepc alone) to the whole
//   architectural state the specification comparison needs -- six CSRs, the
//   architectural PC, and the register file.
//
// `include`d by check/h3_core_common.svh, so it is present, identically, in
// BOTH models (build/core.aig and build/all.aig).  Everything here mentions
// only signals inside `cpu`, so every property built on it is a core-only
// property in the sense of `make check-env`.
// ===========================================================================
//
// WHY THIS FILE LOOKS NOTHING LIKE IBEX'S check/peek/abs.sv
// ---------------------------------------------------------------------------
// Ibex's abs.sv builds BOTH a pre-state and a post-state:
//
//     assign pre_mepc  = `CSR.mepc_q;
//     assign post_mepc = `CSR.mepc_en ? `CSR.mepc_d : pre_mepc;
//
// It can do that because ibex_cs_registers exposes a `_d`/`_en` next-state
// pair for every CSR.  hazard3_csr.v does not: every architectural CSR is
// written from inside a single `always @(posedge clk or negedge rst_n)` block
// and neither the next value nor the write enable exists as a named wire.
// Reconstructing `post_mepc` here would mean copying
//
//     mepc <= trapreg_update_enter ? mepc_in       & MEPC_MASK
//           : (wen_m_mode && addr == MEPC) ? wdata_update & MEPC_MASK : mepc;
//
// into the harness -- option (a) of the plan, which is rejected: a copy of the
// design's write logic makes a bug in that logic invisible, because the copy
// contains the same bug.
//
// So this file implements option (b): PRE-STATE ONLY.  `pre_<x>` is the
// architectural state as observed by an instruction that begins now; the ghost
// mechanism (check/peek/h3_follower.svh) carries the specification's answer
// forward to the next comparison point, where it meets the DUT's own
// post-state as that state's *pre*-state.  Nothing in the harness ever
// computes what a CSR should become.
//
// GATE 4 CONFIRMS DESIGN (b) SCALES, as gate 2 predicted: the per-register
// cost is one `assign` plus two obligations, and every `assign` is a
// re-encoding of stored bits (mstatus, mcause, mtvec) rather than a
// re-implementation of a write.  Section 4a proves the re-encodings right by
// comparing them against the CSR file's own read-data path, which is a check
// gate 2 did not have and which is worth more than the prose above.
// ===========================================================================

// ---------------------------------------------------------------------------
// 0.  CSR addresses this file needs.  hdl/hazard3_csr_addr.vh.
// ---------------------------------------------------------------------------
localparam [11:0] H3_CSR_MISA       = 12'h301;
localparam [11:0] H3_CSR_MIE        = 12'h304;
localparam [11:0] H3_CSR_MTVEC      = 12'h305;
localparam [11:0] H3_CSR_MCOUNTEREN = 12'h306;
localparam [11:0] H3_CSR_MSTATUSH   = 12'h310;
localparam [11:0] H3_CSR_MSCRATCH   = 12'h340;
localparam [11:0] H3_CSR_MEPC       = 12'h341;
localparam [11:0] H3_CSR_MTVAL      = 12'h343;
localparam [11:0] H3_CSR_MIP        = 12'h344;
localparam [11:0] H3_CSR_MVENDORID  = 12'hf11;
localparam [11:0] H3_CSR_MARCHID    = 12'hf12;
localparam [11:0] H3_CSR_MIMPID     = 12'hf13;
localparam [11:0] H3_CSR_MHARTID    = 12'hf14;
localparam [11:0] H3_CSR_MCONFIGPTR = 12'hf15;
// mie has a SECOND write address: meicontext.clearts/mtiesave/msiesave write
// mie[7] and mie[3] (hdl/hazard3_csr.v:335-341).  That `else if` branch carries
// no EXTENSION_XH3IRQ guard, so the address is included in mie's change-cause
// list even though EXTENSION_XH3IRQ = 0 makes meicontext undecodable.
localparam [11:0] H3_CSR_MEICONTEXT = 12'hbe5;
// (H3_CSR_MSTATUS = 12'h300 and H3_CSR_MCAUSE = 12'h342 are declared in
//  check/peek/h3_commit.svh, which is included immediately before this file.)

// ===========================================================================
// 1.  THE ABSTRACTION -- architectural state, read directly
// ===========================================================================
// Each `pre_<x>` below is "the value software would read from <x> right now".
// For mstatus / mcause / mtvec that is an assembly of the stored bits into the
// architectural layout, exactly as the CSR file's own read-data case does.

// --- mepc.  hdl/hazard3_csr.v:301.  A flat XLEN word, already masked to
//     MEPC_MASK, so reading it is the whole abstraction. ---------------------
logic [31:0] pre_mepc;
assign pre_mepc = cpu.core.csr_u.mepc;

// --- mscratch.  hdl/hazard3_csr.v:267.  Flat, like mepc. --------------------
logic [31:0] pre_mscratch;
assign pre_mscratch = cpu.core.csr_u.mscratch;

// --- mie.  hdl/hazard3_csr.v:321.  Flat; reserved bits are held 0 by
//     MIE_WMASK = 32'h888 (meie/mtie/msie at bits 11/7/3) -- exactly the three
//     the Sail model knows about.  Unlike Ibex, whose harness marks mie
//     UNCHECKABLE (check/top.sv:478) because Ibex has fast interrupts Sail
//     cannot model, Hazard3 with EXTENSION_XH3IRQ = 0 and NUM_IRQS = 1 has no
//     extra enable bits, so mie is a first-class member of the ghost set. -----
logic [31:0] pre_mie;
assign pre_mie = cpu.core.csr_u.mie;

// --- mtvec.  hdl/hazard3_csr.v:283-297 stores mtvec_reg; the architectural
//     value is {BASE, 1'b0, MODE} with BASE = mtvec_reg[31:2] and
//     MODE = mtvec_reg[0] (:860-866).  Bit 1 is WARL'd to zero on read. -------
logic [31:0] pre_mtvec;
assign pre_mtvec = {cpu.core.csr_u.mtvec_reg[31:2], 1'b0, cpu.core.csr_u.mtvec_reg[0]};

// --- mcause.  hdl/hazard3_csr.v:354-355 stores {mcause_irq, mcause_code[3:0]}
//     and :836-842 zero-fills the middle 27 bits on read.  This is Ibex's
//     widenMCause; a re-encoding, not a re-implementation. -------------------
logic [31:0] pre_mcause;
assign pre_mcause = {cpu.core.csr_u.mcause_irq, 27'h0, cpu.core.csr_u.mcause_code};

// --- mstatus.  hdl/hazard3_csr.v:188-192 stores five separate bits; :778-796
//     is the read layout.  Only the five fields spec_api models are packed here
//     (mie=3, mpie=7, mpp=12:11, mprv=17, tw=21); every other bit of Hazard3's
//     MSTATUS read data is a hard zero, which AbsMstatusIsRdata proves.
//
//     With U_MODE = 0, mstatus_mpp is constant 1 (:255-257) so MPP reads 2'b11
//     = Machine, and mstatus_tw is constant 0 (:244, `&& U_MODE`).  This is the
//     same packing spec_api.sv:202-208 applies to its mstatus_t input, so
//     check/h3_top.sv can unpack pre_mstatus again and nothing is lost. -------
logic [31:0] pre_mstatus;
assign pre_mstatus =
    (32'(cpu.core.csr_u.mstatus_mie)      << 3)  |
    (32'(cpu.core.csr_u.mstatus_mpie)     << 7)  |
    (32'({2{cpu.core.csr_u.mstatus_mpp}}) << 11) |
    (32'(cpu.core.csr_u.mstatus_mprv)     << 17) |
    (32'(cpu.core.csr_u.mstatus_tw)       << 21);

// ---------------------------------------------------------------------------
// 1b.  Architectural state that EXISTS architecturally but is not a register
// ---------------------------------------------------------------------------
// WHAT THE ABSTRACTION CANNOT REACH, AND WHY.
//
// mtval: hdl/hazard3_csr.v:844-846.  MTVAL decodes -- accessing it is legal and
// does not trap -- but there is no register and the read comment is "Hardwired
// to 0".  Read-only-zero mtval is architecturally permitted (the priv spec
// makes mtval WARL), but the Sail model writes exception-specific information
// into it.  So mtval is NOT ghosted and NOT compared; the specification is
// handed constant 0 as its mtval pre-state on every query, which is exactly
// what the DUT would return, and its mtval post-state is discarded.  This is a
// documented non-comparison -- it narrows what the proof covers -- and it is in
// BRINGUP.md's list for gate 4.
logic [31:0] pre_mtval;
assign pre_mtval = 32'h0;

// mcounteren: hdl/hazard3_csr.v:635-648.  Three real reset-0 flops, but every
// write is masked with `|CSR_COUNTER && |U_MODE`, both 0 here, so all three
// bits are permanently 0.  Same treatment as mtval, and AbsMcounterenIsZero
// proves the constancy rather than assuming it.
logic [31:0] pre_mcounteren;
assign pre_mcounteren = 32'h0;

// mip: hdl/hazard3_csr.v:1425-1434, and :1417-1418 in the author's words --
// "In our implementation this register is entirely read-only".  It is an INPUT
// to the specification, never part of the ghost set.
logic [31:0] pre_mip;
assign pre_mip = cpu.core.csr_u.mip;

// Privilege.  U_MODE = 0 makes m_mode constant 1 (hdl/hazard3_csr.v:255-257,
// the explicit `if (!U_MODE)` tie-off), so there is no privilege state to track
// and no pre_priv/post_priv pair to port.  MModeIsM proves the constancy.
logic h3_m_mode_is_m;
assign h3_m_mode_is_m = cpu.core.csr_u.m_mode;

// ---------------------------------------------------------------------------
// 1c.  The architectural PC
// ---------------------------------------------------------------------------
// hdl/hazard3_decode.v:179-227.  `pc` holds the address of the instruction in
// D/X; d_pc and debug_dpc_rdata are both aliases of it (:184-186).  It is also
// what the trap machinery returns to: m_exception_return_addr
// (hdl/hazard3_core.v:1400-1404) is d_pc, walked back by the size of the M
// instruction for an exception and taken verbatim for an interrupt.  So unlike
// Ibex -- whose pre_pc is `wbexc_handling_irq ? pc_if : pc_id` -- Hazard3 needs
// no case split: the interrupt's return address IS the X instruction's PC.
//
// (h3_pc is the same wire under the gate-3 name, declared in h3_commit.svh.)
logic [31:0] pre_pc;
assign pre_pc = cpu.core.decode_u.pc;

// The sequentially-next PC, the specification's `nextpc_i`.  DECODED IN THE
// HARNESS rather than read from hdl/hazard3_decode.v:181-184's pc_seq_next: the
// size of the instruction in the CIR is a property of its encoding (bits [1:0]
// == 2'b11 <-> 32-bit), and the harness is entitled to work that out for
// itself.  Same expression as hazard3_rvfi_monitor.vh:186.
// PreNextPcMatchesSeqNext proves it agrees with the core's own increment.
logic [31:0] pre_nextpc;
assign pre_nextpc = pre_pc + (cpu.core.fd_cir_raw[1:0] == 2'b11 ? 32'd4 : 32'd2);

// ---------------------------------------------------------------------------
// 1d.  The register file
// ---------------------------------------------------------------------------
// hdl/hazard3_regfile_1w2r.v:66-74 (RESET_REGFILE = 0, so the
// real_dualport_noreset branch): one write port, `mem[waddr] <= wdata` on
// `wen`, and TWO REGISTERED read ports.  Because the reads are registered,
// rdata1/rdata2 lag the file by a cycle, which is why hdl/hazard3_core.v
// :369-374 keeps mw_result as a write->read bypass.  None of that is
// architectural: `mem` IS the architectural register file.
//
// The only committed write `mem` does not yet contain is the one on the write
// port THIS cycle (it lands at this edge), so one level of forwarding is needed
// and no more:
//
//     pre_regs[i] = (m_reg_wen && xm_rd == i) ? m_result : mem[i]
//
// which is exactly the shape of Ibex's abs.sv:19-22.  It is NOT a
// reconstruction of Hazard3's bypass network: the three-way mux at
// hdl/hazard3_core.v:574-582 (x_rdata / xm_result / mw_result) is never read by
// the harness.  hazard3_rvfi_monitor.vh:223-224 says why, in the author's words
// -- "Do not reimplement internal bypassing logic. Danger of implementing it
// correctly here but incorrectly in core."  The single write port forwarded
// here is the same pair of signals the comparison itself uses at h3_retire
// (h3_reg_write / xm_rd / m_result), so no new trusted logic is introduced.
//
// The mw_* level of Hazard3's bypass needs no forwarding here because its write
// has ALREADY landed in `mem` (at the previous edge); mw_result exists only to
// compensate for the registered read ports.
//
// RESET_REGFILE = 0 also means `mem` has no reset value.  Nothing here assumes
// one: trace equivalence needs the DUT and the specification to START equal,
// not to start at zero, and that is a gate-5 initial condition (plan section 7).
logic [31:0] pre_regs [32];

assign pre_regs[0] = 32'h0;
for (genvar gi = 1; gi < 32; gi = gi + 1) begin: g_h3_pre_regs
    assign pre_regs[gi] = (h3_reg_write && cpu.core.xm_rd == 5'(gi)) ?
        cpu.core.m_result : cpu.core.regs.real_dualport_noreset.mem[gi];
end

// The cut-down view handed to the specification.  Only the registers the
// instruction in X actually reads get real values; the rest are free, so the
// specification CANNOT depend on a register the decoder did not read.  (Ibex's
// check/spec_instance.sv:36-43, verbatim in shape; its comment applies
// unchanged: too many driven is harmless because they are checked as inputs,
// too few makes instructions fail to be spec conformant.)
//
// d_rs1 / d_rs2 are the decoder's register numbers, forced to 0 for
// instructions with no register operand, which is why index 0 is never driven.
logic [31:0] h3_reg_driven;
logic [31:0] pre_regs_cut [1:31];

assign h3_reg_driven[0] = 1'b0;
for (genvar gj = 1; gj < 32; gj = gj + 1) begin: g_h3_regs_cut
    logic [31:0] free;   // undriven -> free
    assign h3_reg_driven[gj] =
        (cpu.core.d_rs1 == 5'(gj)) || (cpu.core.d_rs2 == 5'(gj));
    assign pre_regs_cut[gj] = h3_reg_driven[gj] ? pre_regs[gj] : free;
end

// ---------------------------------------------------------------------------
// 1e.  Read-only identification CSRs the specification takes as inputs
// ---------------------------------------------------------------------------
// Restated here from the configuration rather than read out of the design, and
// then PROVED equal to the design's own read data in section 4a.  (Ibex reads
// `CSR.MISA_VALUE hierarchically instead; restating and proving is strictly
// better, because it catches a configuration drift that a hierarchical read
// would silently absorb.)
//
// MISA_VAL, hdl/hazard3_csr.v:405-427, with this configuration's parameters:
//   [31:30] MXL=1, [23] X=1 (Xh3misa), [12] M=1, [8] I=1, [2] C=1, rest 0.
logic [31:0] pre_misa;
logic [31:0] pre_mvendorid;
logic [31:0] pre_marchid;
logic [31:0] pre_mimpid;
logic [31:0] pre_mhartid;
logic [31:0] pre_mconfigptr;

assign pre_misa       = 32'h4080_1104;
assign pre_mvendorid  = 32'h0;                       // MVENDORID_VAL, config.vh:197
assign pre_marchid    = 32'd27;                      // hazard3_csr.v:761
assign pre_mimpid     = cpu.core.csr_u.mimpid_rdata; // :397-402, carries eco_version
assign pre_mhartid    = mhartid_val;                 // :770
assign pre_mconfigptr = 32'h0;                       // MCONFIGPTR_VAL, config.vh:201

// ===========================================================================
// 2.  Which CSR the instruction leaving X is accessing
// ===========================================================================
// INSTRUCTION DECODE, not a copy of the CSR file's write logic:
// hdl/hazard3_core.v:1182 wires csr_u.addr to fd_cir[31:20], the I-type
// immediate of the instruction in the CIR, and d_csr_wen / d_csr_ren are the
// decoder's "this instruction writes / reads a CSR" bits
// (hdl/hazard3_decode.v:506-511, forced to 0 for an invalid or starved slot at
// :558-565).  h3_x_csr_wen / h3_x_csr_addr are declared in h3_commit.svh.
//
// What is deliberately NOT read is `wen` / `wen_m_mode` / `trapreg_update*`,
// the CSR file's own write enables.  Using those would make every "<x> changed
// at a commit point" obligation below tautological -- the trap gate 2 flagged.

logic h3_x_writes_mepc;
logic h3_x_writes_mscratch;
logic h3_x_writes_mtvec;
logic h3_x_writes_mie;

assign h3_x_writes_mepc     = h3_x_csr_wen && (h3_x_csr_addr == H3_CSR_MEPC);
assign h3_x_writes_mscratch = h3_x_csr_wen && (h3_x_csr_addr == H3_CSR_MSCRATCH);
assign h3_x_writes_mtvec    = h3_x_csr_wen && (h3_x_csr_addr == H3_CSR_MTVEC);
// THE ONE IRREGULAR CASE: two write addresses (hdl/hazard3_csr.v:335-341).
assign h3_x_writes_mie      = h3_x_csr_wen &&
    ((h3_x_csr_addr == H3_CSR_MIE) || (h3_x_csr_addr == H3_CSR_MEICONTEXT));
// (h3_x_writes_mstatus and h3_x_writes_mcause are in check/peek/h3_commit.svh.)

logic h3_mepc_may_change;
assign h3_mepc_may_change = h3_trap_entry || (h3_x_advance && h3_x_writes_mepc);

// ---------------------------------------------------------------------------
// 2b.  CHECKABLE CSR ACCESSES
// ---------------------------------------------------------------------------
// The ghost (check/peek/h3_follower.svh) is only meaningful while the
// specification and the DUT agree about what the instruction stream did.  A CSR
// access at an address where they DISAGREE -- one raises an illegal instruction
// and the other does not, or one has a register where the other does not --
// makes the ghost stale.  Ibex clears `has_spec_past` for exactly this reason
// (check/top.sv:470-486).
//
// Ibex uses a DENYLIST.  Hazard3's configuration makes an ALLOWLIST both
// shorter and safer to audit, because divergence runs in BOTH directions here:
//   * Hazard3 implements a custom CSR space the Sail model has never heard of
//     (meiea/meipa/meifa/meipra/meinext/meicontext, msleep, h3misa, pmpcfgm0) --
//     the DUT accepts, Sail raises illegal;
//   * CSR_COUNTER = 0 turns the counter block OFF in the DUT while Sail keeps it
//     ON, and PMP_REGIONS = 0 does the same for pmpcfg/pmpaddr/mseccfg (Sail's
//     stub.sv reports pmp_count = 4) -- the DUT raises illegal, Sail accepts.
// Enumerating what AGREES is therefore the honest way round.
//
// EVERYTHING ELSE clears the ghost.  Over-clearing costs coverage (a vacuous
// Wrap), never soundness; NegNoUncheckableCsr in step 1 is the control that the
// clearing path is reachable at all.
//
// ---------------------------------------------------------------------------
// GATE 5 RE-AUDIT, FROM THE SAIL SIDE (gate 4 flagged that this list had been
// derived from the Hazard3 side only).  The authority is
// riscv_sys_control.sail:17-64's is_CSR_defined, with misa = 0x4080_1104, so
// haveUsrMode() = haveSupMode() = haveNExt() = false and sizeof(xlen) == 32.
// Note that ext_is_CSR_defined is `= false` in every clause
// (riscv_csr_ext.sail:17), so that match IS the complete legal set -- there is no
// extension escape hatch.  All 16 entries survive, but TWO JUSTIFICATIONS WERE
// WRONG AND ARE CORRECTED HERE:
//
//  * MCOUNTEREN (0x306).  Gate 4 said it was in the list because "the DUT reads
//    it as constant 0".  IT DOES NOT: hdl/hazard3_csr.v:991 guards the whole
//    decode with `if (CSR_COUNTER && U_MODE)`, both 0 here, so Hazard3 raises an
//    ILLEGAL INSTRUCTION for 0x306.  It stays in the list because Sail does the
//    same -- riscv_sys_control.sail:32, `0x306 => p == Machine & haveUsrMode()`,
//    and haveUsrMode() is false.  Both sides trap, so the two agree, and that is
//    a better reason than the one gate 4 gave.
//  * MSTATUSH (0x310).  Sail defines it for RV32 (riscv_sys_control.sail:34) and
//    readCSR returns the raw `mstatush` register, which nothing in the model ever
//    writes (its write case, riscv_insts_zicsr.sail:93, is literally commented
//    "ignore writes for now").  That would be an unconstrained free value -- and
//    it is not, only because spec/spec_api.sv:219 pins `.mstatush_in('{bits:
//    32'b0})`.  Hazard3 reads 0x310 as zero (hazard3_csr.v:804-806, decoded with
//    no rdata assignment).  So 0x310 is comparable ONLY because of that tie-off;
//    if it is ever removed, 0x310 must leave this list.
//
// What the audit confirms about the EXCLUSIONS, and the reason the list is an
// allowlist: Sail declares legal, in this configuration, four pmpcfg registers
// (0x3A0-0x3A3), sixteen pmpaddr registers (0x3B0-0x3BF), mseccfg and mseccfgh
// (0x747/0x757), mcycle/minstret and their high halves (0xB00/0xB02/0xB80/0xB82)
// and mcountinhibit (0x320) -- twenty-five addresses Hazard3 traps because
// PMP_REGIONS = CSR_COUNTER = 0.  In particular sail_plat_enable_pmp = 0 has NO
// effect on CSR legality: is_CSR_defined consults only sys_pmp_count() and
// sys_pmp_max_count(), which spec/stub.sv:84-85 report as 4 and 16.  And
// mseccfg's clause carries no PMP condition at all.  A denylist would have had
// to enumerate all of that correctly; the allowlist fails safe.
//
// mtval (0x343) and mip (0x344) are the two addresses where both sides accept
// the access but only Sail keeps the written value.  They are in the list and
// NOT ghosted: the specification is handed constant 0 / the DUT's mip as their
// pre-state on every query, so a read agrees, and its post-state is discarded by
// check/h3_top.sv -- the documented non-comparison, re-seeded from the DUT.
// The five identification CSRs (0xf11-0xf15) are read-only on both sides
// (Sail: csrAccess == 0b11; Hazard3: match_mro, hazard3_csr.v:735), so a CSRRW
// to them traps on both.
logic h3_x_csr_access;
assign h3_x_csr_access = cpu.core.d_csr_wen || cpu.core.d_csr_ren;

logic h3_x_csr_checkable;
assign h3_x_csr_checkable =
    h3_x_csr_addr == H3_CSR_MSTATUS    ||
    h3_x_csr_addr == H3_CSR_MSTATUSH   ||
    h3_x_csr_addr == H3_CSR_MISA       ||
    h3_x_csr_addr == H3_CSR_MIE        ||
    h3_x_csr_addr == H3_CSR_MTVEC      ||
    h3_x_csr_addr == H3_CSR_MCOUNTEREN ||
    h3_x_csr_addr == H3_CSR_MSCRATCH   ||
    h3_x_csr_addr == H3_CSR_MEPC       ||
    h3_x_csr_addr == H3_CSR_MCAUSE     ||
    h3_x_csr_addr == H3_CSR_MTVAL      ||
    h3_x_csr_addr == H3_CSR_MIP        ||
    h3_x_csr_addr == H3_CSR_MVENDORID  ||
    h3_x_csr_addr == H3_CSR_MARCHID    ||
    h3_x_csr_addr == H3_CSR_MIMPID     ||
    h3_x_csr_addr == H3_CSR_MHARTID    ||
    h3_x_csr_addr == H3_CSR_MCONFIGPTR;

// "This query leaves the ghost trustworthy."
logic h3_x_query_checkable;
assign h3_x_query_checkable = !h3_x_csr_access || h3_x_csr_checkable;

// ---------------------------------------------------------------------------
// 3. One-cycle history (this flow has no $past in continuous assignments)
// ---------------------------------------------------------------------------
// Synchronous, and deliberately NOT reset-sensitive: h3_abs_past_valid is low
// for the first two cycles, so no property below is evaluated across the reset
// edge.  (h3_past_trap_entry / h3_past_trap_exit /
// h3_past_x_advance_writes_{mstatus,mcause} are declared and driven in
// check/peek/h3_commit.svh; the two files share them rather than duplicating.)

// AN ARBITRARY BUT CONSTANT REGISTER INDEX.  Same device as mhartid_val
// (check/h3_core_common.svh): a free wire sampled during reset and held, so the
// solver still chooses the register -- the register-file obligation is "for
// every register index" -- but it cannot change its mind mid-trace.  This is
// what makes that obligation ONE property with 32 bits of history instead of 31
// properties with 1024.
logic [4:0]  h3_reg_probe_free;   // undriven -> free every cycle
logic [4:0]  h3_reg_probe;

initial h3_reg_probe = 5'h0;

always @ (posedge clk_i) begin
    h3_reg_probe <= rst_ni ? h3_reg_probe : h3_reg_probe_free;
end

logic [31:0] pre_reg_probe;
assign pre_reg_probe = pre_regs[h3_reg_probe];

logic        h3_abs_past_valid;
logic [31:0] h3_past_pre_mepc;
logic [31:0] h3_past_pre_mscratch;
logic [31:0] h3_past_pre_mtvec;
logic [31:0] h3_past_pre_mie;
logic [31:0] h3_past_pre_mcause;
logic [31:0] h3_past_pre_mstatus;
logic [31:0] h3_past_pre_reg_probe;
logic        h3_past_any_commit;
logic        h3_past_retire_writes_mepc;
logic        h3_past_x_advance_writes_mscratch;
logic        h3_past_x_advance_writes_mtvec;
logic        h3_past_x_advance_writes_mie;

initial begin
    h3_abs_past_valid                 = 1'b0;
    h3_past_pre_mepc                  = 32'h0;
    h3_past_pre_mscratch              = 32'h0;
    h3_past_pre_mtvec                 = 32'h0;
    h3_past_pre_mie                   = 32'h0;
    h3_past_pre_mcause                = 32'h0;
    h3_past_pre_mstatus               = 32'h0;
    h3_past_pre_reg_probe             = 32'h0;
    h3_past_any_commit                = 1'b0;
    h3_past_retire_writes_mepc        = 1'b0;
    h3_past_x_advance_writes_mscratch = 1'b0;
    h3_past_x_advance_writes_mtvec    = 1'b0;
    h3_past_x_advance_writes_mie      = 1'b0;
end

always @ (posedge clk_i) begin
    h3_abs_past_valid                 <= rst_ni;
    h3_past_pre_mepc                  <= pre_mepc;
    h3_past_pre_mscratch              <= pre_mscratch;
    h3_past_pre_mtvec                 <= pre_mtvec;
    h3_past_pre_mie                   <= pre_mie;
    h3_past_pre_mcause                <= pre_mcause;
    h3_past_pre_mstatus               <= pre_mstatus;
    h3_past_pre_reg_probe             <= pre_reg_probe;
    h3_past_any_commit                <= h3_commit_any;
    h3_past_retire_writes_mepc        <= h3_x_advance && h3_x_writes_mepc;
    h3_past_x_advance_writes_mscratch <= h3_x_advance && h3_x_writes_mscratch;
    h3_past_x_advance_writes_mtvec    <= h3_x_advance && h3_x_writes_mtvec;
    h3_past_x_advance_writes_mie      <= h3_x_advance && h3_x_writes_mie;
end

// ===========================================================================
// 4.  THE OBLIGATIONS -- "is this abstraction right?"
// ===========================================================================
// Three families, for every ghosted register:
//   (i)   STABLE BETWEEN COMMITS -- on a cycle that was not a commit point,
//         pre_<x> is unchanged.  This is what lets the specification's answer,
//         produced at commit point N, still be comparable at commit point N+1.
//   (ii)  CHANGES ONLY FOR A NAMED ARCHITECTURAL REASON -- strictly stronger.
//   (iii) THE ASSEMBLY IS THE ARCHITECTURAL VALUE -- pre_<x> equals what the
//         CSR file itself returns for a read of <x>.

// --- 4a. (iii) the assembly obligations -------------------------------------
// hdl/hazard3_csr.v:740-745: `rdata` is a pure combinational function of `addr`
// (an always @(*) case with a zero default), evaluated whether or not a read is
// enabled, so conditioning on the address alone is enough.  Nothing here reads
// a read-ENABLE, which keeps these non-vacuous.
//
// This is the sharpest available check that the harness grabbed the right bits:
// mcause's 27-bit zero fill, mtvec's WARL'd bit 1 and its mtvec_reg[0] MODE
// bit, and mstatus's five scattered fields are each restated independently
// above and then proved equal to the design's own read data.
logic h3_abs_mepc_is_rdata;
logic h3_abs_mscratch_is_rdata;
logic h3_abs_mtvec_is_rdata;
logic h3_abs_mie_is_rdata;
logic h3_abs_mcause_is_rdata;
logic h3_abs_mstatus_is_rdata;
logic h3_abs_misa_is_rdata;
logic h3_abs_ids_are_rdata;

assign h3_abs_mepc_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MEPC)     || (cpu.core.csr_u.rdata == pre_mepc);
assign h3_abs_mscratch_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MSCRATCH) || (cpu.core.csr_u.rdata == pre_mscratch);
assign h3_abs_mtvec_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MTVEC)    || (cpu.core.csr_u.rdata == pre_mtvec);
assign h3_abs_mie_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MIE)      || (cpu.core.csr_u.rdata == pre_mie);
assign h3_abs_mcause_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MCAUSE)   || (cpu.core.csr_u.rdata == pre_mcause);
assign h3_abs_mstatus_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MSTATUS)  || (cpu.core.csr_u.rdata == pre_mstatus);
assign h3_abs_misa_is_rdata =
    (cpu.core.csr_u.addr != H3_CSR_MISA)     || (cpu.core.csr_u.rdata == pre_misa);

// The four identification CSRs the specification is handed as constants.  If
// the configuration ever changes MVENDORID_VAL / MCONFIGPTR_VAL, or Hazard3's
// architecture ID moves, this fails instead of silently mis-specifying.
assign h3_abs_ids_are_rdata =
    ((cpu.core.csr_u.addr != H3_CSR_MVENDORID)  || (cpu.core.csr_u.rdata == pre_mvendorid))  &&
    ((cpu.core.csr_u.addr != H3_CSR_MARCHID)    || (cpu.core.csr_u.rdata == pre_marchid))    &&
    ((cpu.core.csr_u.addr != H3_CSR_MIMPID)     || (cpu.core.csr_u.rdata == pre_mimpid))     &&
    ((cpu.core.csr_u.addr != H3_CSR_MHARTID)    || (cpu.core.csr_u.rdata == pre_mhartid))    &&
    ((cpu.core.csr_u.addr != H3_CSR_MCONFIGPTR) || (cpu.core.csr_u.rdata == pre_mconfigptr));

// mtval really is hardwired to zero: the abstraction's constant is the design's
// behaviour, not an assumption about it.
logic h3_abs_mtval_is_zero;
assign h3_abs_mtval_is_zero =
    (cpu.core.csr_u.addr != H3_CSR_MTVAL)    || (cpu.core.csr_u.rdata == 32'h0);

// ... and mcounteren's three flops, which exist, can never be set.
logic h3_abs_mcounteren_is_zero;
assign h3_abs_mcounteren_is_zero =
    !cpu.core.csr_u.mcounteren_cy && !cpu.core.csr_u.mcounteren_tm &&
    !cpu.core.csr_u.mcounteren_ir;

// The harness's own instruction-size decode agrees with the core's PC
// increment whenever there is an instruction to size.  (pc_seq_next also
// carries a Zcmp micro-op term, dead here because EXTENSION_ZCMP = 0.)
logic h3_pre_nextpc_matches_seq_next;
assign h3_pre_nextpc_matches_seq_next =
    cpu.core.d_starved || (pre_nextpc == cpu.core.decode_u.pc_seq_next);

// --- 4b. (i) stable between commits -----------------------------------------
logic h3_mepc_stable_between_commits;
logic h3_mscratch_stable_between_commits;
logic h3_mtvec_stable_between_commits;
logic h3_mie_stable_between_commits;
logic h3_mcause_stable_between_commits;
logic h3_mstatus_stable_between_commits;

assign h3_mepc_stable_between_commits =
    !h3_abs_past_valid || h3_past_any_commit || (pre_mepc == h3_past_pre_mepc);
assign h3_mscratch_stable_between_commits =
    !h3_abs_past_valid || h3_past_any_commit || (pre_mscratch == h3_past_pre_mscratch);
assign h3_mtvec_stable_between_commits =
    !h3_abs_past_valid || h3_past_any_commit || (pre_mtvec == h3_past_pre_mtvec);
assign h3_mie_stable_between_commits =
    !h3_abs_past_valid || h3_past_any_commit || (pre_mie == h3_past_pre_mie);
assign h3_mcause_stable_between_commits =
    !h3_abs_past_valid || h3_past_any_commit || (pre_mcause == h3_past_pre_mcause);
assign h3_mstatus_stable_between_commits =
    !h3_abs_past_valid || h3_past_any_commit || (pre_mstatus == h3_past_pre_mstatus);

// --- 4c. (ii) changes only for a named architectural reason ------------------
// Note which terms are ABSENT, because each absence is a claim:
//   mscratch / mtvec / mie -- NO trap term at all.  The trap machinery writes
//       mepc, mcause and mstatus and nothing else (hdl/hazard3_csr.v:181-182,
//       :221-233, :312-313, :368-370); if trap entry ever touched one of these
//       three, the obligation would fail.
//   mepc / mcause -- trap ENTRY but not trap EXIT.  MRET must not move either.
//   mstatus -- all three events, which is the positive half of the gate-3 MRET
//       decision, now stated over the whole register and not just the MIE bit.
logic h3_mepc_change_has_cause;
logic h3_mscratch_change_has_cause;
logic h3_mtvec_change_has_cause;
logic h3_mie_change_has_cause;
logic h3_mcause_change_has_cause_full;
logic h3_mstatus_change_has_cause;

assign h3_mepc_change_has_cause =
    !h3_abs_past_valid || (pre_mepc == h3_past_pre_mepc) ||
    h3_past_trap_entry || h3_past_retire_writes_mepc;

assign h3_mscratch_change_has_cause =
    !h3_abs_past_valid || (pre_mscratch == h3_past_pre_mscratch) ||
    h3_past_x_advance_writes_mscratch;

assign h3_mtvec_change_has_cause =
    !h3_abs_past_valid || (pre_mtvec == h3_past_pre_mtvec) ||
    h3_past_x_advance_writes_mtvec;

assign h3_mie_change_has_cause =
    !h3_abs_past_valid || (pre_mie == h3_past_pre_mie) ||
    h3_past_x_advance_writes_mie;

assign h3_mcause_change_has_cause_full =
    !h3_abs_past_valid || (pre_mcause == h3_past_pre_mcause) ||
    h3_past_trap_entry || h3_past_x_advance_writes_mcause;

assign h3_mstatus_change_has_cause =
    !h3_abs_past_valid || (pre_mstatus == h3_past_pre_mstatus) ||
    h3_past_trap_entry || h3_past_trap_exit || h3_past_x_advance_writes_mstatus;

// --- 4d. The register file ---------------------------------------------------
// The architectural value of the probed register changes ONLY on a cycle where
// the write port is committing a write to that register.  Note the cause is the
// CURRENT cycle, not the past one: pre_regs forwards the in-flight write, so the
// value moves on the cycle the write port asserts and then stays put when the
// write lands in `mem` at that same edge.  That the forwarding really does make
// it stay put is half of what this obligation proves.
//
// Together with gate 3's RegWriteAtRetire (h3_reg_write -> h3_retire) this says
// the architectural register file changes only at a retirement that names that
// register -- the register-file half of the commit point, which gate 3 could
// only state about the write port and not about the file.
logic h3_reg_change_has_write;
assign h3_reg_change_has_write =
    !h3_abs_past_valid || (pre_reg_probe == h3_past_pre_reg_probe) ||
    (h3_reg_write && cpu.core.xm_rd == h3_reg_probe);

// x0 is never anything but zero, whatever the write port says.  (m_reg_wen is
// already gated on |xm_rd at hdl/hazard3_core.v:1510, so this is cheap.)
logic h3_reg_x0_zero;
assign h3_reg_x0_zero = pre_regs[0] == 32'h0;

// --- 4e. Well-formedness -----------------------------------------------------
// MEPC_MASK = {30{1'b1}, |EXTENSION_C, 1'b0} (hdl/hazard3_csr.v:303), so with
// EXTENSION_C = 1 bit 0 is always 0 and bit 1 is writable.  A cheap check that
// the register we grabbed really is mepc and not something next to it.
logic h3_mepc_aligned;
assign h3_mepc_aligned = pre_mepc[0] == 1'b0;

// mtvec's reserved mode bit is WARL'd to zero, so the architectural value can
// only ever select direct (0) or vectored (1) mode.
logic h3_mtvec_mode_legal;
assign h3_mtvec_mode_legal = pre_mtvec[1] == 1'b0;

// --- gate 6: the WARL policy the SAIL CONFIGURATION claims Hazard3 has ------
// sail-riscv-h3 parameterises legalize_tvec on sys_tvec_wmask(), and
// spec/stub.sv sets that to Hazard3's MTVEC_WMASK = 32'hfffffffd
// (hdl/hazard3_config.vh:253, not overridden in h3_core_common.svh).  Editing
// the specification is the one move in this project that can hide a real bug,
// so the claim is CHECKED against the DUT rather than trusted, in two halves.
//
// UNWRITABLE HALF, here: the STORED reserved MODE bit is always zero.  This is
// what makes "bit 1 unwritable, reads 0" the whole truth rather than a readback
// that masks a stored one -- with MTVEC_INIT[1] = 0 and MTVEC_WMASK[1] = 0 the
// flop can never leave 0, and so the model's "unwritable bits keep their
// previous value" and the DUT's "unwritable bit reads 0" agree.
// Stated over mtvec_reg and NOT over pre_mtvec: pre_mtvec[1] is the literal
// 1'b0 of the abstraction, which is why h3_mtvec_mode_legal below is vacuous on
// its own and gets its content from AbsMtvecIsRdata.
//
// WRITABLE HALF: the three step-1 controls NegMtvecBaseLowZero /
// NegMtvecModeNeverVectored / NegMtvecModeNeverCleared, each of which must
// FAIL, plus WrapMtvec itself.
logic h3_mtvec_reserved_bit_hardwired;
assign h3_mtvec_reserved_bit_hardwired = cpu.core.csr_u.mtvec_reg[1] == 1'b0;

// mie's reserved bits are held clear by MIE_WMASK (hdl/hazard3_csr.v:322), so
// only msie/mtie/meie can ever be set.  If this failed, the Sail comparison of
// mie would be comparing bits Sail does not model.
logic h3_mie_reserved_zero;
assign h3_mie_reserved_zero = (pre_mie & ~32'h0000_0888) == 32'h0;

// ---------------------------------------------------------------------------
// 5. Non-vacuity controls (step 1 of thm/hazard3.proof -- these MUST FAIL)
// ---------------------------------------------------------------------------
// (ii) is only worth anything if the register can move at all, and if every
// disjunct is load-bearing.  The first three are gate 2's, kept; the rest are
// the gate-4 generalisation -- one "this register never moves" per ghosted
// register, plus the register file and the uncheckable-CSR path.
logic h3_neg_mepc_never_moves;
assign h3_neg_mepc_never_moves =
    !h3_abs_past_valid || (pre_mepc == h3_past_pre_mepc);

logic h3_neg_mepc_only_trap;
assign h3_neg_mepc_only_trap =
    !h3_abs_past_valid || (pre_mepc == h3_past_pre_mepc) || h3_past_trap_entry;

logic h3_neg_mepc_only_csr;
assign h3_neg_mepc_only_csr =
    !h3_abs_past_valid || (pre_mepc == h3_past_pre_mepc) || h3_past_retire_writes_mepc;

logic h3_neg_mscratch_never_moves;
assign h3_neg_mscratch_never_moves =
    !h3_abs_past_valid || (pre_mscratch == h3_past_pre_mscratch);

logic h3_neg_mtvec_never_moves;
assign h3_neg_mtvec_never_moves =
    !h3_abs_past_valid || (pre_mtvec == h3_past_pre_mtvec);

logic h3_neg_mie_never_moves;
assign h3_neg_mie_never_moves =
    !h3_abs_past_valid || (pre_mie == h3_past_pre_mie);

logic h3_neg_mcause_never_moves;
assign h3_neg_mcause_never_moves =
    !h3_abs_past_valid || (pre_mcause == h3_past_pre_mcause);

logic h3_neg_mstatus_never_moves;
assign h3_neg_mstatus_never_moves =
    !h3_abs_past_valid || (pre_mstatus == h3_past_pre_mstatus);

// --- gate 6: Hazard3 really uses the WARL freedom Ibex's Sail policy denied --
// Each MUST FAIL, and each failure refutes one clause of lowRISC's
// `Mk_Mtvec(v[31..8] @ 0x01)` -- "256 byte aligned, always vectored" -- as a
// description of THIS core.  Together they are why reverting legalize_tvec to
// upstream's WARL form is a fix and not a convenience: if all three PROVED,
// Ibex's policy would describe Hazard3 too and there would be nothing to fix.
//
// (a) BASE bits below bit 8 are writable, so mtvec is NOT 256-byte aligned.
logic h3_neg_mtvec_base_low_zero;
assign h3_neg_mtvec_base_low_zero = pre_mtvec[7:2] == 6'h0;

// (b) MODE can be made vectored, and
logic h3_neg_mtvec_mode_never_vectored;
assign h3_neg_mtvec_mode_never_vectored = pre_mtvec[0] == 1'b0;

// (c) ... written back to direct.  MODE is a writable field in both
//     directions, not hardwired to vectored as lowRISC's `@ 0x01` has it.
logic h3_neg_mtvec_mode_never_cleared;
assign h3_neg_mtvec_mode_never_cleared =
    !h3_abs_past_valid || !h3_past_pre_mtvec[0] || pre_mtvec[0];

// (d) mcause moves for a reason OTHER than trap entry, i.e. a software CSR
//     write really can set it.  h3_mcause_change_has_cause_full with the
//     CSR-write disjunct deleted.  This is the non-vacuity control for
//     legalize_mcause: if mcause could only ever be written by hardware, the
//     legalizer would never run and WrapMcause would say nothing about it.
logic h3_neg_mcause_never_csr_written;
assign h3_neg_mcause_never_csr_written =
    !h3_abs_past_valid || (pre_mcause == h3_past_pre_mcause) || h3_past_trap_entry;

// The MRET decision restated over the whole of mstatus:
// h3_mstatus_change_has_cause WITHOUT the trap-exit term must fail, or the
// trap-exit term is dead machinery.
logic h3_neg_mstatus_no_trap_exit;
assign h3_neg_mstatus_no_trap_exit =
    !h3_abs_past_valid || (pre_mstatus == h3_past_pre_mstatus) ||
    h3_past_trap_entry || h3_past_x_advance_writes_mstatus;

// The probed register is never written, i.e. 4d is vacuous.
logic h3_neg_reg_probe_never_moves;
assign h3_neg_reg_probe_never_moves =
    !h3_abs_past_valid || (pre_reg_probe == h3_past_pre_reg_probe);

// A CSR access at an address the harness calls uncheckable is reachable.  If
// this PROVED, h3_x_csr_checkable would be constantly true and the ghost's
// clearing path would be dead code.
logic h3_neg_no_uncheckable_csr;
assign h3_neg_no_uncheckable_csr = !h3_x_csr_access || h3_x_csr_checkable;

// ---------------------------------------------------------------------------
// 6. Flattening sanity check
// ---------------------------------------------------------------------------
// ./probe_undriven.sh reports cpu.core.csr_u.irq{,_software,_timer} as
// "used but has no driver", which would be alarming: it would mean the CSR
// file reads a DIFFERENT free signal from the top-level `irq`, and every
// future constraint on `irq` would silently miss.  This property decides it.
// (It must hold.  If it ever fails, nothing downstream of gate 2 is sound.)
logic h3_irq_alias_ok;
assign h3_irq_alias_ok =
    (cpu.core.csr_u.irq          == irq)      &&
    (cpu.core.csr_u.irq_software == soft_irq) &&
    (cpu.core.csr_u.irq_timer    == timer_irq);
