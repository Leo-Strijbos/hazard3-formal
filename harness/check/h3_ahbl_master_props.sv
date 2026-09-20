// AHB5 master-contract properties for the Hazard3 harness.
//
// This is a *mechanical transcription* of Hazard3's own
//   test/formal/common/ahbl_master_assertions.v   (C) 2021-2022 Luke Wren
// with two changes, and no others:
//
//   1. Each `assert(X)` inside the original's `always @(posedge clk) if (rst_n)`
//      block becomes a combinational output `ok_*`, so that the psgen flow can
//      turn it into a *named* property (`thm/hazard3.proof`).  Raw `assert()`
//      cells cannot be used here: `aig-manip select` requires every AIGER bad
//      state to carry a psgen `StepN_Name` label, and asserts a 1:1
//      correspondence between bads and ywmap entries.
//   2. `$past(x)` / `$stable(x)` are replaced by explicit `past_*` registers.
//      (Not strictly necessary -- yosys-slang does accept $past/$stable in
//      procedural code -- but an output has to be combinational, and $past in a
//      continuous assignment is not legal SystemVerilog.)
//
// The `ok_*` outputs are the *implications*: guard -> assertion body, so that
// `assert property (ok_x)` on every cycle is exactly the original's
// `if (guard) assert(body)` on every cycle after reset.
//
// Original line numbers are quoted against each property.

`default_nettype wire

module h3_ahbl_master_props #(
    parameter W_ADDR = 32,
    parameter W_DATA = 32
) (
    input  wire              clk,
    input  wire              rst_n,

    input  wire              src_hready,
    input  wire              src_hresp,
    input  wire              src_hexokay,
    input  wire [W_ADDR-1:0] src_haddr,
    input  wire              src_hwrite,
    input  wire [1:0]        src_htrans,
    input  wire [2:0]        src_hsize,
    input  wire [2:0]        src_hburst,
    input  wire [3:0]        src_hprot,
    input  wire              src_hmastlock,
    input  wire              src_hexcl,
    input  wire [W_DATA-1:0] src_hwdata,
    input  wire [W_DATA-1:0] src_hrdata,

    output wire              ok_aph_aligned,        // orig :63
    output wire              ok_aph_size,           // orig :65
    output wire              ok_aph_stable,         // orig :67-77
    output wire              ok_seq_after_active,   // orig :79-80
    output wire              ok_seq_addr,           // orig :83-84
    output wire              ok_excl_no_pipeline,   // orig :86-87
    output wire              ok_dph_wdata_stable,   // orig :93-94
    output wire              ok_dph_excl_reserved   // orig :96-97
);

// ---------------------------------------------------------------------------
// Data-phase monitoring -- verbatim from the original (orig :31-55)
// ---------------------------------------------------------------------------
reg              src_active_dph;
reg              src_write_dph;
reg [W_ADDR-1:0] src_addr_dph;
reg [2:0]        src_size_dph;
reg              src_excl_dph;
reg              global_reservation_valid;

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        src_active_dph <= 1'b0;
        src_write_dph <= 1'b0;
        src_addr_dph <= {W_ADDR{1'b0}};
        src_size_dph <= 3'h0;
        src_excl_dph <= 1'b0;
        global_reservation_valid <= 1'b0;
    end else if (src_hready) begin
        src_active_dph <= src_htrans[1];
        src_write_dph <= src_hwrite;
        src_addr_dph <= src_haddr;
        src_size_dph <= src_hsize;
        src_excl_dph <= src_hexcl && src_htrans[1];
        if (src_excl_dph)
            global_reservation_valid <= src_hexokay && !src_write_dph;
    end
end

// ---------------------------------------------------------------------------
// Explicit $past registers (replacing $past/$stable)
// ---------------------------------------------------------------------------
// Reset values are the idle-bus values, so that the very first post-reset
// cycle cannot fire a property spuriously.  Both properties that consume these
// are in any case guarded by past_req_held / src_active_dph, which reset to 0.
reg              past_hready;
reg              past_req_held;   // $past(src_htrans[1] && !src_hready && !src_hresp)
reg [1:0]        past_htrans;
reg              past_hwrite;
reg [W_ADDR-1:0] past_haddr;
reg [2:0]        past_hsize;
reg [2:0]        past_hburst;
reg [3:0]        past_hprot;
reg              past_hmastlock;
reg [W_DATA-1:0] past_hwdata;

always @ (posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        past_hready    <= 1'b1;
        past_req_held  <= 1'b0;
        past_htrans    <= 2'b00;
        past_hwrite    <= 1'b0;
        past_haddr     <= {W_ADDR{1'b0}};
        past_hsize     <= 3'h0;
        past_hburst    <= 3'h0;
        past_hprot     <= 4'h0;
        past_hmastlock <= 1'b0;
        past_hwdata    <= {W_DATA{1'b0}};
    end else begin
        past_hready    <= src_hready;
        past_req_held  <= src_htrans[1] && !src_hready && !src_hresp;
        past_htrans    <= src_htrans;
        past_hwrite    <= src_hwrite;
        past_haddr     <= src_haddr;
        past_hsize     <= src_hsize;
        past_hburst    <= src_hburst;
        past_hprot     <= src_hprot;
        past_hmastlock <= src_hmastlock;
        past_hwdata    <= src_hwdata;
    end
end

// ---------------------------------------------------------------------------
// The properties
// ---------------------------------------------------------------------------
wire aph_active = src_htrans != 2'b00;   // orig :61

// Transfer must be naturally aligned
assign ok_aph_aligned = !aph_active ||
    ~|(src_haddr & ~({W_ADDR{1'b1}} << src_hsize));

// HSIZE appropriate for bus width
assign ok_aph_size = !aph_active ||
    ((32'd8 << src_hsize) <= W_DATA);

// No deassertion or change of active request
assign ok_aph_stable = !aph_active || !past_req_held || (
    {src_htrans,  src_hwrite,  src_haddr,  src_hsize,  src_hburst,  src_hprot,  src_hmastlock} ==
    {past_htrans, past_hwrite, past_haddr, past_hsize, past_hburst, past_hprot, past_hmastlock}
);

// SEQ only issued following an NSEQ or SEQ, never an IDLE
assign ok_seq_after_active = !aph_active || (src_htrans != 2'b11) || src_active_dph;

// SEQ transfer addresses must be sequential with previous transfer
assign ok_seq_addr = !aph_active || (src_htrans != 2'b11) ||
    (src_haddr == src_addr_dph + W_DATA / 8);

// No pipelining of exclusive transfers
assign ok_excl_no_pipeline = !aph_active || !src_excl_dph ||
    !(src_hexcl && src_htrans[1]);

// Write data stable during write data phase
assign ok_dph_wdata_stable = !src_active_dph || !(src_write_dph && !past_hready) ||
    (src_hwdata == past_hwdata);

// An exclusive write must match a prior exclusive read which was HEXOKAY=1
assign ok_dph_excl_reserved = !src_active_dph || !(src_write_dph && src_excl_dph) ||
    global_reservation_valid;

endmodule
