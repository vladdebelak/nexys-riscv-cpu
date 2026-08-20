# test1.s — self-checking RV32I exerciser.
# Every check branches to `fail` on mismatch. If all pass, the program stores
# 0x0ACE to the memory-mapped LED word (0x1000) and ECALLs (halt). On any
# failure it stores 0x0BAD instead. The testbench only has to read the LEDs.
#
# Exercises: reg-reg & reg-imm ALU, shifts, SLT/SLTU, all branch conditions,
# JAL/JALR call+return, AUIPC, and byte/half/word load+store with sign/zero
# extension — including load-use and back-to-back dependencies (forwarding).

    # ---- reg-imm / reg-reg + forwarding ----
    addi t0, x0, 10
    addi t1, x0, 20
    add  t2, t0, t1          # 30
    addi t3, x0, 30
    bne  t2, t3, fail

    sub  t4, t1, t0          # 10
    addi t5, x0, 10
    bne  t4, t5, fail

    # ---- logical ----
    li   t0, 0xF0
    li   t1, 0x0F
    or   t2, t0, t1          # 0xFF
    li   t3, 0xFF
    bne  t2, t3, fail
    and  t2, t0, t1          # 0
    bne  t2, x0, fail
    xor  t2, t0, t0          # 0
    bne  t2, x0, fail

    # ---- shifts ----
    li   t0, 1
    slli t1, t0, 4           # 16
    li   t2, 16
    bne  t1, t2, fail
    li   t0, 0x80000000
    srli t1, t0, 28          # 0x8
    li   t2, 0x8
    bne  t1, t2, fail
    srai t1, t0, 28          # 0xFFFFFFF8
    li   t2, 0xFFFFFFF8
    bne  t1, t2, fail

    # ---- SLT / SLTU ----
    li   t0, -1
    li   t1, 1
    slt  t2, t0, t1          # signed -1 < 1 -> 1
    li   t3, 1
    bne  t2, t3, fail
    sltu t2, t0, t1          # unsigned 0xFFFFFFFF < 1 -> 0
    bne  t2, x0, fail

    # ---- load / store (word, byte, half; signed & unsigned) ----
    li   sp, 0x400
    li   t0, 0x12345678
    sw   t0, 0(sp)
    lw   t1, 0(sp)           # load-use: consumed by the next instruction
    bne  t0, t1, fail
    lbu  t2, 0(sp)           # 0x78
    li   t3, 0x78
    bne  t2, t3, fail
    lbu  t2, 1(sp)           # 0x56
    li   t3, 0x56
    bne  t2, t3, fail
    lhu  t2, 2(sp)           # 0x1234
    li   t3, 0x1234
    bne  t2, t3, fail

    li   t0, 0xF0
    sb   t0, 4(sp)
    lb   t2, 4(sp)           # sign-extended 0xFFFFFFF0
    li   t3, 0xFFFFFFF0
    bne  t2, t3, fail
    lbu  t2, 4(sp)           # 0xF0
    li   t3, 0xF0
    bne  t2, t3, fail

    li   t0, 0xBEEF
    sh   t0, 8(sp)
    lhu  t2, 8(sp)           # 0xBEEF
    li   t3, 0xBEEF
    bne  t2, t3, fail

    # ---- all branch conditions (each expected taken) ----
    li   t0, -5
    li   t1, 3
    blt  t0, t1, ok1         # signed -5 < 3
    j    fail
ok1:
    bge  t1, t0, ok2         # 3 >= -5
    j    fail
ok2:
    bltu t1, t0, ok3         # 3 < 0xFFFFFFFB (unsigned)
    j    fail
ok3:
    bgeu t0, t1, ok4         # 0xFFFFFFFB >= 3 (unsigned)
    j    fail
ok4:

    # ---- JAL / JALR (call + return) ----
    li   a0, 100
    li   a1, 23
    jal  ra, addfn           # a0 = a0 + a1
    li   t3, 123
    bne  a0, t3, fail

    # ---- AUIPC (PC-relative; two adjacent should differ by 4) ----
    auipc t0, 0
    auipc t1, 0
    sub  t2, t1, t0          # 4
    li   t3, 4
    bne  t2, t3, fail

    # ---- all checks passed ----
pass:
    li   t0, 0x0ACE
    li   t1, 0x1000          # LED_ADDR
    sw   t0, 0(t1)
    ecall

fail:
    li   t0, 0x0BAD
    li   t1, 0x1000
    sw   t0, 0(t1)
    ecall

addfn:
    add  a0, a0, a1
    ret
