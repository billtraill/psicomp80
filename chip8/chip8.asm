; COMP80 CHIP-8
;
; A CHIP-8 interpreter for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh)
; that held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the
; RS key enters it: the monitor's NMI handler jumps to 0800h, which starts
; the CHIP-8 program at 0E00h from the beginning.
;
; The CHIP-8 display is 64 x 32 pixels, the size of the COMP80 screen, so
; each pixel is a character: a solid block (4Fh) or a space (20h).  CHIP-8
; memory is 4 KB, 0C00h-1BFFh: CHIP-8 address a is 0C00h + a, so programs,
; which start at 200h, load at 0E00h.  The hex font is copied to 0C00h.
;
; Keys while a program runs
; -------------------------
; A key strobes NMI, and the monitor's NMI handler (0066h) goes back to the
; monitor unless the byte before the interrupted address is a HALT (76h).
; As in life/life.asm, the interpreter runs with SP pointing into this ROM,
; at TRAP+2: the NMI's push is lost and the handler takes the ROM word at
; TRAP (KEYH, with a HALT byte in front of it) as the address it
; interrupted, so it returns to KEYH with A = the key.  Return goes through
; PAD_TO_NEXT_LINE (03C4h), whose CALL, RST 20h and RET use the ROM words
; below TRAP: 03CCh keeps it in its loop and KEYCR is where it returns.
;
; What was interrupted can't be carried on (HL, A and the flags are lost),
; so every CHIP-8 instruction can be started again.  The CHIP-8 registers
; are kept twice, in STA and STB.  An instruction copies the current set to
; the other, works on the copy and makes it current with a single store to
; CUR; a key before that store loses only the copy, and KEYH starts the
; instruction again.  The other writes are ones that can be done twice:
; memory written from registers (FX33, FX55), the return stack, CLS.  DRW
; first works out the new value of each character it changes into TBUF;
; then PEND marks TBUF ready, and the characters are written and the
; registers made current, which RESUME does again if a key gets in first.
;
; With SP in ROM there is no CALL, PUSH or POP while a program runs, and DE
; points either at SCRATCH (the NMI handler stores the key at (DE)) or into
; the register copy being worked on, where a stray byte does no harm.
;
; Keys: the CHIP-8 keypad    1 2 3 C   is   1 2 3 4
;                            4 5 6 D        Q W E R
;                            7 8 9 E        A S D F
;                            A 0 B F        Z X C V
; The COMP80 keyboard says when a key goes down but not when it comes up,
; so a key counts as held for HOLD ticks after it was pressed (a held key
; repeats on the host).  RS starts the program again; FS goes back to the
; monitor.
;
; Timing: there is no clock to read, so the interpreter waits SPEED loops
; before each instruction, and the 60 Hz timers count down every IPT
; instructions.  SPEED (1C00h) can be changed with the monitor.

MEM:    equ 0C00h           ; CHIP-8 address 000h
PROG:   equ 0E00h           ; CHIP-8 address 200h

SPEED:  equ 1C00h           ; delay before each instruction
MAGIC:  equ 1C01h           ; MAGICV once SPEED has been set
CUR:    equ 1C02h           ; current register set (STA or STB)
PEND:   equ 1C04h           ; register set to make current after TBUF, or 0
NEWP:   equ 1C06h           ; register set being worked on
ICOUNT: equ 1C08h           ; instructions left until the next tick
TICK:   equ 1C09h           ; counts ticks
LASTKEY: equ 1C0Ah          ; CHIP-8 key held, or 0FFh
KEYTIME: equ 1C0Bh          ; TICK when it was pressed
KEYSEQ: equ 1C0Ch           ; counts key presses
SEED:   equ 1C0Eh           ; random number state
TCOUNT: equ 1C10h           ; entries in TBUF
COLL:   equ 1C11h           ; DRW: a pixel was turned off
DX:     equ 1C12h           ; DRW: left column
DY:     equ 1C13h           ; DRW: row being drawn
NROWS:  equ 1C14h           ; DRW: rows left
SPR:    equ 1C16h           ; DRW: next sprite byte
COLX:   equ 1C18h           ; DRW: column being drawn
JMPV:   equ 1C1Ah           ; jump address for DISP
TMPW:   equ 1C1Ch
STK:    equ 1C40h           ; CHIP-8 return stack, 16 words
STA:    equ 1D00h           ; the two register sets, each in a block of 64
STB:    equ 1D40h
STHI:   equ 1Dh
SCRATCH: equ 1D80h          ; the NMI handler's (DE) (E & 3Fh = 0)
TBUF:   equ 1E00h           ; DRW: up to 120 x (address, new character)
ISTK:   equ 1FC0h           ; stack while not running a program

