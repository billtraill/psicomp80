; Scrolling banner for the PSI COMP80
;
; A message in big letters scrolls from right to left across the middle of
; the screen, round and round.  The letters are 5 x 7, drawn with each dot
; two characters wide and one tall (12 x 10 points on the screen, so nearly
; square).  The scroll moves a quarter of a dot, half a character, at a time:
; a character can show the left half of one dot and the right half of the
; next, using the quadrant graphics (left half 49h, right half 46h).
;
; The message is ASCII at 1400h, ending with a 00 byte, up to 255 characters;
; lower case is shown as capitals.  To change it, before RUN 1000:
;     LOAD 1400  [HELLO THERE   ]  00 @
; ([ and ] switch LOAD to typing text and back.  It stores letters as the
; screen codes 01h-1Ah, which are taken as A-Z too, and keeps the [ and ]
; themselves, as 1Bh and 1Dh, which are left out.)  The speed is the byte at
; 1005h: the pause between steps, 0 fastest.
;
; Load at 1000h and RUN 1000.  Any key stops it: a key strobes NMI, and the
; monitor's NMI handler restarts the monitor (jumps to 0000h) because the
; program is not sitting in a HALT.

VRAM:   equ 8000h
FONT:   equ 1200h           ; 5 bytes a character, 20h-5Fh
SHADE:  equ 1340h           ; the four half-and-half characters
SHADEH: equ 13h             ; high byte of SHADE
MSG:    equ 1400h           ; the message
COLS:   equ 1500h           ; the message as columns of dots, bit 0 the top
TOP:    equ 12              ; first screen row of the letters
WRAP:   equ 34              ; columns copied to the end so the screen wraps round

        org 1000h
        jp start

frames: dw 0                ; frame count (the test reads it)
speed:  db 12               ; 1005h: pause between steps
off:    dw 0                ; scroll position, in quarter dots
ncol:   dw 0                ; columns in the message
qpos:   dw 0                ; quarter dot at the left of the column being drawn

start:
        di                  ; keys also pulse IRQ; we never want it
        ld hl,VRAM          ; clear the screen
        ld bc,2048
cls:    ld (hl),20h
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,cls

        ld hl,VRAM+(TOP-1)*64   ; rules above and below: lower and upper halves
        ld de,VRAM+(TOP+7)*64
        ld b,64
rule:   ld (hl),4Ch
        ld a,43h
        ld (de),a
        inc hl
        inc de
        djnz rule

        ld hl,texts         ; title and help: address, then text up to 00
txt:    ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,d
        or a
        jr z,build
txt1:   ld a,(hl)
        inc hl
        or a
        jr z,txt
        and 3Fh
        ld (de),a
        inc de
        jr txt1

build:                      ; COLS = five columns for each letter, then a gap
        ld hl,MSG
        ld de,COLS
        ld b,255
bl:     ld a,(hl)
        or a
        jr z,bdone
        inc hl
        and 7Fh
        cp 60h
        jr c,bl1
        sub 20h             ; lower case to capitals
bl1:    cp 20h
        jr nc,bl2
        cp 1Bh              ; LOAD keeps the [ and ] that switch it to text
        jr z,bl
        cp 1Dh              ;   and back: leave them out
        jr z,bl
        add a,40h           ; 01h-1Ah: letters as LOAD's text mode stores them
bl2:    push hl
        push bc
        sub 20h
        ld l,a              ; FONT + 5 * (A - 20h)
        ld h,0
        ld c,l
        ld b,h
        add hl,hl
        add hl,hl
        add hl,bc
        ld bc,FONT
        add hl,bc
        ld bc,5
        ldir
        xor a
        ld (de),a
        inc de
        pop bc
        pop hl
        djnz bl
bdone:  ld hl,-COLS
        add hl,de
        ld a,h
        or l
        jr nz,bd1
        xor a               ; empty message: one blank column
        ld (de),a
        inc de
        inc hl
bd1:    ld (ncol),hl
        ld hl,COLS          ; repeat the start after the end
        ld bc,WRAP
        ldir
        ld hl,0
        ld (off),hl

frame:
        ld hl,(off)
        ld (qpos),hl
        ld iy,VRAM+TOP*64
        ld b,64             ; screen columns
col:    push bc
        ld bc,COLS
        ld hl,(qpos)        ; left half: column qpos / 4
        srl h
        rr l
        srl h
        rr l
        add hl,bc
        ld d,(hl)
        ld hl,(qpos)        ; right half: column (qpos + 1) / 4
        inc hl
        srl h
        rr l
        srl h
        rr l
        add hl,bc
        ld e,(hl)
        ld hl,(qpos)
        inc hl
        inc hl
        ld (qpos),hl
        ld bc,64
        ld h,SHADEH
        ld a,7              ; seven rows
rows:   ex af,af'
        ld a,10h            ; 40h + 2 * right + left
        srl e
        rla
        srl d
        rla
        ld l,a
        ld a,(hl)
        ld (iy+0),a
        add iy,bc
        ex af,af'
        dec a
        jr nz,rows
        ld bc,1-7*64        ; back to the top, one column on
        add iy,bc
        pop bc
        djnz col

        ld hl,(off)         ; scroll a quarter dot
        inc hl
        ld (off),hl
        ld de,(ncol)        ; round again after 4 * ncol quarters
        ex de,hl
        add hl,hl
        add hl,hl
        or a
        sbc hl,de
        jr nz,next
        ld (off),hl
next:   ld hl,(frames)
        inc hl
        ld (frames),hl
        ld a,(speed)        ; pause
        or a
        jr z,frame
pause:  ld b,0
p1:     djnz p1
        dec a
        jr nz,pause
        jp frame

texts:  dw VRAM
        db " BANNER",0
        dw VRAM+28*64
        db "THE MESSAGE IS AT 1400, ENDING WITH 00; THE SPEED AT 1005",0
        dw VRAM+29*64
        db "ANY KEY STOPS IT",0
        dw 0

        ds FONT-$
        include "font.inc"
        ds SHADE-$
        db 20h,49h,46h,4Fh  ; neither, left, right, both

        ds MSG-$
        db "HELLO FROM THE PSI COMP80, IN Z80 MACHINE CODE.     ",0
