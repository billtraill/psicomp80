# PicoRV32 start-up: a stack at the top of the 128 KB, a cleared .bss, main().
    .section .text.start
    .global _start
_start:
    li   sp, 0x20000
    la   a0, __bss_start
    la   a1, __bss_end
1:  bgeu a0, a1, 2f
    sw   zero, 0(a0)
    addi a0, a0, 4
    j    1b
2:  call main
3:  j    3b