; register set
VF:     equ 15              ; V0-VF are bytes 0-15
IL:     equ 16              ; I
IH:     equ 17
PCL:    equ 18              ; PC
PCH:    equ 19
SPO:    equ 20              ; return stack depth
DT:     equ 21              ; delay timer
ST:     equ 22              ; sound timer
KS:     equ 23              ; KEYSEQ when FX0A last took a key
SSIZE:  equ 24

VRAM:   equ 8000h
ON:     equ 4Fh             ; solid block
OFF:    equ 20h
MAGICV: equ 0C8h
SPEEDV: equ 44
DLYIN:  equ 6
IPT:    equ 10
HOLD:   equ 20

        org 0400h

; ---------------------------------------------------------------- tables
; DISP jumps through a word in this page.

jtab:   dw h0, h1, h2, h3, h4, h5, h6, h7
        dw h8, h9, ha, hb, hc, hd, he, hf
tab8:   dw i80, i81, i82, i83, i84, i85, i86, i87
        dw commit, commit, commit, commit, commit, commit, i8e, commit

; ---------------------------------------------------------------- the loop

; Start again after a key: finish a DRW whose characters are worked out.
resume: ld sp,TRAP+2
        ld de,SCRATCH
        ld hl,(PEND)
        ld a,h
        or l
        jr z,loop
        ld iy,TBUF
        ld a,(TCOUNT)
        or a
        jr z,res2
        ld b,a
res1:   ld l,(iy+0)
        ld h,(iy+1)
        ld a,(iy+2)
        ld (hl),a
        inc iy
        inc iy
        inc iy
        djnz res1
res2:   ld hl,(PEND)
        ld (CUR),hl
        ld hl,0
        ld (PEND),hl

loop:   ld a,(SPEED)
        ld b,a
dly1:   ld c,DLYIN
dly2:   dec c
        jr nz,dly2
        djnz dly1
        ld hl,(CUR)         ; copy the registers to the other set
        ld a,l
        xor 40h
        ld e,a
        ld d,h
        ld (NEWP),de
        ld ix,STA
        or a
        jr z,cpy
        ld ix,STB
cpy:    ld bc,SSIZE
        ldir
        ld de,SCRATCH
        ld hl,ICOUNT        ; timers
        dec (hl)
        jr nz,fetch
        ld (hl),IPT
        ld hl,TICK
        inc (hl)
        ld a,(hl)
        ld hl,KEYTIME
        sub (hl)
        cp HOLD
        jr c,tk1
        ld a,0FFh           ; the key has been let go
        ld (LASTKEY),a
tk1:    ld a,(ix+DT)
        or a
        jr z,tk2
        dec (ix+DT)
tk2:    ld a,(ix+ST)
        or a
        jr z,fetch
        dec (ix+ST)

fetch:  ld l,(ix+PCL)       ; B, C = the instruction
        ld a,(ix+PCH)
        and 0Fh
        add a,MEM/256
        ld h,a
        ld b,(hl)
        inc hl
        ld c,(hl)
        ld l,(ix+PCL)
        ld h,(ix+PCH)
        inc hl
        inc hl
        ld (ix+PCL),l
        ld (ix+PCH),h
        ld a,(NEWP)         ; DE = &Vx, HL = &Vy
        ld l,a
        ld a,b
        and 0Fh
        or l
        ld e,a
        ld d,STHI
        ld a,c
        rrca
        rrca
        rrca
        rrca
        and 0Fh
        or l
        ld l,a
        ld h,STHI
        ld a,b
        rrca
        rrca
        rrca
        and 1Eh
        add a,jtab-0400h
