# Self-checking test. Final: HEX word (0x10000008) = 0x600D0001 on pass, 0xBAD000nn on fail nn
        lui   x1, 0x10000
        # 1) sum 1..10 = 55
        addi  x2, x0, 0
        addi  x3, x0, 10
sum:    add   x2, x2, x3
        addi  x3, x3, -1
        bne   x3, x0, sum
        addi  x10, x0, 55
        addi  x20, x0, 1
        bne   x2, x10, fail
        # 2) forwarding chain
        addi  x4, x0, 5
        add   x5, x4, x4         # 10
        sub   x6, x5, x4         # 5
        xor   x7, x6, x5         # 15
        addi  x10, x0, 15
        addi  x20, x0, 2
        bne   x7, x10, fail
        # 3) store / load + load-use + byte/half access
        li    x8, 0x12345678
        sw    x8, 16(x0)
        lw    x9, 16(x0)
        add   x9, x9, x0         # load-use
        addi  x20, x0, 3
        bne   x9, x8, fail
        lbu   x11, 17(x0)        # 0x56
        addi  x10, x0, 0x56
        addi  x20, x0, 4
        bne   x11, x10, fail
        li    x12, 0x80
        sb    x12, 20(x0)
        lb    x13, 20(x0)        # sign-extended -128
        addi  x10, x0, -128
        addi  x20, x0, 5
        bne   x13, x10, fail
        lhu   x14, 18(x0)        # 0x1234
        li    x10, 0x1234
        addi  x20, x0, 6
        bne   x14, x10, fail
        # 4) jal/jalr
        jal   x15, func
        addi  x20, x0, 7
        addi  x10, x0, 99
        bne   x16, x10, fail
        # 5) shifts/compare/lui/auipc
        li    x17, -16
        srai  x18, x17, 2        # -4
        srli  x19, x17, 28       # 15
        addi  x20, x0, 8
        addi  x10, x0, -4
        bne   x18, x10, fail
        addi  x10, x0, 15
        addi  x20, x0, 9
        bne   x19, x10, fail
        slt   x21, x17, x0       # 1
        sltu  x22, x17, x0       # 0
        add   x21, x21, x22
        addi  x10, x0, 1
        addi  x20, x0, 10
        bne   x21, x10, fail
        # 6) taken-branch flush must not execute wrong path
        addi  x23, x0, 0
        beq   x0, x0, skip
        addi  x23, x0, 1
        addi  x23, x0, 1
skip:   addi  x20, x0, 11
        bne   x23, x0, fail
pass:   lui   x24, 0x600d0
        addi  x24, x24, 1
        sw    x24, 8(x1)
done:   j     done
fail:   lui   x24, 0xbad00
        add   x24, x24, x20
        sw    x24, 8(x1)
        j     fail
func:   addi  x16, x0, 99
        jalr  x0, x15, 0
