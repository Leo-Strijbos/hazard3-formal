# FENCE with rs1 or rd non-zero raises illegal-instruction (v1.1.1) -- not filed

Already fixed upstream. `develop` commit `6adda670` (2026-08-22, "Fix: fence and
fence.i decode should match on all values of rd, rs1 and imm fields. Found from
running new ACT version which covers these encodings.") makes the same change
our conformance patch makes: the opcode pattern no longer pins rs1/rd to zero,
and the decode arm forces rs1, rs2 and rd to x0. The fix is not on `stable`
(v1.1.1, `8af99293`) at the time of writing.

Our finding (FINDING_FENCE_FIELDS.md, witness instruction `0xf150020f`) was
therefore an independent rediscovery, by formal equivalence, of a divergence the
maintainer had already found with the newer riscv-arch-test suite. The
reproducer `repro/fence_rd_nonzero.bin` exits 1 on v1.1.1 and is expected to
exit 0 on `develop`; see `repro/out-develop/`.

Nothing to file. If a stable release is cut without this commit, a one-line
backport request would be appropriate.
