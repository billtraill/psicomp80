; Conway's Game of Life for the PSI COMP80
;
; 128 x 64 cells on the 64 x 32 screen, four cells per character using the
; quadrant block graphics. The board wraps at the edges.
;
; Load at 1000h and RUN 1000.  Keys:  R = new random board,  P = pause / resume,
; S = stop (back to the monitor).
;
; Reading keys while running
; --------------------------
; A key strobes NMI, and the monitor's NMI handler (0066h) jumps to 0000h unless
; the byte before the interrupted instruction is a HALT (76h).  It finds the
; interrupted address on the stack.  So while the program runs, SP points into
; ROM at TRAPSP: the NMI's push is lost (ROM ignores writes) and the handler
; reads the ROM word at 06B6h, which is 1013h, as the return address.  1012h
; holds 76h, so the check passes and the handler RETNs to KEYH with A = key
; code (letters folded to 01h-1Ah).  The Return key takes a path that calls
; 03C4h; its RET pops the ROM word at 06B4h (127Eh), which jumps back to RUN.
;
; Rules this imposes on code that runs with SP = TRAPSP:
;   - no CALL / PUSH / POP (the stack is ROM)
;   - DE always points to SCRATCH (the NMI handler stores the key at (DE))
;   - no EXX (it would swap DE)
; A key aborts whatever was in progress, so the generation is only committed
; by a single store to CUR at the end, and RUN restarts it from CUR.

TRAPSP:  equ 06B8h          ; ROM words: 06B6h = 1013h (KEYH), 06B4h = 127Eh
PSTACK:  equ 1FC0h          ; real stack, used while paused
SCRATCH: equ 1F40h          ; NMI handler writes the key here (E & 3Fh = 0)
VRAM:    equ 8000h
SPAGE:   equ 13h            ; column sums, indexed 0..129
BUF0:    equ 1700h          ; two 1 KB boards: 64 rows x 16 bytes, MSB = left
BUF1:    equ 1B10h          ; (gaps after each catch the end-of-board write)

        org 1000h
        jp start

cur:    dw BUF0             ; board being shown
nxtv:   dw BUF1             ; board being built
seed:   dw 0ACE1h           ; xorshift state, never zero
ycnt:   db 0
pgu:    db 14h              ; row buffer pages: row above,
pgc:    db 15h              ;   this row,
pgd:    db 16h              ;   row below (each indexed 0..129, wrapped)

        ds 1012h-$
        db 76h              ; HALT opcode: makes 1013h acceptable to the NMI handler

; ---- key handler: entered from the NMI handler with A = key code ----
keyh:                       ; 1013h
        ld sp,PSTACK
        ld de,SCRATCH
        cp 12h              ; R
        jp z,randomize
        cp 13h              ; S
        jp z,0000h
        cp 10h              ; P
        jp nz,run           ; anything else: carry on

        ld hl,VRAM+58       ; show PAUSED in the top right corner
        ld (hl),10h
        inc hl
        ld (hl),01h
        inc hl
        ld (hl),15h
        inc hl
        ld (hl),13h
        inc hl
        ld (hl),05h
        inc hl
        ld (hl),04h
pwait:
        halt                ; NMI wakes us with A = key (normal stack here)
        ld de,SCRATCH
        cp 12h
        jp z,randomize
        cp 13h
        jp z,0000h
        cp 10h
        jr nz,pwait
        jp run

; ---- start / random board ----
start:
        di                  ; keys also pulse IRQ; we never want it
randomize:
        ld sp,TRAPSP
        ld de,SCRATCH
        ld a,r              ; mix in the refresh counter: varies with key timing
        ld hl,(seed)
        xor l
        ld l,a
        or h
        jr nz,seedok
        inc l
seedok:
        ld ix,(cur)
        ld bc,1024
rfill:                      ; each byte = r1 & (r2 | r3): 3/8 of cells alive
        ld a,h              ; xorshift16 (7,9,8), result in A and H
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
        ld (ix+0),a

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
        or (ix+0)
        ld (ix+0),a

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
        and (ix+0)
        ld (ix+0),a

        inc ix
        dec bc
        ld a,b
        or c
        jr nz,rfill
        ld (seed),hl

; ---- main loop: draw the board, then build the next generation ----
run:
        ld sp,TRAPSP
        ld de,SCRATCH

        ; draw: each character shows a 2 x 2 block of cells from two board rows
        ld ix,(cur)
        ld bc,VRAM
        ld iy,dtmp
