; Assemble with psicomp80.asm for the key-safe monitor, which ignores a key
; that comes while the CPU is not waiting in a HALT, so a running program is
; never restarted by a key:
;   z80asm -o psicomp80_ks.bin monitor_keysafe.asm psicomp80.asm
KEYSAFE: equ 1
