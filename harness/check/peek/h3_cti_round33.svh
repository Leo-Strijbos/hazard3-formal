// ===========================================================================
// Round 33.  CtiFolWriteCoverage was REFUTED at depth 5 (round 32, witness in
// results/icti/round32-CtiFolWriteCoverage-bmc/report.txt): a C.J (0xbffd,
// expanded JAL x0) makes the spec's RAW write-enable fire with wX_addr = 0
// and wX = pc+2 -- Sail calls wX(0, ...) for every jump, and x0 discards it.
// C.J / C.JR are not writer classes, and need not be: no lemma above tracks
// x0.  V2 masks the x0 write exactly as the en/CSR lemmas do (round 26).
// ===========================================================================
logic h3_cti_fol_write_coverage_v2;
assign h3_cti_fol_write_coverage_v2 =
    !h3_fol_clean_write || !h3_fol_spec_wX_en || !(|h3_fol_spec_wX_addr) || h3_fol_is_writer;
`include "h3_cti_round36.svh"
