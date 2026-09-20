// ===========================================================================
// check/peek/h3_mem.svh -- THE DATA-SIDE MEMORY VIEW.  Gate 5 of the bring-up.
//
// `include`d by check/h3_core_common.svh AFTER h3_abs.svh (it uses the commit
// events and the abstraction) and BEFORE h3_follower.svh (the follower latches
// what this file exposes), so it is present identically in BOTH models.
//
// This is the Hazard3 analogue of Ibex's check/peek/mem.sv, and of the parts of
// check/protocol/mem.sv that are about DATA rather than protocol.  The protocol
// half does not port: Hazard3's own ahbl_slave_assumptions.v (gate 1) already
// constrains the bus, with MAX_BUS_STALL = -1, and Ibex's TIME_LIMIT / StrictGnt
// / StrictRValid fairness bounds are therefore not needed and not used.
// ===========================================================================
//
// WHY THIS FILE IS SO MUCH SMALLER THAN IBEX'S
// ---------------------------------------------------------------------------
// Ibex's peek/mem.sv is 136 lines, of which about 100 exist to cope with ONE
// thing: a misaligned access is split into two bus beats, so a memory
// instruction can have a first and a second granule, an "early" response while
// it is still in ID/EX and a "late" response in WB, and three separate
// instantiations of a duplicated LSU (alt_lsu) to reconstruct the load result at
// each of those points.  Hazard3 TRAPS misaligned accesses
// (hdl/hazard3_core.v:613-616, x_unaligned_addr -> EXCEPT_LOAD_ALIGN /
// EXCEPT_STORE_ALIGN), so:
//
//   * there is never a second granule -- MemNoSecondGranule states it;
//   * there is at most one bus transfer per instruction, so "first/second",
//     "early/late" and the outstanding-response counter all disappear;
//   * alt_lsu disappears with them.
//
// WHAT REPLACES THEM IS THE AHB5 TWO-PHASE STRUCTURE
// ---------------------------------------------------------------------------
// Ibex's memory interface presents a request and a response as separate events
// with an explicit grant.  AHB5 has an ADDRESS phase and a DATA phase, one cycle
// apart, and the plan (section 1) said to compare address/control at the address
// phase and latch the write-data comparison one cycle rather than trying to
// reconstruct a single-cycle view.  That is what happens here, and Hazard3's
// stall logic makes the alignment exact rather than approximate:
//
//     x_stall contains `bus_aph_req_d && !bus_aph_ready_d`  (core.v:484)
//
// so an instruction with a memory operation CANNOT leave stage X until its
// address phase has been accepted.  Since h3_x_progress -> !x_stall, the address
// phase of a memory instruction is accepted on EXACTLY the cycle the
// specification is queried about it.  MemAphAtProgress proves it.  The
// consequence is worth stating plainly, because it is the single biggest
// simplification this port gets over the reference:
//
//     Ibex needs `FstEnd: spec_en & spec_mem_en |-> mem_gnt_fst_d`, a separate
//     obligation that the request the specification asked for actually got out
//     before the instruction retired.  In Hazard3 that is the same cycle as the
//     request itself, so Load/Store's `En` and `End` collapse into one property.
//
// The write DATA is the one thing that is not available at the address phase:
// hdl/hazard3_core.v:1435-1441 drives bus_wdata_d from xm_memop and m_wdata,
// i.e. from stage M, one cycle later.  So the write-data comparison is made
// against the follower's latched copy of what the specification said, during the
// data phase -- which is the "latch the write data comparison one cycle" the
// plan asked for.
// ===========================================================================

// ---------------------------------------------------------------------------
// 0.  AHB5 transfer sizes (hdl/hazard3_core.v uses the standard encoding)
// ---------------------------------------------------------------------------
localparam [2:0] H3_HSIZE_BYTE  = 3'd0;
localparam [2:0] H3_HSIZE_HWORD = 3'd1;
localparam [2:0] H3_HSIZE_WORD  = 3'd2;

