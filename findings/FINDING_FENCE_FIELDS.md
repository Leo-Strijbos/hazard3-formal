# Finding: Hazard3 traps `FENCE` when rs1 or rd is non-zero

*Status: verified divergence from the RISC-V Sail golden model (machine-checked
counterexample). Fixed locally as a conformance patch and re-verified. Not yet
reported upstream. Severity: low, forward-compatibility.*
*Design: Hazard3 @ `8af9929`.*

Note: this witness was first mis-read on our side as "the spec executes a
reserved MISC-MEM encoding as a NOP". The instruction `0xf150020f` has
funct3 = 000 — it is a plain `FENCE` (fm=0xf, pred=I, succ=I|R, rs1=x0, rd=x4).
The spec is right; Hazard3 is the one that deviates.

## The divergence

Unprivileged spec §2.7: "The unused fields in the FENCE instructions—rs1 and
rd—are reserved for finer-grain fences in future extensions. For forward
compatibility, base implementations shall ignore these fields ... Base
implementations shall treat all such reserved configurations [of fm/pred/succ]
as normal fences with fm=0000."

`hdl/rv_opcodes.vh:59`:

```verilog
`define RVOPC_FENCE  32'b????????????00000000000000001111   // rs1=0, rd=0 pinned
```

`hazard3_decode.v:513` comments "Note rs1/rd are zero in instruction". A FENCE
with rd≠0 or rs1≠0 matches nothing and falls to illegal-instruction. Sail
decodes it as `FENCE_RESERVED` (`riscv_insts_hints.sail:140-145`) and retires
it as a no-op fence.

## Evidence

Witness `results/cex/round13-CtiGhostTracksMcauseV2/`, frame 4: instruction
`0xf150020f`; spec `pc+4`, `mcause` unchanged, `spec_int_err=0`; DUT raises
illegal-instruction (mcause=2, pc -> mtvec). This one witness blocks
`WrapMcause`, `WrapMepc` and `WrapPc` together.

## The fix (applied via `patch_hazard3_rtl.sh`, `H3_CONFORMANCE=1`)

```verilog
`define RVOPC_FENCE  32'b?????????????????000?????0001111
// decode arm: force the ignored fields so nothing is written or waited on
`RVOPC_FENCE: begin raw_rs1 = X0; raw_rs2 = X0; raw_rd = X0; raw_fence_d = 1'b1; end
```

The decode arm change matters: `raw_rd` defaults to `instr[11:7]`, so widening
the opcode pattern alone would make `fence` with rd=x4 write x4.

## Impact

No compiler emits FENCE with non-zero rs1/rd today. The risk is the one the
spec names: a future extension that allocates these fields would trap on
Hazard3 where a conforming core executes a plain fence.
