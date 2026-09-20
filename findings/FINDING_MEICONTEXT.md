# Finding: a trapping `meicontext` write still modifies `mie`

*Status: verified divergence from the RISC-V Sail golden model (machine-checked
counterexample). Fixed locally as a conformance patch and re-verified. Not yet
reported upstream. Severity: moderate in kind (architectural state changed by an
instruction that raises illegal-instruction), low in practice.*
*Design: Hazard3 @ `8af9929`, configured `EXTENSION_XH3IRQ=0`.*

## The divergence

`meicontext` (0xBE5) belongs to the custom Xh3irq extension. With
`EXTENSION_XH3IRQ=0` the CSR does not exist: the decode at
`hdl/hazard3_csr.v:1248` is gated on the extension, so a write to it raises
illegal-instruction. But the write arm is not gated:

```verilog
end else if (wen_m_mode && addr == MEICONTEXT) begin   // :335, no EXTENSION_XH3IRQ
    ... mie[3]/mie[7] updated (the mtiesave/msiesave side effect) ...
```

and `wen_m_mode` (`:172`) is not qualified by decode legality. So
`csrrwi x31, 0xBE5, 4` traps with mcause=2 **and** changes `mie`.

## Evidence

Witness `results/cex/round10-CtiFollowerPostIsDutMie/`: `mie: 0 -> 0x8` in the
same cycle as `m_trap_enter_vld = 1`. The goal `WrapMie` still proved because
its ghost tie is guarded on `h3_has_ghost`, which excludes the trap-entry
cycle; the divergence was caught by a follower-side lemma instead.

## The fix (applied via `patch_hazard3_rtl.sh`, `H3_CONFORMANCE=1`)

```verilog
end else if (wen_m_mode && addr == MEICONTEXT && EXTENSION_XH3IRQ) begin
```

Alternative, broader fix for upstream: qualify `wen_m_mode` with the
decode-legal signal so no undecodable CSR can have a write side effect.

## Impact

An illegal instruction must not change architectural state (priv spec §3.1.15:
the trap is taken and the instruction is not executed). Requires executing a
CSR write to an address no compiler emits, so exposure is deliberate code only.

## Simulation reproducer (2026-09-20)

`upstream/repro/meicontext_side_effect.bin` on Hazard3's CXXRTL testbench: exit 1 (diverges) at
v1.1.1 `8af99293`, exit 0 (agrees with Sail) on the same tree with the conformance
patch applied. Logs in `upstream/repro/out/` and `out-fixed/`.