// ===========================================================================
// 1.  THE DUT's DATA-SIDE BUS, AT THE ADDRESS PHASE
// ===========================================================================
// These are the core's own D-side port signals (hdl/hazard3_core.v:46-58), the
// same wires hazard3_cpu_1port.v muxes onto haddr/hsize/hwrite/hwdata.  Reading
// them here rather than the top-level AHB wires is deliberate: the top-level
// wires carry instruction fetches and (in a configuration with a debug module)
// system-bus accesses too, and the goals below are about the DATA side only.
// H3_BUS_DPH_MUTEX (thm/hazard3.proof, gate 2) is what says the two cannot be
// confused.

logic h3_mem_aph_req;
logic h3_mem_aph_rdy;
assign h3_mem_aph_req = cpu.core.bus_aph_req_d;
assign h3_mem_aph_rdy = cpu.core.bus_aph_ready_d;

// THE EVENT: a data-side address phase is accepted this cycle.  This is the
// Hazard3 analogue of Ibex's `mem_gnt_fst_d` -- "the memory request this
// instruction makes has gone out".
logic h3_mem_aph;
assign h3_mem_aph = h3_mem_aph_req && h3_mem_aph_rdy;

logic        h3_mem_write;
logic [31:0] h3_mem_addr;
logic [2:0]  h3_mem_size;
assign h3_mem_write = cpu.core.bus_hwrite_d;
assign h3_mem_addr  = cpu.core.bus_haddr_d;
assign h3_mem_size  = cpu.core.bus_hsize_d;