disp:   ld (JMPV),a         ; jump through the word at 04xxh
        ld a,04h
        ld (JMPV+1),a
        ld iy,(JMPV)
        ld a,(iy+0)
        ld (JMPV),a
        ld a,(iy+1)
        ld (JMPV+1),a
        ld iy,(JMPV)
        jp (iy)

skip:   ld l,(ix+PCL)
        ld h,(ix+PCH)
        inc hl
        inc hl
        ld (ix+PCL),l
        ld (ix+PCH),h
commit: ld de,SCRATCH
        ld hl,(NEWP)
        ld (CUR),hl
        jp loop

; ---------------------------------------------------------------- 0-7

h0:     ld a,b
        or a
        jr nz,commit        ; 0nnn: machine code, not done
        ld a,c
        cp 0E0h
        jr z,cls
        cp 0EEh
        jr nz,commit
        ld a,(ix+SPO)       ; 00EE RET
        dec a
        and 0Fh
        ld (ix+SPO),a
        add a,a
        or STK&0FFh
        ld l,a
        ld h,STK/256
        ld a,(hl)
        ld (ix+PCL),a
        inc l
        ld a,(hl)
        ld (ix+PCH),a
        jr commit

cls:    ld hl,VRAM          ; 00E0 CLS
cls1:   ld (hl),OFF
        inc hl
        ld a,h
        cp 88h
        jr nz,cls1
        jr commit

h2:     ld a,(ix+SPO)       ; 2nnn CALL
        ld l,a
        inc a
        and 0Fh
        ld (ix+SPO),a
        ld a,l
        add a,a
        or STK&0FFh
        ld l,a
        ld h,STK/256
        ld a,(ix+PCL)
        ld (hl),a
        inc l
        ld a,(ix+PCH)
        ld (hl),a
h1:     ld (ix+PCL),c       ; 1nnn JP
        ld a,b
        and 0Fh
        ld (ix+PCH),a
        jr commit

h3:     ld a,(de)           ; 3xkk SE Vx,kk
        cp c
        jr z,skip
        jr commit

h4:     ld a,(de)           ; 4xkk SNE Vx,kk
        cp c
        jr nz,skip
        jr commit

h5:     ld a,(de)           ; 5xy0 SE Vx,Vy
        cp (hl)
        jp z,skip
        jr commit

h9:     ld a,(de)           ; 9xy0 SNE Vx,Vy
        cp (hl)
        jp nz,skip
        jr commit

h6:     ld a,c              ; 6xkk LD Vx,kk
        ld (de),a
        jp commit

h7:     ld a,(de)           ; 7xkk ADD Vx,kk
        add a,c
        ld (de),a
        jp commit

; ---------------------------------------------------------------- 8xyn

h8:     ld a,c
        and 0Fh
        add a,a
        add a,tab8-0400h
        jp disp

i80:    ld a,(hl)           ; LD Vx,Vy
        ld (de),a
        jp commit
i81:    ld a,(de)           ; OR
        or (hl)
        ld (de),a
        jp commit
i82:    ld a,(de)           ; AND
        and (hl)
        ld (de),a
        jp commit
i83:    ld a,(de)           ; XOR
        xor (hl)
        ld (de),a
        jp commit
i84:    ld a,(de)           ; ADD, VF = carry
        add a,(hl)
        ld (de),a
        jr setvf
i85:    ld a,(de)           ; SUB, VF = no borrow
        sub (hl)
        ld (de),a
        ccf
        jr setvf
i87:    ld a,(de)           ; SUBN: Vx = Vy - Vx
        ld b,a
        ld a,(hl)
        sub b
        ld (de),a
        ccf
        jr setvf
