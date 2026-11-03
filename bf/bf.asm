; COMP80 BF
;
; Brainf*** for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that held
; BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS key
; enters it: the monitor's NMI handler jumps to 0800h.
;
; The language has eight commands; every other character is a comment.
;
;   >  move the data pointer one cell right     <  one cell left
;   +  add 1 to the cell                        -  take 1 from it
;   .  print the cell as a character            ,  read a key into it
;   [  if the cell is 0, jump past the matching ]
;   ]  if the cell is not 0, jump back to the command after the matching [
;
; Cells are bytes and wrap round (255 + 1 is 0); so does the tape at its
; ends.  The tape is 768 cells at 1A00h, or 30000 at 8800h with the 32 KB
; expansion.  All eight characters can be typed on the COMP80 keyboard.
;
; Programs are typed as numbered lines, as in BASIC: a number on its own
; deletes that line.  LIST, NEW, RUN (flat out), SHOW (the program, the tape
; and the output on the screen as it runs, SPEED n setting the pause between
; commands) and STEP (the same, one command a key: Q stops, R runs on at
; SPEED).  A line typed without a number runs at once, flat out.
;
; RUN first copies the commands out of the program into CODE, one byte
; each, and finds the matching brackets: MATCH holds, for each [ and ], the
; address of its partner in CODE.
;
; Output: 10 is a new line, 32-95 print as themselves, 96-127 as capitals,
; and 128 + n prints graphics character n (143 is a solid block).  A key
; read by , is shown, and Return gives 10.
;
; Keys and screen are as in FORTH: the monitor's NMI handler echoes each key
; at (DE); RS while waiting for a key is rubout; any key while a program runs
; resets to the monitor and RS comes back with the program kept.  Line 0
; shows BF, lines 1-31 scroll.

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
PEND:   equ 0C02h           ; end of the program
SPEED:  equ 0C04h           ; SHOW's pause, about 0.8 ms a unit (20 at first)
PROG:   equ 0C06h           ; first program line
PTOP:   equ 1400h           ; the program must end below here
MAGICV: equ 0BF0Fh

CODE:   equ 1400h           ; the commands, one byte each, then 0
CODEND: equ 1600h           ; so at most 511 of them
MATCH:  equ 1600h           ; for each command, its partner if a bracket
TAPES:  equ 1A00h           ; the tape without the expansion: 768 cells
TAPESE: equ 1D00h
TAPEX:  equ 8800h           ; with it: 30000 cells
TAPEXE: equ 8800h+30000

TIB:    equ 1D00h           ; input line (80 bytes)
TAPE0:  equ 1D50h           ; first cell
TEND:   equ 1D52h           ; past the last cell
CP:     equ 1D54h           ; end of CODE while copying
MODE:   equ 1D56h           ; 0 RUN, 1 SHOW, 2 STEP
STEPS:  equ 1D58h           ; commands run
PAGE:   equ 1D5Ah           ; which 256 commands are on the screen
OMARK:  equ 1D5Ch           ; where the command marker is
TOP:    equ 1D5Eh           ; first line that scrolls
IPV:    equ 1D60h           ; IP and DP, kept for the display
DPV:    equ 1D62h
CURS:   equ 1DA0h           ; output position in screen memory
S0:     equ 1F00h           ; machine stack (the monitor uses 1Fxx)

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line
MARK:   equ 43h             ; upper half block: the markers

ROWST:  equ VRAM+1*64       ; status line
ROWCD:  equ VRAM+2*64       ; code on lines 2, 4, 6, 8; markers below each
ROWTL:  equ VRAM+11*64      ; tape label
ROWTP:  equ VRAM+12*64      ; 16 cells, marker on the line below
ROWOL:  equ VRAM+14*64      ; output label
ROWOUT: equ VRAM+15*64      ; output, scrolling, to the bottom

        org 0400h

; ---------------------------------------------------------------- terminal

; Wait for a key.  A = glyph to show at the cursor meanwhile.  Returns A =
; ASCII key, 0Dh for Return, 08h for rubout.  Keeps HL, DE.
rawkey: push de
        push hl
        ld de,(CURS)
        ld h,a
        ld a,(de)
        ld l,a
        ld a,h
        ld (de),a
        push de
        halt
keyret: pop de
        ld h,a
        ld a,l
        ld (de),a
        ld a,h
        pop hl
        pop de
        cp 0FFh
        jr nz,rk1
        ld a,8
        ret
rk1:    cp 1Fh
        jr nz,rk2
        ld a,0Dh
        ret
rk2:    cp 20h
        ret nc
        add a,40h
        ret

; Read a line into TIB, echoing it, and end it with 0.  DE ends at TIB.
accept: ld de,TIB
        ld b,0
ac1:    ld a,1Fh            ; cursor: _
        call rawkey
        cp 0Dh
        jr z,ac9
        cp 8
        jr z,ac3
        ld c,a
        ld a,b
        cp 78
        jr nc,ac1           ; line full
        ld a,c
        ld (de),a
        inc de
        inc b
        call putc
        jr ac1
ac3:    ld a,b
        or a
        jr z,ac1
        dec b
        dec de
        ld hl,(CURS)
        dec hl
        ld (hl),' '
        ld (CURS),hl
        jr ac1
ac9:    xor a
        ld (de),a
        ld de,TIB
        jr crlf

; New line, unless the cursor is at the start of one.
fresh:  ld a,(CURS)
        and 3Fh
        ret z

; New line: blank the rest of this line and move to the next.
crlf:   push de
        push hl
        ld de,(CURS)
        rst 20h             ; monitor: space at (DE)
        call PAD64
        ex de,hl
        call fixcur
        pop hl
        pop de
        ret

; Print character A (ASCII 20h-5Fh), or a screen code with PUTRAW.  Keeps
; everything but AF.
putc:   cp 40h
        jr c,putraw
        and 1Fh
putraw: push hl
        ld hl,(CURS)
        ld (hl),a
        inc hl
        call fixcur
        pop hl
        ret

; CURS = HL, scrolling the lines from TOP up if HL has run off the end.
fixcur: ld a,h
        cp 88h
        jr c,fc9
        push bc
        push de
        ld de,(TOP)
        ld hl,40h
        add hl,de
        xor a               ; BC = 8800h - HL
        sub l
        ld c,a
        ld a,88h
        sbc a,h
        ld b,a
        ldir
        push de
        rst 20h
        call PAD64
        pop hl
        pop de
        pop bc
fc9:    ld (CURS),hl
        ret

cls:    ld hl,VRAM+40h
        ld (CURS),hl
        jp CLS64

; Print the string after the CALL, up to a 0 byte.
prsi:   ex (sp),hl
        call puts
        ex (sp),hl
        ret

; Print the string at HL, up to a 0 byte.  HL ends past it.
puts:   ld a,(hl)
        inc hl
        or a
        ret z
        call putc
        jr puts

; Print HL in decimal.  Keeps BC, DE.
udot:   push bc
        push de
        ld de,10
        call udr
        pop de
        pop bc
        ret
udr:    call udiv           ; BC = HL / 10, HL = last digit
        push hl
        ld h,b
        ld l,c
        ld a,h
        or l
        call nz,udr
        pop hl
        ld a,l
        add a,'0'
        jr putc

; BC = HL / DE, HL = remainder (unsigned; DE must be below 8001h).
udiv:   ld b,h
        ld c,l
        ld hl,0
        ld a,16
ud1:    sla c
        rl b
        adc hl,hl
        sbc hl,de
        jr nc,ud2
        add hl,de
        jr ud3
ud2:    inc c
ud3:    dec a
        jr nz,ud1
        ret

; Print HL, or A, in hex.  Keeps everything but AF.
hex4:   ld a,h
        call hex2
        ld a,l
hex2:   push af
        rrca
        rrca
        rrca
        rrca
        call hex1
        pop af
hex1:   and 0Fh
        add a,90h
        daa
        adc a,40h
        daa
        jp putc

; ---------------------------------------------------------------- parsing
; DE points into the text throughout.

sk0:    inc de
skipsp: ld a,(de)
        cp ' '
        jr z,sk0
        ret

; CY if (DE) is a digit.
isdig:  ld a,(de)
        sub '0'
        cp 10
        ret

; HL = the unsigned number at DE.
getnum: ld hl,0
gn1:    call isdig
        ret nc
        push bc
        ld b,h
        ld c,l
        add hl,hl
        add hl,hl
        add hl,bc
        add hl,hl
        ld c,a
        ld b,0
        add hl,bc
        pop bc
        inc de
        jr gn1

; Compare the word at HL (ending 0) with the text: Z if the text has it,
; followed by a space or the end, and then DE is past it.
kw:     push de
kw1:    ld a,(hl)
        inc hl
        or a
        jr z,kw2
        ex de,hl
        cp (hl)
        ex de,hl
        inc de
        jr z,kw1
kw0:    pop de
        ret
kw2:    ld a,(de)
        or a
        jr z,kw3
        cp ' '
        jr nz,kw0
kw3:    pop af
        xor a
        ret

; ---------------------------------------------------------------- editing

; A line with a number: delete the line with that number, then put the new
; one in its place unless it is empty.
edit:   call getnum
        call skipsp
        push de             ; text
        push hl             ; number
        call findln
        call z,dellin
        pop bc
        pop de
        ld a,(de)
        or a
        jp z,main
        push bc             ; number
        push de             ; text
        push hl             ; where it goes
        ex de,hl
        ld bc,3
ed1:    inc c               ; size: number, size, text, 0
        ld a,(hl)
        inc hl
        or a
        jr nz,ed1
        pop hl
        push bc
        call openup
        pop bc
        pop de              ; text
        ex (sp),hl          ; HL = number, where it goes on the stack
        ex de,hl            ; DE = number, HL = text
        ex (sp),hl          ; HL = where it goes, text on the stack
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (hl),c
        inc hl
        ex de,hl
        pop hl
ed2:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        or a
        jr nz,ed2
        jp main

; HL = the first line numbered HL or more; Z if it is numbered HL.
findln: ld b,h
        ld c,l
        ld hl,PROG
fl1:    call before
        jr nc,fl9
        ld e,(hl)
        inc hl
        ld d,(hl)
        dec hl
        ex de,hl
        or a
        sbc hl,bc
        ex de,hl
        ret z
        ret nc
        call nextrec
        jr fl1
fl9:    or 1
        ret

; Delete line HL.  Keeps HL.
dellin: push hl
        ld d,h
        ld e,l              ; DE = the line
        call nextrec        ; HL = the next line
        push hl
        push de
        ex de,hl
        ld hl,(PEND)
        or a
        sbc hl,de
        ld b,h
        ld c,l              ; BC = bytes after the line
        pop de
        pop hl
        push hl
        or a
        sbc hl,de           ; size of the line
        ex (sp),hl          ; on the stack; HL = the next line
        ld a,b
        or c
        jr z,dl1
        ldir
dl1:    pop bc
        ld hl,(PEND)
        or a
        sbc hl,bc
        ld (PEND),hl
        pop hl
        ret

; Make BC bytes of room at HL.  Keeps HL.
openup: ld de,(PEND)
        push hl             ; where
        ex de,hl
        push hl             ; old end
        add hl,bc
        ld de,PTOP
        push hl
        or a
        sbc hl,de
        pop de              ; DE = new end
        jp nc,full
        ld (PEND),de
        dec de
        pop hl              ; old end
        pop bc              ; where
        push bc
        or a
        sbc hl,bc           ; bytes to move
        ld b,h
        ld c,l
        pop hl
        push hl
        add hl,bc
        dec hl              ; last byte to move
        ld a,b
        or c
        jr z,ou9
        lddr
ou9:    pop hl
        ret

; CY if HL is before the end of the program.  Keeps HL, DE.
before: push de
        ld de,(PEND)
        push hl
        or a
        sbc hl,de
        pop hl
        pop de
        ret

; HL = the line after line HL.  Keeps DE.
nextrec:
        push de
        inc hl
        inc hl
        ld e,(hl)
        ld d,0
        dec hl
        dec hl
        add hl,de
        pop de
        ret

list:   ld hl,PROG
li1:    call before
        jp nc,main
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        inc hl
        ex de,hl
        call udot
        ld a,' '
        call putc
        ex de,hl
        call puts
        call crlf
        jr li1

s_list: db "LIST",0
s_run:  db "RUN",0
s_show: db "SHOW",0
s_step: db "STEP",0
s_new:  db "NEW",0
s_speed: db "SPEED",0

; ---------------------------------------------------------------- SHOW and STEP

; Clear the screen for SHOW and STEP; the output scrolls on its own lines.
vinit:  call cls
        ld hl,ROWOL
        ld (CURS),hl
        call prsi
        db "OUTPUT",0
        ld hl,ROWOUT
        ld (CURS),hl
        ld (TOP),hl
        ld a,0FFh
        ld (PAGE),a
        ld hl,TIB
        ld (OMARK),hl
        ret

; Before each command: show where it has got to, then pause or wait for a
; key.  Keeps DE (IP) and HL (DP).
visual: push hl
        push de
        call vdraw
        ld a,(MODE)
        cp 2
        jr z,vstep
        ld a,(SPEED)
        or a
        jr z,vs9
        ld b,a
vs1:    push bc
        ld b,0
vs2:    djnz vs2
        pop bc
        djnz vs1
vs9:    pop de
        pop hl
        ret
vstep:  ld a,' '
        call rawkey
        cp 'Q'
        jr z,stop
        cp 'R'
        jr nz,vs9
        ld a,1
        ld (MODE),a
        jr vs9
stop:   call fresh
        call prsi
        db "STOPPED",0
        jp err

; Draw the status line, the code with a mark under the next command, and
; the 16 cells round the data pointer with a mark under its cell.
vdraw:  ld (IPV),de
        ld (DPV),hl
        ld hl,(CURS)
        push hl             ; the output's place
        ld hl,ROWST
        ld (CURS),hl
        call prsi
        db "IP ",0
        ld hl,(IPV)
        ld de,-CODE
        add hl,de
        push hl             ; the command's number
        call hex4
        call prsi
        db "   DP ",0
        ld hl,(DPV)
        ld de,(TAPE0)
        or a
        sbc hl,de
        push hl             ; the cell's number
        call hex4
        call prsi
        db "   CELL ",0
        ld hl,(DPV)
        ld a,(hl)
        call hex2
        call prsi
        db "   STEPS ",0
        ld hl,(STEPS)
        call hex4
        ; the tape
        ld hl,ROWTL
        ld (CURS),hl
        call prsi
        db "TAPE FROM ",0
        pop hl
        ld a,l
        and 0Fh
        ld c,a              ; place of the cell among the 16
        ld a,l
        and 0F0h
        ld l,a
        call hex4
        ld de,(TAPE0)
        add hl,de           ; first cell shown
        ld de,ROWTP
        ld (CURS),de
        ld b,16
vd1:    ld a,' '
        call putc
        ld a,(hl)
        inc hl
        call hex2
        ld a,' '
        call putc
        djnz vd1
        ld hl,ROWTP+40h     ; its marker line
        ld b,64
vd2:    ld (hl),' '
        inc hl
        djnz vd2
        ld a,c
        add a,a
        add a,a
        add a,41h
        ld l,a              ; ROWTP+40h is 8340h
        ld h,(ROWTP+40h)/256
        ld (hl),MARK
        inc hl
        ld (hl),MARK
        ; the code, if this command is on a different page of 256
        pop hl              ; the command's number
        ld a,(PAGE)
        cp h
        call nz,vcode
        ld de,(OMARK)
        ld a,' '
        ld (de),a
        ld a,l              ; line 3 + 2 * (L / 64), column L mod 64
        and 0C0h
        rlca
        rlca                ; L / 64
        add a,a
        add a,3
        ld e,a
        ld d,0
        ex de,hl            ; HL = line, DE = number
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,e
        and 3Fh
        or l
        ld l,a
        ld a,h
        add a,VRAM/256
        ld h,a
        ld (hl),MARK
        ld (OMARK),hl
        pop hl
        ld (CURS),hl
        ld de,(IPV)
        ld hl,(DPV)
        ret

; Draw page H of the code (256 commands) on lines 2-9.  Keeps HL.
vcode:  push hl
        ld a,h
        ld (PAGE),a
        ld l,0
        ld de,CODE
        add hl,de           ; the page's first command
        ld de,ROWCD
        ld c,4
vc1:    ld b,64
vc2:    ld a,(hl)
        or a
        jr z,vc3
        inc hl
        cp 40h
        jr c,vc4
        and 1Fh
        jr vc4
vc3:    ld a,' '            ; past the end
vc4:    ld (de),a
        inc de
        djnz vc2
        ld b,64             ; and a blank marker line
vc5:    ld a,' '
        ld (de),a
        inc de
        djnz vc5
        dec c
        jr nz,vc1
        pop hl
        ret

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If BF was waiting for
; a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) BF.