// The word address, which is what the specification produces.  Sail's
// checked_mem_read / checked_mem_write align the physical address before calling
// read_ram / write_ram (riscv_mem.sail: `let aligned = [paddr with 1..0 = 0b00]`),
// so read_ram_sail_invoke_arg_1 is ALWAYS word-aligned, while Hazard3 puts the
// byte address on HADDR and lets HSIZE select the lane.  The comparison is
// therefore between the spec's aligned address and this.
logic [31:0] h3_mem_addr_word;
assign h3_mem_addr_word = {h3_mem_addr[31:2], 2'b00};

// The byte lanes the transfer touches, in the 4-bit form the specification
// produces (write_ram_sail_invoke_arg_3).  AHB5 has no byte-enable signal: the
// lanes are implied by HSIZE and the low address bits, which is what this
// reconstructs.  Misaligned transfers are impossible (x_unaligned_addr traps
// before the address phase is raised, core.v:779-788), so the halfword case only
// has to consider bit 1 and the word case none at all.
logic [3:0] h3_mem_be;
always_comb begin
    case (h3_mem_size)
        H3_HSIZE_WORD:  h3_mem_be = 4'b1111;
        H3_HSIZE_HWORD: h3_mem_be = h3_mem_addr[1] ? 4'b1100 : 4'b0011;
        default:        h3_mem_be = 4'b0001 << h3_mem_addr[1:0];
    endcase
end

// ===========================================================================
// 2.  THE DATA PHASE
// ===========================================================================
// hdl/hazard3_core.v:1136 -- m_dphase_in_flight = xm_memop is a real, non-AMO
// memory operation.  It is the RTL's own "the instruction in M is waiting on the
// bus", and it is what m_bus_stall (:1387) is built from.
logic h3_mem_dph_active;
assign h3_mem_dph_active = cpu.core.m_dphase_in_flight;

// The data phase completes / errors.  hdl/hazard3_cpu_1port.v:330-331:
//   core_dph_ready_d = bus_active_dph_d && hready
//   core_dph_err_d   = bus_active_dph_d && hresp
// Note the asymmetry the author documents at :327-329: a D-side error is
// reported even when !hready, which is the FIRST phase of the two-phase AHB5
// error response, and it is on that cycle that the core captures the exception.
logic h3_mem_dph_end;
logic h3_mem_dph_err;
assign h3_mem_dph_end = cpu.core.bus_dph_ready_d;
assign h3_mem_dph_err = cpu.core.bus_dph_err_d;

// The write data the core is driving, and the read data the bus is returning.
logic [31:0] h3_mem_wdata;
logic [31:0] h3_mem_rdata;
assign h3_mem_wdata = cpu.core.bus_wdata_d;
assign h3_mem_rdata = cpu.core.bus_rdata_d;

// ===========================================================================
// 3.  THE READ DATA HANDED TO THE SPECIFICATION
// ===========================================================================
// THE PROBLEM.  The specification is asked its question at the X->M handoff and
// answers in one step, so it needs the loaded word THEN.  Hazard3's address
// phase is accepted on that same cycle, but the data phase -- and therefore
// HRDATA -- is at least one cycle later.  The specification cannot be given a
// value that does not exist yet.
//
// THE ANSWER, WHICH IS IBEX'S (check/peek/mem.sv:32-44).  Leave the value the
// specification is told FREE, and constrain the BUS to return it.  h3_spec_rdata
// below is undriven, so `setundef -undriven -anyseq` makes it a free input; the
// solver chooses it at the query cycle, the follower latches it, and
// MemRdataIsSpecData (section 5) makes the memory hand the core exactly that
// word when the data phase completes.
//
// WHY THAT IS SOUND, AND NOT A WEAKENING.  hrdata is an unconstrained free input
// in this harness -- BRINGUP.md's environment table says so, and Hazard3's own
// ahbl_slave_assumptions.v never mentions it, because it is data and not
// protocol.  So for every trace of the unconstrained model there is a trace of
// the constrained model with the same hrdata: pick h3_spec_rdata at the query
// cycle to be the hrdata the trace was going to produce.  The "for all memory
// contents" quantifier is preserved exactly; what changes is only WHICH free
// wire the solver makes the choice on.  It is a renaming, not a restriction.
//
// It DOES add one AIGER constraint (C: 5 -> 6), and it is therefore in
// BRINGUP.md's assumption list with this justification.  The alternative --
// driving hrdata structurally -- was rejected because hrdata is shared with the
// instruction-fetch port (hdl/hazard3_cpu_1port.v:318-319) and driving it would
// constrain fetches too.  The constraint below does not, because it only fires
// on a cycle where the D-side owns the data phase, and BusDphMutex (gate 2)
// proves the I-side does not.
logic [31:0] h3_spec_rdata;   // UNDRIVEN -> free.  check/h3_top.sv feeds it to
                              // spec_api_i.mem_read_fst_rdata_i.

// ===========================================================================
// 4.  WHICH INSTRUCTION OWNS THE DATA PHASE
// ===========================================================================
// At most one data phase is in flight (there is one D-side port and m_bus_stall
// holds the instruction in M until it completes), and the instruction that owns
// it is the one in M -- which is the one the follower is following.  So "this
// instruction's data phase" needs no tag: it is h3_fol_valid && h3_mem_dph_active,
// and FollowerOwnsDphase (thm/hazard3.proof) is the obligation that the follower
// really is occupied whenever a data phase is in flight.
//
// h3_mem_fault is the event at the centre of this gate: the in-flight
// instruction has just been told its access faulted.
logic h3_mem_fault;
assign h3_mem_fault = h3_mem_dph_err;

// ===========================================================================
// 5.  NON-VACUITY SUPPORT (step 1 of thm/hazard3.proof -- these MUST FAIL)
// ===========================================================================
// If the DUT never makes a data-side request, every memory goal is vacuous.
logic h3_neg_never_mem_aph;
assign h3_neg_never_mem_aph = !h3_mem_aph;

logic h3_neg_never_mem_read;
assign h3_neg_never_mem_read = !(h3_mem_aph && !h3_mem_write);

logic h3_neg_never_mem_write;
assign h3_neg_never_mem_write = !(h3_mem_aph && h3_mem_write);

// The bus fault is reachable.  This is the measurement behind the whole
// late-exception story, and gate 4's NegFollowerExceptExact was its first
// symptom.  If it ever PROVED, everything in section 6 of h3_goals.svh would be
// dead machinery and FollowerExceptExact would be true for the wrong reason.
logic h3_neg_never_mem_fault;
assign h3_neg_never_mem_fault = !h3_mem_fault;
