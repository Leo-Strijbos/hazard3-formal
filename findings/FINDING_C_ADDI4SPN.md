# Finding: Hazard3 executes 7 reserved `C.ADDI4SPN` encodings

*Status: verified divergence from the RISC-V Sail golden model. Not yet reported
upstream. Severity: low impact today, forward-compatibility risk.*
*Design: Hazard3 @ `8af9929` (the RISC-V core in the Raspberry Pi RP2350).*
*Found by: unbounded formal equivalence against the RISC-V Sail specification —
not by directed testing.*

## The divergence

RISC-V unprivileged ISA, compressed extension, `C.ADDI4SPN`: the immediate is
`nzuimm = instr[12:5]`, and **the code points with `nzuimm = 0` are reserved.**

`hdl/hazard3_instr_decompress.v:205-209`:

```verilog
`RVOPC_C_ADDI4SPN: begin
    instr_out = `RVOPC_NOZ_ADDI | rfmt_rd(rd_s) | rfmt_rs1(5'd2) | { ... };
    invalid   = ~|instr_in[12:2]; // Always-invalid all-zeroes instruction
end
```

The test is `instr[12:2]`, not `instr[12:5]`. It additionally requires `rd'`
(bits 4:2) to be zero, so it only catches the all-zeroes halfword `0x0000`.
Every other `nzuimm = 0` encoding is accepted and expanded to `addi rd', x2, 0`.

**Affected encodings — exactly 7:**

| encoding | rd' | executes as |
|---|---|---|
| `0x0004` | x9  | `addi x9, x2, 0` |
| `0x0008` | x10 | `addi x10, x2, 0` |
| `0x000c` | x11 | `addi x11, x2, 0` |
| `0x0010` | x12 | `addi x12, x2, 0` |
| `0x0014` | x13 | `addi x13, x2, 0` |
| `0x0018` | x14 | `addi x14, x2, 0` |
| `0x001c` | x15 | `addi x15, x2, 0` |

Sail traps all seven as illegal instructions (`riscv_insts_cext.sail`, guard
`nz… != 0b00000000`). Hazard3 retires them and advances the PC by 2.

## Evidence

1. **The RTL line itself** — the field mismatch is unambiguous.
2. **The signal reaches the trap logic.** `decomp_invalid` → `cir_invalid_16bit`
   (`hazard3_frontend.v:886`) → `fd_cir_invalid_16bit` (`hazard3_core.v:308`) →
   `d_invalid` (`hazard3_decode.v:92`). A correct `invalid` here *would* trap, so
   this is a decode-condition defect, not a missing trap path.
3. **Two independent machine-checked counterexamples** from the Sail-equivalence
   model, on different builds (`fixall` and `ctrl`), using `0x0008` and `0x001C`
   — both members of the 7-element set derived independently from the RTL. Each
   trace shows the spec taking a trap with `mcause = 2` (illegal instruction)
   while the DUT retires with `rvfi_trap = 0` and `pc += 2`.
4. **Not house style.** Every sibling reserved-encoding test in the same file
   checks exactly the field the spec names: `C.LUI` `~|{instr[12], instr[6:2]}`
   ("RESERVED if imm == 0"), `C.JR` `~|rs1_l`, `C.LWSP` `~|rd_l`.
   `C.ADDI4SPN` is the only one that tests a wider field.
5. **The comment states the author's intent** — "Always-invalid all-zeroes
   instruction". The case being handled was `0x0000`, not the reserved-`nzuimm`
   case. This reads as an oversight rather than a policy.
6. No mention of `ADDI4SPN` or a deliberate departure in the repo's docs, tests,
   or the decompressor's commit history.

## The fix

One line:

```verilog
invalid = ~|instr_in[12:5];   // RESERVED if nzuimm == 0
```

`~|instr_in[12:5]` is exactly "nzuimm == 0", so it still catches `0x0000` and
additionally catches the 7 encodings above. It matches the style of the sibling
cases. **Untested by us — we have not modified or rebuilt the RTL.**

## Impact — stated honestly

**Low today.** No compiler emits these encodings; software would have to encode
them deliberately. Executing `addi rd', sp, 0` instead of trapping does not
corrupt architectural state beyond writing `sp` into `rd'`.

**The real risk is forward compatibility.** Reserved code points exist so future
standard extensions can claim them. If these are later allocated, Hazard3
silently executes the wrong instruction where a compliant core would trap and
let software emulate. This is exactly the failure reserved encodings are meant
to prevent.

RISC-V's language is "reserved", with the convention that implementations should
raise illegal-instruction exceptions. It is not an unambiguous "must", so this is
better characterised as a **conformance divergence from the golden model** than
as a functional bug. Against the Sail specification — the executable reference —
the divergence is certain.

## Limits of this result

- Verified against the **open-source RTL at commit `8af9929`**. We have not
  verified silicon; the shipped RP2350 may differ.
- We have not asked the maintainer whether this is intentional. It should be
  reported upstream as a question, not published as a defect claim.
- The three other narrow-looking `invalid` terms flagged during triage
  (`hazard3_instr_decompress.v:250, 256, 323`) were checked and are correct.

## Why this matters methodologically

Directed testing does not generate reserved encodings — there is nothing to
compare against, and no test author writes a case for an instruction that
shouldn't exist. Equivalence against an executable golden specification covers
the whole encoding space by construction, so this class of divergence falls out
of the proof rather than having to be anticipated.

It was found incidentally: the counterexample surfaced while diagnosing an
unrelated `WrapMcause` goal.

## Simulation reproducer (2026-09-20)

`upstream/repro/c_addi4spn_reserved.bin` on Hazard3's CXXRTL testbench: exit 1 (diverges) at
v1.1.1 `8af99293`, exit 0 (agrees with Sail) on the same tree with the conformance
patch applied. Logs in `upstream/repro/out/` and `out-fixed/`.
