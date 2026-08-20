# wavedemo.s — a tiny program chosen to make two pipeline mechanisms visible in
# a waveform: (1) WB->EX forwarding, and (2) a taken-branch shadow flush.
    addi t0, x0, 5      # t0 = 5
    addi t1, t0, 3      # t1 = t0 + 3  -> needs t0 forwarded (WB->EX), = 8
    addi t2, x0, 8      # t2 = 8
    beq  t1, t2, taken  # 8 == 8 -> TAKEN: redirect, squash the next instruction
    addi t3, x0, 99     # SHADOW: fetched but must be flushed (never commits)
taken:
    addi t3, x0, 7      # t3 = 7
    li   s1, 0x1000     # LED address
    sw   t3, 0(s1)      # display 7 on the LEDs
    ecall               # halt
