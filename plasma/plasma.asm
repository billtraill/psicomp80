; Plasma for the PSI COMP80
;
; Fills the 64 x 32 screen with a moving plasma: each character is the sum of
; four sine waves (two across, one down, one diagonal), looked up in a table
; of shading characters made from the quadrant graphics.  The waves drift a
; little every frame, so the bands of shading flow across the screen.
;
; Load at 1000h and RUN 1000.  Any key stops it: a key strobes NMI, and the
; monitor's NMI handler restarts the monitor (jumps to 0000h) because the
; program is not sitting in a HALT.
;
; The inner loop takes 89 T-states a character, about 21 frames a second at
; the emulator's 4 MHz (10 on a real 2 MHz COMP80).

VRAM:   equ 8000h
SINT:   equ 1100h           ; sine table, 0..63 (in the program)
PAL:    equ 1200h           ; shade for each sum, built at start (SINT + 100h)
COLS:   equ 13C0h           ; this frame's two across-waves for x = 0..63
SINH:   equ 11h             ; high byte of SINT (PAL is the page after)
VEND:   equ 88h             ; high byte just past the screen

        org 1000h
        jp start

frames: dw 0                ; frame count (the test reads it)
t1:     db 0                ; wave phases
t2:     db 0
t3:     db 0
t5:     db 0
cyc:    db 0                ; shade offset, cycles the bands
ridx:   db 0                ; down-wave index for the row being drawn
didx:   db 0                ; diagonal index at the start of the row

; 16 shades, dark to light and back, so the bands have no hard edge
ramp:   db 20h,20h,41h,41h,45h,40h,47h,4Fh
        db 4Fh,4Fh,47h,40h,45h,41h,41h,20h

start:
        ld hl,PAL           ; PAL[v] = ramp[(v / 4) mod 16]
bpal:   ld a,l
        rrca
        rrca
        and 0Fh
        ld e,a
        ld d,0
        push hl
        ld hl,ramp
        add hl,de
        ld a,(hl)
        pop hl
        ld (hl),a
        inc l
        jr nz,bpal

frame:
        ; COLS[x] = sin(4x + t1) + sin(3x - t2)
        ld a,(t1)
        ld b,a
        ld a,(t2)
        neg
        ld c,a
        ld hl,COLS
        ld d,SINH
bcol:   ld e,b
        ld a,(de)
        ld e,c
        ex de,hl
        add a,(hl)
        ex de,hl
        ld (hl),a
        ld a,b
        add a,4
        ld b,a
        ld a,c
        add a,3
        ld c,a
        inc l
        jr nz,bcol

        exx
        ld hl,VRAM          ; HL' walks the screen
        exx
        ld a,(t3)
        ld (ridx),a
        ld a,(t5)
        ld (didx),a
row:
        ld h,SINH      ; B = sin(7y + t3) + cyc
        ld a,(ridx)
        ld l,a
        add a,7
        ld (ridx),a
        ld a,(cyc)
        add a,(hl)
        ld b,a
        ld a,(didx)           ; C = diagonal index, 2x + 5y + t5
        ld c,a
        add a,5
        ld (didx),a
        ld de,COLS
px:
        ld a,(de)           ; across-waves
        add a,b             ; + down-wave
        ld h,SINH
        ld l,c
        add a,(hl)          ; + diagonal wave
        inc h               ; H = high PAL
        ld l,a
        ld a,(hl)           ; shade
        exx
        ld (hl),a
        inc hl
        exx
        inc c
        inc c
        inc e               ; E runs C0h..FFh, so zero ends the row
        jr nz,px
        exx
        ld a,h
        exx
        cp VEND
        jr nz,row

        ld hl,t1            ; move the waves on
        ld a,(hl)
        add a,3
        ld (hl),a
        inc hl
        ld a,(hl)
        add a,2
        ld (hl),a
        inc hl
        ld a,(hl)
        sub 2
        ld (hl),a
        inc hl
        ld a,(hl)
        add a,3
        ld (hl),a
        inc hl
        inc (hl)            ; cyc
        ld hl,(frames)
        inc hl
        ld (frames),hl
        jp frame

        ds SINT-$
; sine table: round(31.5 + 31.5 sin(2 pi i / 256)), 0..63
        db 32,32,33,34,35,35,36,37,38,38,39,40,41,41,42,43
        db 44,44,45,46,46,47,48,48,49,50,50,51,51,52,53,53
        db 54,54,55,55,56,56,57,57,58,58,59,59,59,60,60,60
        db 61,61,61,61,62,62,62,62,62,63,63,63,63,63,63,63
        db 63,63,63,63,63,63,63,63,62,62,62,62,62,61,61,61
        db 61,60,60,60,59,59,59,58,58,57,57,56,56,55,55,54
        db 54,53,53,52,51,51,50,50,49,48,48,47,46,46,45,44
        db 44,43,42,41,41,40,39,38,38,37,36,35,35,34,33,32
        db 32,31,30,29,28,28,27,26,25,25,24,23,22,22,21,20
        db 19,19,18,17,17,16,15,15,14,13,13,12,12,11,10,10
        db 9,9,8,8,7,7,6,6,5,5,4,4,4,3,3,3
        db 2,2,2,2,1,1,1,1,1,0,0,0,0,0,0,0
        db 0,0,0,0,0,0,0,0,1,1,1,1,1,2,2,2
        db 2,3,3,3,4,4,4,5,5,6,6,7,7,8,8,9
        db 9,10,10,11,12,12,13,13,14,15,15,16,17,17,18,19
        db 19,20,21,22,22,23,24,25,25,26,27,28,28,29,30,31