i86:    ld a,(de)           ; SHR, VF = bit shifted out
        srl a
        ld (de),a
        jr setvf
i8e:    ld a,(de)           ; SHL
        add a,a
        ld (de),a
setvf:  ld a,0
        rla
        ld (ix+VF),a
        jp commit

; ---------------------------------------------------------------- A-C, E

ha:     ld (ix+IL),c        ; Annn LD I,nnn
        ld a,b
        and 0Fh
        ld (ix+IH),a
        jp commit

hb:     ld a,(ix+0)         ; Bnnn JP V0,nnn
        add a,c
        ld (ix+PCL),a
        ld a,b
        adc a,0
        and 0Fh
        ld (ix+PCH),a
        jp commit

hc:     ld hl,(SEED)        ; Cxkk RND: 16-bit xorshift
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (SEED),hl
        and c
        ld (de),a
        jp commit

he:     ld a,(de)           ; Ex9E SKP, ExA1 SKNP
        and 0Fh
        ld l,a
        ld a,(LASTKEY)
        cp l
        ld a,c
        jr z,he1
        cp 0A1h             ; not held
        jp z,skip
        jp commit
he1:    cp 9Eh              ; held
        jp z,skip
        jp commit

; ---------------------------------------------------------------- D DRW

hd:     ld a,(de)
        and 63
        ld (DX),a
        ld a,(hl)
        and 31
        ld (DY),a
        ld de,SCRATCH
        ld a,c
        and 0Fh
        jp z,commit
        ld (NROWS),a
        ld l,(ix+IL)
        ld a,(ix+IH)
        and 0Fh
        add a,MEM/256
        ld h,a
        ld (SPR),hl
        xor a
        ld (COLL),a
        ld (TCOUNT),a
        ld iy,TBUF
drow:   ld a,(DY)           ; past the bottom: done
        cp 32
        jr nc,ddone
        ld l,a              ; HL = VRAM + 64 * row + DX
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(DX)
        ld (COLX),a
        or l
        ld l,a
        ld a,h
        or VRAM/256
        ld h,a
        ld bc,(SPR)
        ld a,(bc)
        inc bc
        ld (SPR),bc
        ld c,a
        ld b,8
dbit:   sla c
        jr nc,dnext
        ld a,(COLX)         ; off the right edge
        cp 64
        jr nc,dnext
        ld a,(hl)
        cp OFF
        ld a,ON
        jr z,don
        ld a,1
        ld (COLL),a
        ld a,OFF
don:    ld (iy+0),l
        ld (iy+1),h
        ld (iy+2),a
        inc iy
        inc iy
        inc iy
        ld a,(TCOUNT)
        inc a
        ld (TCOUNT),a
dnext:  inc hl
        ld a,(COLX)
        inc a
        ld (COLX),a
        djnz dbit
        ld hl,DY
        inc (hl)
        ld hl,NROWS
        dec (hl)
        jr nz,drow
ddone:  ld a,(COLL)
        ld (ix+VF),a
        ld hl,(NEWP)
        ld (PEND),hl
        jp resume

; ---------------------------------------------------------------- Fxkk

hf:     ld a,c
        cp 07h
        jr z,f07
        cp 0Ah
        jr z,f0a
        cp 15h
        jr z,f15
        cp 18h
        jr z,f18
        cp 1Eh
        jr z,f1e
        cp 29h
        jr z,f29
        cp 33h
        jr z,f33
        cp 55h
        jp z,f55
        cp 65h
        jp z,f65
        jp commit

f07:    ld a,(ix+DT)        ; LD Vx,DT
        ld (de),a
        jp commit
f15:    ld a,(de)           ; LD DT,Vx
        ld (ix+DT),a
        jp commit
f18:    ld a,(de)           ; LD ST,Vx
        ld (ix+ST),a
        jp commit
f1e:    ld a,(de)           ; ADD I,Vx
        add a,(ix+IL)
        ld (ix+IL),a
        ld a,(ix+IH)
        adc a,0
        and 0Fh
        ld (ix+IH),a
        jp commit