dbyte:
        ld a,(ix+0)         ; top row byte
        ld (iy+0),a
        ld a,(ix+16)        ; bottom row byte
        ld (iy+1),a
        inc ix

        xor a               ; char 1: A = TL TR BL BR in bits 3..0
        rl (iy+0)
        rla
        rl (iy+0)
        rla
        rl (iy+1)
        rla
        rl (iy+1)
        rla
        add a,dtab & 0FFh
        ld l,a
        ld h,dtab >> 8
        ld a,(hl)
        ld (bc),a
        inc bc

        xor a               ; char 2
        rl (iy+0)
        rla
        rl (iy+0)
        rla
        rl (iy+1)
        rla
        rl (iy+1)
        rla
        add a,dtab & 0FFh
        ld l,a
        ld h,dtab >> 8
        ld a,(hl)
        ld (bc),a
        inc bc

        xor a               ; char 3
        rl (iy+0)
        rla
        rl (iy+0)
        rla
        rl (iy+1)
        rla
        rl (iy+1)
        rla
        add a,dtab & 0FFh
        ld l,a
        ld h,dtab >> 8
        ld a,(hl)
        ld (bc),a
        inc bc

        xor a               ; char 4
        rl (iy+0)
        rla
        rl (iy+0)
        rla
        rl (iy+1)
        rla
        rl (iy+1)
        rla
        add a,dtab & 0FFh
        ld l,a
        ld h,dtab >> 8
        ld a,(hl)
        ld (bc),a
        inc bc

        ld a,c              ; end of a screen line?
        and 3Fh
        jp nz,dbyte
        ld l,16             ; skip the bottom row we just used
dskip:
        inc ix
        dec l
        jr nz,dskip
        ld a,b
        cp (VRAM+800h) >> 8
        jp nz,dbyte

        ; next generation: work out which board to build into
        ld a,(cur+1)
        cp BUF0 >> 8
        ld hl,BUF1
        jr z,gotnxt
        ld hl,BUF0
gotnxt:
        ld (nxtv),hl
        ld ix,(nxtv)        ; IX walks the new board; one bit per cell
        ld (ix+0),1         ; sentinel: after 8 shifts it falls out into carry

        ; prime the row buffers with rows 63 (above) and 0 (this row)
        ld hl,(cur)
        ld bc,63*16
        add hl,bc
        ld b,h
        ld c,l
        ld a,(pgu)
        ld h,a
        ld iy,prime2
        jp unpack
prime2:
        ld bc,(cur)
        ld a,(pgc)
        ld h,a
        ld iy,prime3
        jp unpack
prime3:
        xor a
        ld (ycnt),a

genrow:
        ; unpack row y+1 (wrapping) into the "below" buffer
        ld a,(ycnt)
        inc a
        and 63
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld bc,(cur)
        add hl,bc
        ld b,h
        ld c,l
        ld a,(pgd)
        ld h,a
        ld iy,colsum
        jp unpack

colsum:                     ; S[i] = above[i] + this[i] + below[i], i = 0..129
        ld a,(pgu)
        ld (csu+1),a
        ld a,(pgc)
        ld (csc+1),a
        ld a,(pgd)
        ld (csd+1),a
        ld l,0
csloop:
csu:    ld h,0
        ld a,(hl)
csc:    ld h,0
        add a,(hl)
csd:    ld h,0
        add a,(hl)
        ld h,SPAGE
        ld (hl),a
        inc l
        ld a,l
        cp 130
        jr nz,csloop

        ; T = S[x-1] + S[x] + S[x+1] counts the cell itself too:
        ; alive next if T = 3, or T = 4 and the cell is alive now
        ld a,(pgc)
        ld c,a
        ld b,SPAGE
        ld l,1
cell:
        ld h,b
        dec l
        ld a,(hl)
        inc l
        add a,(hl)
        inc l
        add a,(hl)
        dec l
        cp 3
        jr z,alive
        cp 4
        jr nz,dead
        ld h,c
        ld a,(hl)
        rra                 ; carry = this cell
        jr store
alive:
        scf
        jr store
dead:
        or a
store:
        rl (ix+0)
        jr nc,cnext
        inc ix              ; byte full (sentinel came out)
        ld (ix+0),1
cnext:
        inc l
        ld a,l
        cp 129
        jr nz,cell

        ; rotate buffers: above <- this, this <- below, below <- old above
        ld a,(pgu)
        ld h,a
        ld a,(pgc)
        ld (pgu),a
        ld a,(pgd)
        ld (pgc),a
        ld a,h
        ld (pgd),a

        ld a,(ycnt)
        inc a
        ld (ycnt),a
        cp 64
        jp nz,genrow

        ld hl,(nxtv)        ; commit: one store, so a key can't leave it half done
        ld (cur),hl
        jp run

        ds 127Eh-$
        jp run              ; 127Eh: Return key lands here (see top)

; ---- unpack 16 bytes at BC into page H, cells 1..128 as 0/1, then wrap
;      0 = 128 and 129 = 1.  Returns with JP (IY). ----
unpack:
        ld l,1
ubyte:
        ld a,(bc)
        inc bc
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        rlca
        ld (hl),0
        rl (hl)
        inc l
        ld a,l
        cp 129
        jr nz,ubyte
        ld l,128
        ld a,(hl)
        ld l,0
        ld (hl),a
        ld l,1
        ld a,(hl)
        ld l,129
        ld (hl),a
        jp (iy)

dtmp:   ds 2                ; draw: top / bottom bytes being shifted out

        ; 2 x 2 cell pattern (TL TR BL BR) -> screen byte. The quadrant
        ; graphics are 40h + TL*1 + TR*2 + BR*4 + BL*8; empty is a text space
        ; because graphics 40h is a checkerboard.
        ds (($ + 15) & 0FFF0h) - $
dtab:   db 20h, 44h, 48h, 4Ch, 42h, 46h, 4Ah, 4Eh
        db 41h, 45h, 49h, 4Dh, 43h, 47h, 4Bh, 4Fh

progend:
