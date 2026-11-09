; Assemble with psicomp80.asm for the original 1979 monitor, which restarts
; (at 0000h) when a key comes while the CPU is not waiting in a HALT:
;   z80asm -o psicomp80.bin monitor_original.asm psicomp80.asm
KEYSAFE: equ 0