f29:    ld a,(de)           ; LD F,Vx: I = the digit's 5 bytes
        and 0Fh
        ld l,a
        add a,a
        add a,a
        add a,l
        ld (ix+IL),a
        ld (ix+IH),0
        jp commit

f0a:    ld a,(KEYSEQ)       ; LD Vx,K: wait for a key pressed
        cp (ix+KS)
        jr z,fwait
        ld (ix+KS),a
        ld a,(LASTKEY)
        cp 0FFh
        jr z,fwait          ; pressed and let go before: wait for another
        ld (de),a
        jp commit
fwait:  ld l,(ix+PCL)       ; do this instruction again
        ld h,(ix+PCH)
        dec hl
        dec hl
        ld (ix+PCL),l
        ld (ix+PCH),h
        jp commit

memi:   ld l,(ix+IL)        ; HL = memory at I, then back through IY
        ld a,(ix+IH)
        and 0Fh
        add a,MEM/256
        ld h,a
        jp (iy)

f33:    ld iy,f33a          ; LD B,Vx: hundreds, tens, units at I
        jr memi
f33a:   ld a,(de)
        ld b,0
f33b:   cp 100
        jr c,f33c
        sub 100
        inc b
        jr f33b
f33c:   ld (hl),b
        inc hl
        ld b,0
f33d:   cp 10
        jr c,f33e
        sub 10
        inc b
        jr f33d
f33e:   ld (hl),b
        inc hl
        ld (hl),a
        jp commit

f55:    ld iy,f55a          ; LD [I],Vx: V0-Vx to memory
        jr memi
f55a:   ld (TMPW),hl
        ld iy,(TMPW)
        ld hl,(NEWP)
        ld a,b
        and 0Fh
        inc a
        ld b,a
f55b:   ld a,(hl)
        ld (iy+0),a
        inc hl
        inc iy
        djnz f55b
        jp commit

f65:    ld iy,f65a          ; LD Vx,[I]: memory to V0-Vx
        jr memi
f65a:   ld (TMPW),hl
        ld iy,(TMPW)
        ld hl,(NEWP)
        ld a,b
        and 0Fh
        inc a
        ld b,a
f65b:   ld a,(iy+0)
        ld (hl),a
        inc hl
        inc iy
        djnz f65b
        jp commit

        ds 0800h-$

; ---------------------------------------------------------------- RS

entry:  di
        ld sp,ISTK
        ld hl,font          ; the hex digits at CHIP-8 address 000h
        ld de,MEM
        ld bc,80
        ldir
        ld a,(MAGIC)
        cp MAGICV
        jr z,ent1
        ld a,MAGICV
        ld (MAGIC),a
        ld a,SPEEDV
        ld (SPEED),a
ent1:   ld hl,VRAM          ; clear the screen
ent2:   ld (hl),OFF
        inc hl
        ld a,h
        cp 88h
        jr nz,ent2
        ld hl,(PROG)        ; no program: say how to load one
        ld a,h
        or l
        jr z,title
        ld hl,STA           ; clear the registers
        ld b,80h
ent3:   ld (hl),0
        inc hl
        djnz ent3
        ld hl,0200h
        ld (STA+PCL),hl
        ld a,(KEYSEQ)
        ld (STA+KS),a
        ld hl,STA
        ld (CUR),hl
        ld hl,0
        ld (PEND),hl
        ld a,0FFh
        ld (LASTKEY),a
        ld a,IPT
        ld (ICOUNT),a
        ld a,r
        or 1
        ld l,a
        ld h,0ACh
        ld (SEED),hl
        jp resume

title:  ld hl,ttext
tit1:   ld e,(hl)           ; screen address, then text up to 0
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or a
        jr z,tit3
tit2:   ld a,(hl)
        inc hl
        or a
        jr z,tit1
        and 3Fh
        ld (de),a
        inc de
        jr tit2
tit3:   ld de,SCRATCH       ; wait for RS or FS
        halt
        jr tit3

