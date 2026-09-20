// ===========================================================================
// Round 37.  mepc closure.  Round 36 CTIs:
//  * CtiTrapMepcAgrees compared spec_post_mepc with m_exception_return_addr
//    over the whole M residency, but the RTL only guarantees that value at the
//    handshake (FollowerPcIsExceptionReturn: at h3_trap_entry && !irq,
//    m_exception_return_addr == h3_fol_pc).  Sail sets mepc = pc on trap entry
//    (riscv_sys_control.sail:267, no legalization), so the spec-side statement
//    is simply spec_post_mepc == h3_fol_pc; the proven DUT tie closes the edge.
//  * CtiGhostTracksMepcV3's CTI had an odd d_pc (0xffeeeeef): the DUT stores
//    mepc_in & MEPC_MASK (bit 0 cleared, C extension) while the spec keeps the
//    value as is.  Real PCs are even; state it (DUT-only) for the D-stage PC and
//    for the follower's latched PC.
// ===========================================================================
logic h3_cti_pc_even, h3_cti_fol_pc_even, h3_cti_trap_mepc_agrees_v2;
assign h3_cti_pc_even     = !pre_pc[0];
assign h3_cti_fol_pc_even = !h3_fol_valid || !h3_fol_pc[0];
assign h3_cti_trap_mepc_agrees_v2 =
    !h3_fol_trap_rec || (h3_fol_spec_post_mepc == h3_fol_pc);
`include "h3_cti_round38.svh"
