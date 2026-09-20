// ===========================================================================
// Round 31.  CtiWbLoad timed out three times (rounds 25/27/29, kind depth
// 16-23).  The last CTI (results/icti/round29-CtiWbLoad/report.txt): an LB
// in M whose follower record carries h3_fol_spec_wX = 0xffffffff while the
// bus data (== h3_fol_spec_rdata, gate 5's assumption) is 0x7fffffff -- the
// specification's answer is a sign-extended byte, but NOTHING relates the
// latched answer to the lane the DUT will pick (xm_addr_align, xm_memop).
// At the query edge both are functions of the same address and data:
// spec_post_wX = extend(select(h3_spec_rdata, addr[1:0]), memop) and the
// DUT's m_result = m_rdata_pick_sext (hazard3_core.v:1443-1455) over the
// same lane once the data phase ends.  R31.1 states the latched relation over
// the M residency; CtiWbLoad (retire form) sits one layer above it.
// ===========================================================================
logic [31:0] h3_fol_rd_data;
assign h3_fol_rd_data = h3_fol_spec_rdata;
logic [7:0]  h3_fol_rd_byte;
assign h3_fol_rd_byte =
    (cpu.core.xm_addr_align == 2'b00) ? h3_fol_rd_data[7:0]   :
    (cpu.core.xm_addr_align == 2'b01) ? h3_fol_rd_data[15:8]  :
    (cpu.core.xm_addr_align == 2'b10) ? h3_fol_rd_data[23:16] :
                                        h3_fol_rd_data[31:24];
logic [15:0] h3_fol_rd_half;
assign h3_fol_rd_half = cpu.core.xm_addr_align[1] ? h3_fol_rd_data[31:16] : h3_fol_rd_data[15:0];
logic [31:0] h3_fol_load_pick;
assign h3_fol_load_pick =
    (cpu.core.xm_memop == 5'h00) ? h3_fol_rd_data :                                   // LW
    (cpu.core.xm_memop == 5'h01) ? {{16{h3_fol_rd_half[15]}}, h3_fol_rd_half} :      // LH
    (cpu.core.xm_memop == 5'h03) ? {16'h0, h3_fol_rd_half} :                         // LHU
    (cpu.core.xm_memop == 5'h02) ? {{24{h3_fol_rd_byte[7]}}, h3_fol_rd_byte} :       // LB
    (cpu.core.xm_memop == 5'h04) ? {24'h0, h3_fol_rd_byte} :                         // LBU
                                   32'h0;
logic h3_cti_fol_load_wx_is_pick;
assign h3_cti_fol_load_wx_is_pick =
    !h3_fol_clean_write || !h3_fol_is_load || !h3_fol_spec_wX_en ||
    (h3_fol_spec_wX == h3_fol_load_pick);
`include "h3_cti_round32.svh"