ttext:  dw VRAM+2*64+2
        db "CHIP-8", 0
        dw VRAM+4*64+2
        db "LOAD A PROGRAM AT 0E00 FROM THE MONITOR (FS, THEN", 0
        dw VRAM+5*64+2
        db "LOAD 0E00 OR A TAPE), THEN RS TO RUN IT.", 0
        dw VRAM+7*64+2
        db "KEYPAD   1 2 3 C   IS   1 2 3 4", 0
        dw VRAM+8*64+2
        db "         4 5 6 D        Q W E R", 0
        dw VRAM+9*64+2
        db "         7 8 9 E        A S D F", 0
        dw VRAM+10*64+2
        db "         A 0 B F        Z X C V", 0
        dw VRAM+12*64+2
        db "WHILE IT RUNS, RS STARTS IT AGAIN AND FS GOES BACK", 0
        dw VRAM+13*64+2
        db "TO THE MONITOR.  SPEED IS AT 1C00.", 0
        dw 0

font:   db 0F0h, 90h, 90h, 90h, 0F0h    ; 0
        db 20h, 60h, 20h, 20h, 70h      ; 1
        db 0F0h, 10h, 0F0h, 80h, 0F0h   ; 2
        db 0F0h, 10h, 0F0h, 10h, 0F0h   ; 3
        db 90h, 90h, 0F0h, 10h, 10h     ; 4
        db 0F0h, 80h, 0F0h, 10h, 0F0h   ; 5
        db 0F0h, 80h, 0F0h, 90h, 0F0h   ; 6
        db 0F0h, 10h, 20h, 40h, 40h     ; 7
        db 0F0h, 90h, 0F0h, 90h, 0F0h   ; 8
        db 0F0h, 90h, 0F0h, 10h, 0F0h   ; 9
        db 0F0h, 90h, 0F0h, 90h, 90h    ; A
        db 0E0h, 90h, 0E0h, 90h, 0E0h   ; B
        db 0F0h, 80h, 80h, 80h, 0F0h    ; C
        db 0E0h, 90h, 90h, 90h, 0E0h    ; D
        db 0F0h, 80h, 0F0h, 80h, 0F0h   ; E
        db 0F0h, 80h, 0F0h, 80h, 80h    ; F

; ---------------------------------------------------------------- keys

; The words the NMI handler and PAD_TO_NEXT_LINE find on the "stack".
; RST 20h returns through TRAP-6 into PAD's loop.  A second key while
; PAD or RST 20h has words pushed finds PADRET a few words further down,
; and carries on round PAD's loop from there, which comes out at KEYCR.
        db 76h              ; HALT, so the NMI handler accepts PADRET
padret: jp 03CCh            ; back into PAD's loop
        dw padret, padret, padret, padret, padret, padret, padret, padret
        dw keycr            ; TRAP-2: where PAD returns (the Return key)
TRAP:   dw keyh             ; the address the NMI handler thinks it stopped
        db 76h              ; HALT, so the handler accepts KEYH
keyh:   ld sp,TRAP+2
        ld de,SCRATCH
        ld hl,kmap
        ld b,0
kh1:    cp (hl)
        jr z,kh2
        inc hl
        inc b
        bit 4,b
        jr z,kh1
        jp resume           ; not a CHIP-8 key
        db 76h              ; HALT, in case a key comes before LD SP
keycr:  ld sp,TRAP+2
        jp resume
kh2:    ld a,b
        ld (LASTKEY),a
        ld a,(TICK)
        ld (KEYTIME),a
        ld hl,KEYSEQ
        inc (hl)
        jp resume

; the key code (letters folded to 01h-1Ah) for CHIP-8 keys 0-F
kmap:   db 18h, 31h, 32h, 33h   ; X 1 2 3
        db 11h, 17h, 05h, 01h   ; Q W E A
        db 13h, 04h, 1Ah, 03h   ; S D Z C
        db 34h, 12h, 06h, 16h   ; 4 R F V

        ds 0C00h-$, 0FFh
