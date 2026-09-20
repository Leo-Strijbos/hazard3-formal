#!/usr/bin/env python3
"""Emit the five reproducer binaries for the Hazard3 findings.

No toolchain needed: each program is a few dozen RV32I(C) instructions,
assembled here by hand so the encodings can be checked by eye. Each binary is
loaded at 0x80000000 by Hazard3's own testbench (test/sim/tb_cxxrtl) and
signals its verdict through the testbench's exit code:

    exit 0  the core did what the RISC-V Sail model does
    exit 1  the core diverged (the behaviour the finding describes)
    exit 2+ the program did not reach its check (unexpected)

Usage:  python3 mkrepro.py OUTDIR      # writes OUTDIR/<name>.bin and .lst
"""
import struct, sys, os

MEM_BASE  = 0x80000000
IO        = 0xc0000000          # tb_common/include/tb_constants.h
PRINT_U32 = 0x004
EXIT      = 0x008
SET_SOFTIRQ = 0x010
CSR = dict(mstatus=0x300, mie=0x304, mtvec=0x305, mepc=0x341, mcause=0x342,
           meicontext=0xbe5)
x0, sp, t0, t1, t2, a0, t3, t4 = 0, 2, 5, 6, 10, 10, 28, 29
a0 = 10

def s(v, bits):
    v &= (1 << bits) - 1
    return v
def itype(op, f3, rd, rs1, imm):
    assert -2048 <= imm < 2048
    return s(imm, 12) << 20 | rs1 << 15 | f3 << 12 | rd << 7 | op
def lui(rd, imm20):      return (imm20 & 0xfffff) << 12 | rd << 7 | 0x37
def addi(rd, rs1, imm):  return itype(0x13, 0, rd, rs1, imm)
def srli(rd, rs1, sh):   return itype(0x13, 5, rd, rs1, sh)
def andi(rd, rs1, imm):  return itype(0x13, 7, rd, rs1, imm)
def sltu(rd, rs1, rs2):  return rs2 << 20 | rs1 << 15 | 3 << 12 | rd << 7 | 0x33
def sw(rs2, imm, rs1):
    i = s(imm, 12)
    return (i >> 5) << 25 | rs2 << 20 | rs1 << 15 | 2 << 12 | (i & 0x1f) << 7 | 0x23
def jal(rd, off):
    o = s(off, 21)
    return ((o >> 20) & 1) << 31 | ((o >> 1) & 0x3ff) << 21 | ((o >> 11) & 1) << 20 \
         | ((o >> 12) & 0xff) << 12 | rd << 7 | 0x6f
def csr_(f3, rd, csr, rs1_or_uimm): return csr << 20 | rs1_or_uimm << 15 | f3 << 12 | rd << 7 | 0x73
def csrrw(rd, csr, rs1):  return csr_(1, rd, CSR[csr], rs1)
def csrrs(rd, csr, rs1):  return csr_(2, rd, CSR[csr], rs1)
def csrrwi(rd, csr, u):   return csr_(5, rd, CSR[csr], u)
def csrrsi(rd, csr, u):   return csr_(6, rd, CSR[csr], u)
NOP = addi(0, 0, 0)

class Prog:
    def __init__(self): self.words = {}; self.lst = []
    def at(self, off): self.pc = off
    def w(self, word, text):
        assert self.pc % 4 == 0 and self.pc not in self.words, hex(self.pc)
        self.words[self.pc] = word; self.lst.append((self.pc, f"{word:08x}", text)); self.pc += 4
    def h2(self, h1, h2, text):            # two 16-bit halves, little-endian order
        self.w(h1 | h2 << 16, text)
    def emit(self, name, outdir):
        end = max(self.words) + 4
        blob = bytearray(end)
        for off, word in self.words.items(): struct.pack_into("<I", blob, off, word)
        open(os.path.join(outdir, name + ".bin"), "wb").write(blob)
        with open(os.path.join(outdir, name + ".lst"), "w") as f:
            for off, word, text in sorted(self.lst):
                f.write(f"{MEM_BASE + off:08x}: {word}  {text}\n")

def io_print(p, reg, note=""):
    p.w(sw(reg, PRINT_U32, t0), f"sw x{reg}, 4(t0)      # print {note}")
def io_exit(p, code, note=""):
    p.w(addi(a0, x0, code), f"addi a0, x0, {code}")
    p.w(sw(a0, EXIT, t0),   f"sw a0, 8(t0)         # exit {code}: {note}")

def direct_handler(p, exit_code, note):
    """Trap handler at MTVEC_INIT (0x80000000, direct mode): print mcause and mepc."""
    p.at(0x000)
    p.w(lui(t0, 0xc0000),          "lui t0, 0xc0000      # testbench IO base")
    p.w(csrrs(a0, "mcause", x0),   "csrr a0, mcause")
    io_print(p, a0, "mcause")
    p.w(csrrs(a0, "mepc", x0),     "csrr a0, mepc")
    io_print(p, a0, "mepc")
    io_exit(p, exit_code, note)

def prog_c_addi4spn():
    p = Prog()
    direct_handler(p, 0, "trapped: matches Sail (illegal instruction)")
    p.at(0x040)                              # RESET_VECTOR
    p.w(lui(sp, 0xdead0),          "lui sp, 0xdead0      # sp = 0xdead0000")
    p.w(addi(a0, x0, 0),           "addi a0, x0, 0       # x10 = 0")
    p.h2(0x0008, 0x0001,           ".hword 0x0008 ; c.nop   # C.ADDI4SPN rd'=x10, nzuimm=0: RESERVED")
    p.w(lui(t0, 0xc0000),          "lui t0, 0xc0000")
    io_print(p, a0, "x10 after the reserved encoding")
    io_exit(p, 1, "retired as addi x10, sp, 0: diverges from Sail")
    return p

def prog_fence_fields():
    p = Prog()
    direct_handler(p, 1, "trapped: diverges from Sail (FENCE with rd!=0 is a fence)")
    p.at(0x040)
    p.w(addi(4, x0, 0),            "addi x4, x0, 0")
    p.w(0xf150020f,                ".word 0xf150020f     # fence fm=f pred=w succ=rw rs1=x0 rd=x4")
    p.w(lui(t0, 0xc0000),          "lui t0, 0xc0000")
    p.w(addi(a0, 4, 0),            "addi a0, x4, 0")
    io_print(p, a0, "x4 after the fence (should still be 0)")
    io_exit(p, 0, "fence retired: matches Sail")
    return p

def prog_mprv():
    p = Prog()
    direct_handler(p, 3, "unexpected trap")
    p.at(0x040)
    p.w(lui(t1, 0x20),             "lui t1, 0x20         # t1 = 0x20000 = mstatus.MPRV")
    p.w(csrrs(x0, "mstatus", t1),  "csrs mstatus, t1")
    p.w(csrrs(a0, "mstatus", x0),  "csrr a0, mstatus")
    p.w(lui(t0, 0xc0000),          "lui t0, 0xc0000")
    io_print(p, a0, "mstatus read-back")
    p.w(srli(a0, a0, 17),          "srli a0, a0, 17")
    p.w(andi(a0, a0, 1),           "andi a0, a0, 1       # a0 = MPRV bit")
    p.w(sw(a0, EXIT, t0),          "sw a0, 8(t0)         # exit MPRV: 1 = readable 1 (diverges), 0 = hardwired 0")
    return p

def prog_meicontext():
    p = Prog()
    p.at(0x000)                              # trap handler: the write must trap
    p.w(lui(t0, 0xc0000),          "lui t0, 0xc0000")
    p.w(csrrs(a0, "mcause", x0),   "csrr a0, mcause")
    io_print(p, a0, "mcause (2 = illegal instruction, expected)")
    p.w(csrrs(a0, "mie", x0),      "csrr a0, mie")
    io_print(p, a0, "mie after the trapping write")
    p.w(sltu(a0, x0, a0),          "sltu a0, x0, a0      # a0 = (mie != 0)")
    p.w(sw(a0, EXIT, t0),          "sw a0, 8(t0)         # exit: 1 = mie changed by a trapping write (diverges), 0 = unchanged")
    p.at(0x040)
    p.w(lui(t0, 0xc0000),          "lui t0, 0xc0000")
    p.w(csrrs(a0, "mie", x0),      "csrr a0, mie")
    io_print(p, a0, "mie before")
    p.w(csrrwi(x0, "meicontext", 4), "csrrwi x0, 0xbe5, 4  # meicontext.msiesave; CSR absent when EXTENSION_XH3IRQ=0")
    io_exit(p, 2, "the write did not trap (unexpected)")
    return p