entry:  ex (sp),hl
        push de
        ld de,keyret
        or a
        sbc hl,de
        add hl,de           ; keeps Z
        pop de
        ex (sp),hl
        jr nz,warm
        ld a,0FFh
        ret

warm:   ld sp,S0
        ld hl,(MAGIC)
        ld de,MAGICV
        or a
        sbc hl,de
        call nz,new
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " BF",0
        call crlf
        call cls
        ; With the 32 KB expansion, 8800h is RAM; without it, it is the
        ; screen again.
        ld hl,TAPES
        ld de,TAPESE
        ld a,(VRAM)
        ld c,a
        cpl
        ld (TAPEX),a
        ld a,(VRAM)
        cp c
        ld a,c
        ld (VRAM),a
        jr nz,wm1
        ld hl,TAPEX
        ld de,TAPEXE
wm1:    ld (TAPE0),hl
        ld (TEND),de
        ex de,hl
        or a
        sbc hl,de
        call prsi
        db "TAPE OF ",0
        call udot
        call prsi
        db " CELLS",0
        call crlf

main:   ld sp,S0
        ld hl,VRAM+40h
        ld (TOP),hl
        xor a
        ld (MODE),a
        call accept
        call skipsp
        or a
        jr z,main
        call isdig
        jp c,edit
        ld hl,s_list
        call kw
        jp z,list
        ld hl,s_new
        call kw
        jr z,newc
        ld hl,s_speed
        call kw
        jr z,speedc
        ld c,0
        ld hl,s_run
        call kw
        jr z,runc
        inc c
        ld hl,s_show
        call kw
        jr z,runc
        inc c
        ld hl,s_step
        call kw
        jr z,runc
        ; anything else is a program to run at once
        ld hl,CODE
        ld (CP),hl
        ex de,hl
        call copy
        jp go

newc:   call new
        jr main

new:    ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,PROG
        ld (PEND),hl
        ld a,20
        ld (SPEED),a
        ret

speedc: call skipsp
        call getnum
        ld a,l
        ld (SPEED),a
        jp main

; RUN, SHOW or STEP (C = 0, 1, 2): copy the commands out of the program.
runc:   ld a,c
        ld (MODE),a
        ld hl,CODE
        ld (CP),hl
        ld hl,PROG
rc1:    call before
        jr nc,go
        push hl
        inc hl
        inc hl
        inc hl
        call copy
        pop hl
        call nextrec
        jr rc1

; Copy the commands in the text at HL to CP.
copy:   ld a,(hl)
        or a
        ret z
        inc hl
        push hl
        ld hl,cmds
        ld b,8
cy1:    cp (hl)
        jr z,cy2
        inc hl
        djnz cy1
        pop hl
        jr copy
cy2:    pop hl
        ld de,(CP)
        ld (de),a
        inc de
        ld (CP),de
        ld a,d
        cp CODEND/256
        jr c,copy
        call prsi
        db "TOO LONG",0
        jp err

cmds:   db "+-<>[].,"

; HL = MATCH's entry for the command at HL.  Keeps DE.
mslot:  ld bc,-CODE
        add hl,bc
        add hl,hl
        ld bc,MATCH
        add hl,bc
        ret

; Match the brackets, clear the tape and run CODE.
go:     ld hl,(CP)
        ld (hl),0
        ld hl,0
        push hl             ; marks the bottom of the [ stack
        ld hl,CODE
mt1:    ld a,(hl)
        or a
        jr z,mt9
        cp '['
        jr nz,mt2
        push hl
        jr mt4
mt2:    cp ']'
        jr nz,mt4
        pop de              ; its [
        ld a,d
        or e
        jp z,nolb
        push hl
        call mslot
        ld (hl),e
        inc hl
        ld (hl),d
        pop hl
        push hl
        ex de,hl
        call mslot
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ex de,hl
mt4:    inc hl
        jr mt1
mt9:    pop de
        ld a,d
        or e
        jp nz,norb
        ld hl,(TEND)        ; clear the tape
        ld de,(TAPE0)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        dec bc
        ld h,d
        ld l,e
        inc de
        ld (hl),0
        ldir
        ld hl,0
        ld (STEPS),hl
        ld a,(MODE)
        or a
        call nz,vinit
        ld de,CODE          ; DE = IP
        ld hl,(TAPE0)       ; HL = DP

exec:   ld a,(de)
        or a
        jp z,done
        ld a,(MODE)
        or a
        call nz,visual
        ld a,(de)
        cp '+'
        jr nz,x1
        inc (hl)
        jr next
x1:     cp '-'
        jr nz,x2
        dec (hl)
        jr next
x2:     cp '>'
        jr nz,x3
        inc hl
        push de
        ld de,(TEND)
        or a
        sbc hl,de
        add hl,de
        pop de
        jr nz,next
        ld hl,(TAPE0)
        jr next
x3:     cp '<'
        jr nz,x4
        push de
        ld de,(TAPE0)
        or a
        sbc hl,de
        add hl,de
        pop de
        jr nz,x3a
        ld hl,(TEND)
x3a:    dec hl
        jr next
x4:     cp '.'
        jr nz,x5
        ld a,(hl)
        call outc
        jr next
x5:     cp ','
        jr nz,x6
        ld a,1Fh
        call rawkey
        cp 0Dh
        jr nz,x5a
        ld a,10
x5a:    ld (hl),a
        call outc
        jr next
x6:     ld c,a
        ld a,(hl)
        or a
        ld a,c
        jr z,x7
        cp ']'              ; cell not 0: ] jumps back
        jr x8
x7:     cp '['              ; cell 0: [ jumps on
x8:     jr nz,next
        push hl
        ex de,hl
        call mslot
        ld e,(hl)
        inc hl
        ld d,(hl)
        pop hl
next:   inc de
        ld bc,(STEPS)
        inc bc
        ld (STEPS),bc
        jp exec

done:   ld a,(MODE)
        or a
        call nz,vdraw
        call fresh
        jp main

nolb:   call prsi
        db "NO [",0
        jr err
norb:   call prsi
        db "NO ]",0
err:    call crlf
        jp main
full:   call prsi
        db "FULL",0
        jr err

; Print the byte A as BF output.
outc:   cp 10
        jp z,crlf
        cp 80h
        jr nc,oc2
        cp 20h
        ret c
        cp 60h
        jp c,putc
        sub 20h             ; lower case as capitals
        jp putc
oc2:    add a,0C0h          ; 128 + n: graphics character n
        and 7Fh
        jp putraw

part2_end:
        ds 0C00h-$,0FFh
