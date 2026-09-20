// Hazard3 formal harness, FULL model (build/all.aig).
//
//   core + bus environment + Sail specification instance
//
// The core and its environment live in check/h3_core_common.svh, which is
// shared byte-for-byte with check/h3_core_top.sv (build/core.aig).  The only
// thing this file adds is the Sail `spec_api` instance -- which, as of gate 4,
// is CONNECTED: its inputs come from the abstraction function and its outputs
// feed the follower and the ghost.

`default_nettype wire

module top (
    input logic clk_i
);

// ---------------------------------------------------------------------------
// Core + bus/IRQ environment + lemma support wires (shared with core.aig)
// ---------------------------------------------------------------------------
`include "h3_core_common.svh"

// ---------------------------------------------------------------------------
// Sail specification instance  (build/all.aig ONLY)
// ---------------------------------------------------------------------------
// GATE 4: the specification is now CONNECTED.  Until this gate every input of
// spec_api_i was free, so the Sail model was structurally unreachable from every
// property and build/all.aig said exactly what build/core.aig said.  From here
// on the specification is a function of the core's architectural state, which
// is what makes the correctness goals of gate 5 possible to state at all.
//
// Everything below is wiring.  The abstraction that decides WHAT the
// specification sees is check/peek/h3_abs.svh (the pre_* signals); the
// machinery that decides WHEN it is asked, and what happens to the answer, is
// check/peek/h3_follower.svh.  Both live in check/h3_core_common.svh and are
// therefore in build/core.aig too, where the `spec_*` outputs below are simply
// free -- see the h3_follower.svh header for why that is the right split.

localparam int unsigned SPEC_PMP_REGIONS = 4; // spec/stub.sv hardwires pmp_count = 4

// --- mode ------------------------------------------------------------------
// spec/main.sail:37.  h3_spec_mode is the same choice made in plain bits inside
// the shared harness, because t_MainMode exists only in this model.
t_MainMode spec_main_mode;

always_comb begin
    case (h3_spec_mode)
        H3_MAIN_IRQ:   spec_main_mode = MAIN_IRQ;
        H3_MAIN_IFERR: spec_main_mode = MAIN_IFERR;
        default:       spec_main_mode = MAIN_IDEX;
    endcase
end

// --- privilege -------------------------------------------------------------
// U_MODE = 0 (hdl/hazard3_csr.v:255-257 ties m_mode to 1), so the specification
// is always executing in M-mode.  MModeIsM proves it rather than assuming it.
t_Privilege spec_priv_i;
t_Privilege spec_priv_o;
assign spec_priv_i = Machine;

// --- mstatus ---------------------------------------------------------------
// pre_mstatus is packed in h3_abs.svh exactly as spec_api.sv:202-208 packs its
// mstatus_t input, so this unpacks it again and the round trip is lossless.
// The output is re-packed into the same 32-bit form so that the ghost, the
// follower and the abstraction all speak one language.
mstatus_t spec_mstatus_i;
mstatus_t spec_mstatus_o;

assign spec_mstatus_i = '{
    mie  : pre_mstatus[3],
    mpie : pre_mstatus[7],
    tw   : pre_mstatus[21],
    mprv : pre_mstatus[17],
    mpp  : pre_mstatus[12:11]
};