def prog_mtvec_vectored():
    p = Prog()
    direct_handler(p, 3, "trap while still in direct mode (unexpected)")
    p.at(0x040); p.w(jal(x0, 0x100 - 0x040), "j main")
    p.at(0x074); p.w(jal(x0, 0x1c0 - 0x074), "j hexc                # vector slot 0: exceptions (BASE)")
    p.at(0x078); p.w(NOP, "nop")
    p.at(0x07c); p.w(jal(x0, 0x180 - 0x07c), "j h7c                 # BASE | (3<<2) = 0x8000007c  (Hazard3)")
    p.at(0x080); p.w(jal(x0, 0x1a0 - 0x080), "j h80                 # BASE + (3<<2) = 0x80000080  (Sail)")
    p.at(0x100)
    p.w(lui(t0, 0xc0000),          "main: lui t0, 0xc0000")
    p.w(lui(t1, 0x80000),          "lui t1, 0x80000")
    p.w(addi(t1, t1, 0x75),        "addi t1, t1, 0x75    # mtvec = 0x80000075: BASE 0x80000074, MODE vectored")
    p.w(csrrw(x0, "mtvec", t1),    "csrw mtvec, t1")
    p.w(csrrs(a0, "mtvec", x0),    "csrr a0, mtvec")
    io_print(p, a0, "mtvec read-back (unaligned BASE retained?)")
    p.w(addi(t2, x0, 8),           "addi t2, x0, 8")
    p.w(csrrs(x0, "mie", t2),      "csrs mie, t2         # MSIE")
    p.w(csrrsi(x0, "mstatus", 8),  "csrsi mstatus, 8     # MIE")
    p.w(addi(t3, x0, 1),           "addi t3, x0, 1")
    p.w(sw(t3, SET_SOFTIRQ, t0),   "sw t3, 0x10(t0)      # testbench: assert machine software interrupt")
    for _ in range(8): p.w(NOP, "nop")
    io_exit(p, 2, "no interrupt taken (unexpected)")
    p.at(0x180)
    p.w(lui(t0, 0xc0000),          "h7c: lui t0, 0xc0000")
    p.w(addi(a0, x0, 0x7c),        "addi a0, x0, 0x7c")
    io_print(p, a0, "entered at offset 0x7c")
    io_exit(p, 1, "entered at BASE | 0xc: diverges from Sail (BASE + 0xc)")
    p.at(0x1a0)
    p.w(lui(t0, 0xc0000),          "h80: lui t0, 0xc0000")
    p.w(addi(a0, x0, 0x80),        "addi a0, x0, 0x80")
    io_print(p, a0, "entered at offset 0x80")
    io_exit(p, 0, "entered at BASE + 0xc: matches Sail")
    p.at(0x1c0)
    p.w(lui(t0, 0xc0000),          "hexc: lui t0, 0xc0000")
    p.w(csrrs(a0, "mcause", x0),   "csrr a0, mcause")
    io_print(p, a0, "mcause")
    io_exit(p, 3, "exception instead of the interrupt (unexpected)")
    return p

PROGS = {
    "c_addi4spn_reserved": prog_c_addi4spn,     # config: default
    "fence_rd_nonzero":    prog_fence_fields,   # config: default
    "mstatus_mprv_no_umode": prog_mprv,         # config: U_MODE=0
    "meicontext_side_effect": prog_meicontext,  # config: EXTENSION_XH3IRQ=0
    "mtvec_vectored_unaligned": prog_mtvec_vectored,  # config: default
}

if __name__ == "__main__":
    out = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out, exist_ok=True)
    for name, fn in PROGS.items():
        fn().emit(name, out)
        print("wrote", name)
