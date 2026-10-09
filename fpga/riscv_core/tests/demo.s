# Board demo: counter on LEDR/HEX, load-use test result on LEDG
        lui   x1, 0x10000        # x1 = 0x10000000 (I/O base)
        addi  x2, x0, 0          # counter
loop:   addi  x2, x2, 1
        sw    x2, 0(x1)          # LEDR
        sw    x2, 8(x1)          # HEX
        sw    x2, 0(x0)          # store to RAM
        lw    x4, 0(x0)          # load back (load-use hazard below)
        add   x5, x4, x4         # x5 = 2*count
        sw    x5, 4(x1)          # LEDG
        lui   x3, 0x200          # ~2M iterations delay
delay:  addi  x3, x3, -1
        bne   x3, x0, delay
        jal   x0, loop