assign spec_post_mstatus =
    (32'(spec_mstatus_o.mie)  << 3)  |
    (32'(spec_mstatus_o.mpie) << 7)  |
    (32'(spec_mstatus_o.mpp)  << 11) |
    (32'(spec_mstatus_o.mprv) << 17) |
    (32'(spec_mstatus_o.tw)   << 21);

// --- state the specification has and Hazard3 does not ----------------------
// PMP (PMP_REGIONS = 0) and mseccfg have no registers in this configuration, so
// the specification is handed a permanently-empty PMP.  With every pmpcfg entry
// zero and the hart in M-mode, RISC-V grants all accesses, which is what the
// DUT does.  These are documented non-comparisons, listed in BRINGUP.md.
logic [31:0] spec_mseccfg_i;
logic [31:0] spec_mseccfg_o;
logic [7:0]  spec_pmp_cfg_i  [SPEC_PMP_REGIONS];
logic [7:0]  spec_pmp_cfg_o  [SPEC_PMP_REGIONS];
logic [31:0] spec_pmp_addr_i [SPEC_PMP_REGIONS];
logic [31:0] spec_pmp_addr_o [SPEC_PMP_REGIONS];

assign spec_mseccfg_i = 32'h0;
for (genvar gp = 0; gp < SPEC_PMP_REGIONS; gp = gp + 1) begin: g_spec_pmp_tie
    assign spec_pmp_cfg_i[gp]  = 8'h0;
    assign spec_pmp_addr_i[gp] = 32'h0;
end

// mtval and mcounteren: hardwired zero in the DUT (see h3_abs.svh section 1b).
// Their outputs are left unconnected -- the specification may write them, and
// the harness discards the result, which is the documented non-comparison.
logic [31:0] spec_mtval_o;
logic [31:0] spec_mcounteren_o;

// --- memory ----------------------------------------------------------------
// GATE 5 CONNECTS THESE.  The first-granule read data now comes from
// h3_spec_rdata (check/peek/h3_mem.svh section 3), which is itself an undriven
// free wire in the shared harness -- so the SIGNAL SET of the two models is
// unchanged and `make check-env` still sees identical environments.  The
// direction of causality is Ibex's and is the opposite of what the port name
// suggests: the solver chooses the word at the query cycle, the specification is
// told it, and MemRdataIsSpecData (check/peek/h3_goals.svh section 5) then makes
// the bus hand the core exactly that word when the data phase completes.
//
// The second granule is tied to zero rather than left free.  Hazard3 traps
// misaligned accesses, so the specification never asks for it -- which
// MemNoSecondGranule proves rather than assumes; tying it off here means a
// violation shows up as that property failing rather than as a free input
// silently absorbing the difference.
logic [31:0] spec_mem_read_fst_rdata_i;
logic [31:0] spec_mem_read_snd_rdata_i;

assign spec_mem_read_fst_rdata_i = h3_spec_rdata;
assign spec_mem_read_snd_rdata_i = 32'h0;

// Second-granule outputs.  Hazard3 traps misaligned accesses rather than
// splitting them, so these should never assert; gate 5 states that as a
// property rather than tying them off here.
logic [31:0] spec_mem_write_snd_wdata_o;
logic [3:0]  spec_mem_write_snd_be_o;

// --- the instance ----------------------------------------------------------
spec_api #(
    .NREGS         (32),
    .PMPNumRegions (SPEC_PMP_REGIONS)
) spec_api_i (
    .main_mode              (spec_main_mode),

    // Architectural register file, cut down to the registers the instruction
    // in X actually reads (check/peek/h3_abs.svh, section 1d).
    .regs_i                 (pre_regs_cut),
    .wx_en_o                (spec_post_wX_en),
    .wx_o                   (spec_post_wX),
    .wx_addr_o              (spec_post_wX_addr),

    // Program counter.  pc_o is nextPC_out.
    .nextpc_i               (pre_nextpc),
    .pc_i                   (pre_pc),
    .pc_o                   (spec_post_pc),

    // Read-only / input-only architectural state.
    .misa_i                 (pre_misa),
    .mip_i                  (pre_mip),
    .mvendor_id_i           (pre_mvendorid),
    .march_id_i             (pre_marchid),
    .mimp_id_i              (pre_mimpid),
    .mhart_id_i             (pre_mhartid),
    .mconfigptr_i           (pre_mconfigptr),

    // Not present in this configuration -- see above.
    .mseccfg_i              (spec_mseccfg_i),
    .mseccfg_o              (spec_mseccfg_o),
    .pmp_cfg_i              (spec_pmp_cfg_i),
    .pmp_cfg_o              (spec_pmp_cfg_o),
    .pmp_addr_i             (spec_pmp_addr_i),
    .pmp_addr_o             (spec_pmp_addr_o),
    .mtval_i                (pre_mtval),
    .mtval_o                (spec_mtval_o),
    .mcounteren_i           (pre_mcounteren),
    .mcounteren_o           (spec_mcounteren_o),
    .priv_i                 (spec_priv_i),
    .priv_o                 (spec_priv_o),

    // THE GHOST SET.  Six CSRs; mtval is absent because Hazard3 has no such
    // register (hdl/hazard3_csr.v:844-846).
    .mstatus_i              (spec_mstatus_i),
    .mstatus_o              (spec_mstatus_o),
    .mie_i                  (pre_mie),
    .mie_o                  (spec_post_mie),
    .mcause_i               (pre_mcause),
    .mcause_o               (spec_post_mcause),
    .mtvec_i                (pre_mtvec),
    .mtvec_o                (spec_post_mtvec),
    .mscratch_i             (pre_mscratch),
    .mscratch_o             (spec_post_mscratch),
    .mepc_i                 (pre_mepc),
    .mepc_o                 (spec_post_mepc),

    // The instruction, raw (spec/main.sail decompresses for itself).
    .insn_bits              (h3_x_instr),
    .int_err_o              (spec_int_err),

    .mem_read_o             (spec_mem_read),
    .mem_read_snd_gran_o    (spec_mem_read_snd),
    .mem_read_fst_addr_o    (spec_mem_read_fst_addr),
    .mem_read_snd_addr_o    (spec_mem_read_snd_addr),
    .mem_read_fst_rdata_i   (spec_mem_read_fst_rdata_i),
    .mem_read_snd_rdata_i   (spec_mem_read_snd_rdata_i),

    .mem_write_o            (spec_mem_write),
    .mem_write_snd_gran_o   (spec_mem_write_snd),
    .mem_write_fst_addr_o   (spec_mem_write_fst_addr),
    .mem_write_snd_addr_o   (spec_mem_write_snd_addr),
    .mem_write_fst_wdata_o  (spec_mem_write_fst_wdata),
    .mem_write_snd_wdata_o  (spec_mem_write_snd_wdata_o),
    .mem_write_fst_be_o     (spec_mem_write_fst_be),
    .mem_write_snd_be_o     (spec_mem_write_snd_be_o)
);

// ---------------------------------------------------------------------------
// Properties (generated from thm/hazard3.proof by psgen)
// ---------------------------------------------------------------------------
`include "../build/psgen-h3.sv"

endmodule
