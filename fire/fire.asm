; Fire for the PSI COMP80
;
; Flames rise from the bottom of the screen.  Each of the 64 x 32 characters
; has a heat, 0-63.  Two hidden rows below the screen get random heat every
; frame (each cell either 63 or 0), and every cell then takes the average of
; the three cells below it and the one two below, less a little for cooling,
; so the heat drifts up, spreads and dies away.  The heat is shown with the
; six shades the plasma uses, made from the quadrant graphics.
;
; Load at 1000h and RUN 1000.  Any key stops it: a key strobes NMI, and the
; monitor's NMI handler restarts the monitor (jumps to 0000h) because the
; program is not sitting in a HALT.
;
; The inner loop takes about 175 T-states a character, about 11 frames a
; second at the emulator's 4 MHz.

VRAM:   equ 8000h
TAB:    equ 1100h           ; new heat for each sum of four heats (built at start)
PAL:    equ 1200h           ; shade for each heat (built at start)
HEAT:   equ 1400h           ; 34 rows of 64: the screen, then two hidden rows
TABH:   equ 11h             ; high byte of TAB (PAL is the page after)
VEND:   equ 88h             ; high byte just past the screen
COOL:   equ 2               ; taken off every average

        org 1000h
        jp start

frames: dw 0                ; frame count (the test reads it)
seed:   dw 0ACE1h           ; random number state, never zero

; heat at which each shade starts, dark to light
steps:  db 2,8,16,26,40,64
shades: db 20h,41h,45h,40h,47h,4Fh

start:
        di                  ; keys also pulse IRQ; we never want it
        ld hl,TAB           ; TAB[s] = max(0, s / 4 - COOL)
btab:   ld a,l
        rrca
        rrca
        and 3Fh
        sub COOL
        jr nc,btab1
        xor a
btab1:  ld (hl),a
        inc l
        jr nz,btab

        ld hl,PAL           ; PAL[v] = shades[number of steps <= v]
        ld de,steps
        ld bc,shades
bpal:   ld a,(de)
        cp l                ; reached the next step?
        jr nz,bpal1
        inc de
        inc bc
bpal1:  ld a,(bc)
        ld (hl),a
        inc l
        ld a,l
        cp 64
        jr nz,bpal

        ld hl,HEAT          ; start cold
        ld bc,34*64
clr:    ld (hl),0
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,clr

        ld a,r              ; a different fire each time
        ld hl,seed
        xor (hl)
        jr z,frame
        ld (hl),a

frame:
        ; random heat in the two hidden rows: a 16-bit Galois LFSR, one bit a cell
        ld ix,HEAT+32*64
        ld hl,(seed)
        ld b,128
fuel:   srl h
        rr l
        sbc a,a             ; FFh if a 1 fell out, else 00h
        ld c,a
        and 0B4h            ; taps
        xor h
        ld h,a
        ld a,c
        and 63
        ld (ix+0),a
        inc ix
        djnz fuel
        ld (seed),hl

        ; each cell: TAB[left + middle + right below, + two below]
        ld ix,HEAT+64       ; IX points at the cell below the one worked out
        ld de,VRAM
        ld h,TABH
row:    ld b,64
px:     ld a,(ix-1)
        add a,(ix+0)
        add a,(ix+1)
        add a,(ix+64)
        ld l,a
        ld a,(hl)           ; new heat
        ld (ix-64),a
        ld l,a
        inc h
        ld a,(hl)           ; its shade
        dec h
        ld (de),a
        inc de
        inc ix
        djnz px
        ld a,d
        cp VEND
        jr nz,row

        ld hl,(frames)
        inc hl
        ld (frames),hl
        jp frame
