// Hazard3 formal harness, CORE-ONLY model (build/core.aig).
//
//   core + bus environment.  No Sail specification.
//
// Model A of the two-model split (see HAZARD3_HARNESS_PLAN.md, "Architectural
// change: two models").  Everything core-side is in check/h3_core_common.svh,
// which check/h3_top.sv (build/all.aig) includes identically; the two models
// therefore present the core with exactly the same environment, which is the
// precondition for reusing a core-only lemma proved here on the full model.
//
// It carries the SAME psgen property set as build/all.aig (build/psgen-h3.sv),
// so `aig-manip select` names resolve identically on both models.  A property
// that mentions a spec signal would not compile here, which is a useful
// mechanical check that the lemma set really is core-only.

`default_nettype wire

module top (
    input logic clk_i
);

// ---------------------------------------------------------------------------
// Core + bus/IRQ environment + lemma support wires (shared with all.aig)
// ---------------------------------------------------------------------------
`include "h3_core_common.svh"

// ---------------------------------------------------------------------------
// Properties (generated from thm/hazard3.proof by psgen)
// ---------------------------------------------------------------------------
`include "../build/psgen-h3.sv"

endmodule
