; Memory dump for the PSI COMP80
;
; Shows 30 lines of 16 bytes: the address, the bytes in hex in pairs, and the
; same bytes as characters (a dot for those that aren't letters, digits or
; signs).  The first address is the word at 1003h, 0000h to start with, so
;     LOAD 1003  00 1D @     then RUN 1000
; starts at 1D00h.  Keys:
;     N  next page        B  back a page     (480 bytes, 30 lines)
;     D  down a line      U  up a line       (Return also goes down a line)
;     G  and four hex digits: go to that address
;     Q  (or FS) back to the monitor; RUN 1000 comes back to the same place
;
; Reading keys at any time
; ------------------------
; A key strobes NMI, and the monitor's NMI handler (0066h) jumps to 0000h unless
; the byte before the interrupted instruction is a HALT (76h); it finds that
; address on the stack.  So, as in the Game of Life, the stack pointer is kept
; in ROM, at TRAPSP: the NMI's push is lost and the handler reads the ROM word
; at 0360h, which is 101Eh.  101Dh holds 76h, so the check passes and the
; handler RETNs to KEYH with A = the key (letters 01h-1Ah).  The ROM words used
; are in the monitor, so it works with any of the ROMs.
;
; Return takes a path that calls 03C4h, which returns through the ROM words at
; 035Eh (03C4h, so it runs again) and 0360h, and arrives at KEYH with A = 03h;
; it is taken as D.  That needs E & 3Fh = 0 (no padding to do), so DE always
; points at SCRATCH, where the handler also stores the key.
;
; With SP in ROM there can be no CALL, PUSH or POP and no EXX: subroutines
; return with JP (IY).  A key abandons whatever was being drawn, and KEYH
; simply draws the page again from the new address.

TRAPSP:  equ 0362h          ; ROM words: 0360h = 101Eh (KEYH), 035Eh = 03C4h
SCRATCH: equ 1F40h          ; NMI handler writes the key here (E & 3Fh = 0)
VRAM:    equ 8000h
LINES:   equ 30
PAGE:    equ LINES*16

        org 1000h
        jp start

addr:   dw 0000h            ; first address shown
gcnt:   db 0                ; hex digits still to come after G
lcnt:   db 0                ; lines left to draw
hbyte:  db 0                ; byte being printed
tmp:    dw 0

        ds 101Dh-$
        db 76h              ; HALT opcode: makes 101Eh acceptable to the NMI handler

; ---- key handler: entered from the NMI handler with A = key code ----
keyh:                       ; 101Eh
        ld sp,TRAPSP
        ld de,SCRATCH
        ld c,a
        ld a,(gcnt)
        or a
        jr z,cmd
        dec a               ; taking an address: a hex digit
        ld (gcnt),a
        ld a,c
        sub 30h
        cp 10
        jr c,digit          ; 0-9
        ld a,c
        dec a
        cp 6
        jr nc,nodig         ; not A-F: stop taking digits
        add a,10
digit:  ld hl,(addr)
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        or l
        ld l,a
        ld (addr),hl
        jp draw
nodig:  xor a
        ld (gcnt),a
        jp draw

cmd:    ld a,c
        ld hl,(addr)
        ld bc,PAGE
        cp 0Eh              ; N
        jr z,move
        ld bc,-PAGE
        cp 02h              ; B
        jr z,move
        ld bc,16
        cp 04h              ; D
        jr z,move
        cp 03h              ; Return (or C)
        jr z,move
        ld bc,-16
        cp 15h              ; U
        jr z,move
        cp 07h              ; G
        jr z,goto
        cp 11h              ; Q
        jp z,0000h
        jp draw             ; anything else: draw it again
move:   add hl,bc
        ld (addr),hl
        jp draw
goto:   ld a,4
        ld (gcnt),a
        ld hl,0
        ld (addr),hl
        jp draw

start:
        di                  ; keys also pulse IRQ; we never want it
        ld sp,TRAPSP
        ld de,SCRATCH
        xor a
        ld (gcnt),a

; ---- draw the whole screen ----
draw:
        ld hl,VRAM          ; title line
        ld ix,title
ttl:    ld a,(ix+0)
        or a
        jr z,ttl1
        and 3Fh
        ld (hl),a
        inc hl
        inc ix
        jr ttl
ttl1:   ld hl,VRAM+5        ; the address in the title
        ld a,(addr+1)
        ld iy,ttl2
        jp hex2
ttl2:   ld a,(addr)
        ld iy,ttl3
        jp hex2
ttl3:   ld a,(gcnt)         ; a ? while taking an address
        or a
        ld a,20h
        jr z,ttl4
        ld a,3Fh
ttl4:   ld (hl),a

        ld hl,VRAM+64       ; column headings
        ld ix,heads
hd:     ld a,(ix+0)
        or a
        jr z,hd1
        and 3Fh
        ld (hl),a
        inc hl
        inc ix
        jr hd
hd1:
        ld hl,VRAM+128
        ld ix,(addr)
        ld a,LINES
        ld (lcnt),a
line:   ld (tmp),ix         ; address
        ld a,(tmp+1)
        ld iy,ln1
        jp hex2
ln1:    ld a,(tmp)
        ld iy,ln2
        jp hex2
ln2:    ld (hl),20h
        inc hl
        ld c,8              ; eight pairs of bytes
pair:   ld a,(ix+0)
        ld iy,pr1
        jp hex2
pr1:    ld a,(ix+1)
        ld iy,pr2
        jp hex2
pr2:    ld (hl),20h
        inc hl
        inc ix
        inc ix
        dec c
        jr nz,pair
        ld bc,-16
        add ix,bc
        ld c,16             ; the same sixteen as characters
chr:    ld a,(ix+0)
        cp 20h
        jr c,dot
        cp 60h
        jr nc,dot
        and 3Fh
        jr put
dot:    ld a,2Eh
put:    ld (hl),a
        inc hl
        inc ix
        dec c
        jr nz,chr
        ld (hl),20h         ; 61 columns used; clear the other 3
        inc hl
        ld (hl),20h
        inc hl
        ld (hl),20h
        inc hl
        ld a,(lcnt)
        dec a
        ld (lcnt),a
        jr nz,line

idle:   halt                ; a key arrives at KEYH
        jr idle

; ---- print A as two hex digits at HL, return with JP (IY) ----
hex2:   ld (hbyte),a
        rrca
        rrca
        rrca
        rrca
        and 0Fh
        cp 10
        jr c,hx1
        sub 9               ; 10-15 -> A-F (display codes 01h-06h)
        jr hx2
hx1:    add a,30h
hx2:    ld (hl),a
        inc hl
        ld a,(hbyte)
        and 0Fh
        cp 10
        jr c,hx3
        sub 9
        jr hx4
hx3:    add a,30h
hx4:    ld (hl),a
        inc hl
        jp (iy)

title:  db "DUMP 0000   N B PAGE   D U LINE   G ADDRESS   Q QUIT            ",0
heads:  db "ADDR 0001 0203 0405 0607 0809 0A0B 0C0D 0E0F 0123456789ABCDEF   ",0
