# led_counter.s — board demo: increment a counter and show it on the LEDs,
# with a software delay so the upper LEDs visibly walk. Runs forever (no halt).
# Also serves as the synthesis workload so the core isn't optimized away.
#
# Delay is 0x1000 iterations (~3 cycles each) => ~12k cycles/increment. At the
# 25 MHz CPU clock that's ~0.5 ms/increment: low LEDs blur, LED8+ count visibly.

    li   s0, 0               # counter (drives LEDs)
    li   s1, 0x1000          # LED_ADDR (memory-mapped LED register)
loop:
    sw   s0, 0(s1)           # display counter
    addi s0, s0, 1           # next value
    li   t0, 0x1000          # delay loop count
delay:
    addi t0, t0, -1
    bnez t0, delay
    j    loop
