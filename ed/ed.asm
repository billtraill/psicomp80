; COMP80 ED
;
; A line editor in the style of the Unix ed and the editors of its time,
; written for the PSI COMP80 in the 2 KB of ROM (0400h-0BFFh) that held
; BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS key
; enters it: the monitor's NMI handler jumps to 0800h.
;
; The text is a list of lines, each ending in 0Dh, with a 0 after the last.
; There is a current line, dot.  A command is an optional address or range
; and a letter:
;   addresses  n  .  $  /PATTERN/ (the next line containing it, wrapping)
;              +n and -n after any of them, or alone (from dot);
;              a,b is a range; , or % alone is 1,$
;   A  I  C    append after, insert before, change: lines typed in until
;              one that is just a full stop
;   D P N      delete, print, print with numbers
;   V          view the 30 lines round dot (or the address), > at it
;   M d  T d   move or copy the range to after line d
;   J          join (default . and the next)
;   S/OLD/NEW/ change the first OLD in each line; G after it, every one
;   G/PAT/cmd  run cmd on each line containing PAT (P if there is none)
;   =          the line number ($ unless an address is given)
;   E          empty the buffer;  W  how to save it on tape;  R  take in a
;              buffer read from tape;  Q  the monitor
;   an address alone prints that line; Return alone, the next one.
; Mistakes print ? and what was wrong.  A key while ED is busy resets to the
; monitor; RS comes back with the text kept.
;
; The text is kept from BEG to the 0 at ENDP, and must end below TOP: from
; 0C10h to 1BFFh, or 8800h-FFEFh with the 32 KB expansion.  The header at
; 0C00h keeps it over a reset.  Keys and screen are handled as in COMP80
; FORTH and VTL-2: line 0 shows ED; lines 1-31 scroll.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the buffer below is valid
ENDP:   equ 0C02h           ; the 0 after the last line
BEG:    equ 0C04h           ; first line
TOP:    equ 0C06h           ; the text must end below here
DOT:    equ 0C08h           ; the current line
MAGICV: equ 0EDEDh
SMALL:  equ 0C10h

TIB2:   equ 1C00h           ; a line being built by S (128 bytes)
TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
PAT:    equ 1D50h           ; S's pattern, ended by 0Dh
CURS:   equ 1DA0h           ; output position in screen memory
L1:     equ 1DA2h           ; the range
L2:     equ 1DA4h
NADR:   equ 1DA6h           ; how many addresses were given (byte)
TMPA:   equ 1DAAh
TMPS:   equ 1DACh
GN:     equ 1DAEh           ; G: the line it is at
GOLD:   equ 1DB0h           ; G: the lines before the command
NUMF:   equ 1DB2h           ; print with numbers (byte)
SFLAG:  equ 1DB3h           ; S: something changed (byte), and G (bit 1)
DEST:   equ 1DB4h
REP:    equ 1C80h           ; S's replacement (80 bytes)
GCMD:   equ 1E00h           ; G's command (80 bytes)
GPAT:   equ 1E50h           ; G's pattern (48 bytes)
S0:     equ 1F00h           ; stack (monitor uses 1Fxx)

        org 0400h

; ---------------------------------------------------------------- text

; HL = the number of lines.  Keeps DE.
count:  push de
        ld hl,(ENDP)
        ld bc,(BEG)
        or a
        sbc hl,bc
        ld b,h
        ld c,l
        ld hl,(BEG)
        ld de,0
co1:    ld a,b
        or c
        jr z,co2
        ld a,0Dh
        cpir
        jr nz,co2
        inc de
        jr co1
co2:    ex de,hl
        pop de
        ret

; BC = HL, HL = $ - HL: carry if line HL is past the end.  Keeps DE.
cmpc:   push hl
        call count
        pop bc
        or a
        sbc hl,bc
        ret

; HL = the address of line HL (1 up; one past the last gives ENDP).  Keeps DE.
lnad:   push de
        ex de,hl
        ld hl,(BEG)
la1:    dec de
        ld a,d
        or e
        jr z,la9
        ld a,(hl)
        or a
        jp z,eraddr
        call nextl
        jr la1
la9:    pop de
        ret

; HL = past the 0Dh of the line at HL.  Changes BC, A.
nextl:  ld a,0Dh
        ld bc,0
        cpir
        ret

; HL, DE = the addresses of lines L1 and L2+1.
rngad:  ld hl,(L2)
        inc hl
        call lnad
        ex de,hl
        ld hl,(L1)
        jp lnad

; Take out the bytes from HL up to DE.
delb:   push hl
        ld hl,(ENDP)
        or a
        sbc hl,de
        inc hl
        ld b,h
        ld c,l
        ex de,hl
        pop de
        ldir
        dec de
        ld (ENDP),de
        ret

; Put the BC bytes at DE in at HL.  HL = past them.
insb:   ld (TMPA),hl
        ld (TMPS),de
        push bc
        ld hl,(ENDP)
        push hl
        add hl,bc
        jp c,erfull
        ex de,hl            ; DE = the new end
        ld hl,(TOP)
        sbc hl,de
        jp c,erfull
        ld (ENDP),de
        pop hl              ; the old end
        push hl
        ld bc,(TMPA)
        or a
        sbc hl,bc
        inc hl
        ld b,h
        ld c,l
        pop hl
        lddr
        pop bc
        ld hl,(TMPS)
        ld de,(TMPA)
        ldir
        ex de,hl
        ret

; Delete lines L1-L2.
dellns: call rngad
        jp delb

; The length of the line at DE, with its 0Dh, in BC.
llen:   push de
        ex de,hl
        call nextl
        pop de
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ret

; Find the text at BC (ended by 0Dh) in the line at HL, from HL on.
; Carry and HL = where it starts if found.  Keeps DE, BC.
match:  push de
ma1:    push hl
        ld d,b
        ld e,c
ma2:    ld a,(de)
        cp 0Dh
        jr z,ma8
        cp (hl)
        jr nz,ma3
        inc hl
        inc de
        jr ma2
ma3:    pop hl
        ld a,(hl)
        cp 0Dh
        jr z,ma9
        inc hl
        jr ma1
ma8:    pop hl
        scf
ma9:    pop de
        ret

; Copy from DE to HL up to the character in C, or the end of the line,
; ending it with 0Dh.  DE past the C.
cpto:   ld a,(de)
        cp 0Dh
        jr z,ct9
        inc de
        cp c
        jr z,ct9
        ld (hl),a
        inc hl
        jr cpto
ct9:    ld (hl),0Dh
        ret

; ---------------------------------------------------------------- addresses

; HL = an address at DE; carry if there is none.
getadr: call skipsp
        cp '.'
        jr z,ga1
        cp '$'
        jr z,ga2
        cp '/'
        jr z,ga3
        cp '+'
        jr z,ga4
        cp '-'
        jr z,ga4
        sub '0'
        cp 10
        ccf
        ret c
        call getnum
        jr garel
ga1:    inc de
ga4:    ld hl,(DOT)
        jr garel
ga2:    inc de
        call count
        jr garel
ga3:    inc de              ; /PATTERN/: the next line with it in
        ld a,(de)
        cp '/'
        jr z,ga5            ; // uses the last pattern again
        ld hl,PAT
        ld c,'/'
        call cpto
        dec de
ga5:    inc de
        call count
        ld a,h
        or l
        jp z,eraddr
        ld b,h
        ld c,l
        ld hl,(DOT)
ga6:    push bc             ; lines left to look at
        inc hl
        call cmpc
        ld h,b
        ld l,c
        jr nc,ga7
        ld hl,1             ; past the last: round to the first
ga7:    push hl
        call lnad
        ld bc,PAT
        call match
        pop hl
        pop bc
        jr c,garel
        dec bc
        ld a,b
        or c
        jr nz,ga6
ernone: call error
        db "NO MATCH",0
garel:  ld a,(de)           ; then any +n and -n
        cp '+'
        jr z,gr1
        cp '-'
        jr z,gr2
        or a                ; no carry
        ret
gr1:    push hl
        call num1
        pop bc
        add hl,bc
        jr garel
gr2:    push hl
        call num1
        pop bc
        push bc
        ex (sp),hl
        pop bc
        or a
        sbc hl,bc
        jr garel

; HL = the number after the + or - at DE, or 1.
num1:   inc de
        ld a,(de)
        sub '0'
        cp 10
        jp c,getnum
        ld hl,1
        ret

; HL = the number at DE (DE past it).  Changes BC.
getnum: ld hl,0
gn1:    ld a,(de)
        sub '0'
        cp 10
        ret nc
        ld b,h
        ld c,l
        add hl,hl
        add hl,hl
        add hl,bc
        add hl,hl
        ld c,a
        ld b,0
        add hl,bc
        inc de
        jr gn1

; A = the next character at DE that isn't a space.
skipsp: ld a,(de)
        cp ' '
        ret nz
        inc de
        jr skipsp

; Read the addresses at DE into L1, L2 and NADR; A = the command letter,
; DE past it (not past the 0Dh).
parse:  xor a
        ld (NADR),a
        call skipsp
        cp ','
        jr z,pa1
        cp '%'
        jr nz,pa2
pa1:    inc de
        call setall
        ld a,2
        jr pa4
pa2:    call getadr
        jr c,pa5
        ld (L1),hl
        ld (L2),hl
        ld a,1
        ld (NADR),a
        ld a,(de)
        cp ','
        jr nz,pa5
        inc de
        call getadr
        call c,count
        ld (L2),hl
        ld a,2
pa4:    ld (NADR),a
pa5:    call skipsp
        cp 0Dh
        ret z
        inc de
        ret

; L1, L2 = 1, $.
setall: ld hl,1
        ld (L1),hl
        call count
        ld (L2),hl
        ret

; With no address, L1 = L2 = dot.
def1:   ld a,(NADR)
        or a
        jr nz,chk
        ld hl,(DOT)
        ld (L1),hl
        ld (L2),hl
; 1 <= L1 <= L2 <= $, or ?.
chk:    call count
        ld bc,(L2)
        or a
        sbc hl,bc
        jr c,eraddr
        ld hl,(L1)
        ld a,h
        or l
        jr z,eraddr
        dec hl
        or a
        sbc hl,bc
        ret c
eraddr: call error
        db "ADDRESS",0

; HL = the one address a command takes (L2, or dot), checked 0 to $.
addr0:  ld a,(NADR)
        or a
        ld hl,(L2)
        jr nz,ad1
        ld hl,(DOT)
ad1:    call cmpc
        jr c,eraddr
        ld h,b
        ld l,c
        ret

; ---------------------------------------------------------------- terminal

; Print character A (ASCII).  Keeps everything but AF.
putc:   push hl
        cp 40h
        jr c,pc1
        and 1Fh
pc1:    ld hl,(CURS)
        ld (hl),a
        inc hl
        call fixcur
        pop hl
        ret

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

; CURS = HL, scrolling lines 1-31 up if HL has run off the end.
fixcur: ld a,h
        cp 88h
        jr c,fc9
        push bc
        push de
        ld hl,VRAM+80h
        ld de,VRAM+40h
        ld bc,780h
        ldir
        push de
        rst 20h
        call PAD64
        pop hl
        pop de
        pop bc
fc9:    ld (CURS),hl
        ret

; New line unless at the start of one.
newl:   ld a,(CURS)
        and 3Fh
        ret z
        jr crlf

; Print the string after the CALL, up to a 0 byte.  Keeps HL.
prsi:   ex (sp),hl
        call prs
        ex (sp),hl
        ret
prs:    ld a,(hl)
        inc hl
        or a
        ret z
        call putc
        jr prs

; Print HL in decimal.  Keeps DE.
prnum:  push de
        ld de,10
        call pn2
        pop de
        ret
pn2:    call udiv
        push hl
        ld h,b
        ld l,c
        ld a,h
        or l
        call nz,pn2
        pop hl
        ld a,l
        add a,'0'
        jp putc

; BC = HL / DE, HL = remainder (unsigned).
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

; Print HL as four hex digits, with the monitor's routine.
prhex:  ld de,(CURS)
        ld a,h
        call 03AAh
        ld a,l
        call 03AAh
        ld (CURS),de
        ret

; Print line HL, with its number first if NUMF, and a > after the number
; if it is DEST (for V).  At most C characters of it.
prln:   push bc
        ld a,(NUMF)
        or a
        jr z,pl2
        push hl
        push hl
        call prnum
        pop hl
        ld de,(DEST)
        or a
        sbc hl,de
        ld a,'>'
        jr z,pl1
        ld a,' '
pl1:    call putc
        pop hl
pl2:    call lnad
        pop bc
pl3:    ld a,(hl)
        cp 0Dh
        jp z,crlf
        call putc
        inc hl
        dec c
        jr nz,pl3
        jp crlf

; Print lines L1-L2; dot = L2.
prrng:  ld hl,(L1)
pr1:    push hl
        ld c,0
        call prln
        pop hl
        ld de,(L2)
        ld (DOT),de
        or a
        sbc hl,de
        add hl,de
        inc hl
        jr c,pr1
        ret

; J: join lines L1-L2 (with one address, it and the next).
cjoin:  ld a,(NADR)
        or a
        jr nz,cj1
        ld hl,(DOT)
        ld (L1),hl
        ld a,1
cj1:    dec a
        jr nz,cj2
        ld hl,(L1)
        inc hl
        ld (L2),hl
cj2:    call chk
        ld hl,(L2)
        ld de,(L1)
        ld (DOT),de
        or a
        sbc hl,de
        ret z
        ld b,h
        ld c,l
cj3:    push bc
        ld hl,(L1)
        call lnad
        call nextl
        dec hl
        ld d,h
        ld e,l
        inc de
        call delb
        pop bc
        dec bc
        ld a,b
        or c
        jr nz,cj3
        ret

; =: the line number.
cequ:   ld a,(NADR)
        or a
        ld hl,(L2)
        call z,count
        call prnum
        jp crlf

; W: how to save the buffer on tape.
cwrite: call cbytes
        call prsi
        db "TAPE ",0
        ld hl,(BEG)
        call prhex
        ld hl,(ENDP)
        inc hl
        call prhex
        jp crlf

; R: take in a buffer read from tape: find its 0.
cread:  ld hl,(TOP)
        ld de,(BEG)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        xor a
        cpir
        jp nz,ertape
        dec hl
        ld (ENDP),hl
        call count
        ld (DOT),hl
cbytes: ld hl,(ENDP)
        ld de,(BEG)
        or a
        sbc hl,de
        call prnum
        call prsi
        db " BYTES",0
        jp crlf


; An address alone prints that line; nothing at all, the next.
cnone:  ld a,(NADR)
        or a
        jr nz,cn1
        ld hl,(DOT)
        inc hl
        ld (L2),hl
cn1:    ld hl,(L2)
        ld (L1),hl
cn2:    ld a,2
        ld (NADR),a
cprint: xor a
        jr cp2
cnum:   ld a,1
cp2:    ld (NUMF),a
        ld hl,0
        ld (DEST),hl
        call def1
        jp prrng

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If ED was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) ED.

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
        call nz,cold        ; no text in RAM: an empty buffer
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " ED",0
        call crlf
        call CLS64
        ld a,0Dh
        ld (PAT),a

getln:  ld sp,S0
        call newl
        ld a,'*'
        call putc
        call accept
        ld de,TIB
        call docmd
        jr getln

; A new, empty buffer: in the 32 KB expansion if there is one.
cold:   ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,8800h         ; without it, 8800h is the screen again
        ld (hl),55h
        ld a,(VRAM)
        cp 55h
        jr z,cd0
        ld a,(hl)
        cp 55h
        ld de,0FFF0h
        jr z,cd1
cd0:
        ld hl,SMALL
        ld de,TIB2
cd1:    ld (BEG),hl
        ld (TOP),de
cempty: ld hl,(BEG)
        ld (ENDP),hl
        ld (hl),0
        ld hl,0
        ld (DOT),hl
        ret

; Do the command at DE.
docmd:  call parse
        ld hl,cmds
dc1:    cp (hl)
        inc hl
        jr z,dc2
        inc hl
        inc hl
        bit 7,(hl)
        jr z,dc1
        call error
        db "COMMAND",0
dc2:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

cmds:   db 0Dh
        dw cnone
        db 'P'
        dw cprint
        db 'N'
        dw cnum
        db 'D'
        dw cdel
        db 'A'
        dw capp
        db 'I'
        dw cins
        db 'C'
        dw cchg
        db 'M'
        dw cmove
        db 'T'
        dw ccopy
        db 'J'
        dw cjoin
        db 'S'
        dw csub
        db 'G'
        dw cglob
        db '='
        dw cequ
        db 'V'
        dw cview
        db 'E'
        dw cempty
        db 'W'
        dw cwrite
        db 'R'
        dw cread
        db 'Q'
        dw 0
        db 80h

; V: the 30 lines round dot (or the address), with > at it.
cview:  call addr0
        ld (DEST),hl
        ld (DOT),hl
        ld bc,-15
        add hl,bc
        inc hl
        jr c,cv2
        ld hl,1
cv2:    push hl
        ld hl,VRAM+40h
        ld (CURS),hl
        call CLS64
        pop hl
        ld a,1
        ld (NUMF),a
        ld b,30
cv3:    push bc
        call cmpc
        ld h,b
        ld l,c
        jr c,cv4            ; past the last line
        push hl
        ld c,58
        call prln
        pop hl
        inc hl
        pop bc
        djnz cv3
        push bc
cv4:    pop bc
        ld hl,VRAM+7C0h
        ld (CURS),hl
        ret

; D: delete; dot is the line after, or the last.
cdel:   call def1
        call dellns
setdot: ld hl,(L1)          ; dot = L1, or $ if L1 is past the end
        call cmpc
        add hl,bc
        jr c,sd1
        ld h,b
        ld l,c
sd1:    ld (DOT),hl
        ret

; A, I, C: lines typed in after line HL, until a line of just a full stop.
cins:   call addr0
        ld a,h
        or l
        jr z,append
        dec hl
        jr append
cchg:   call def1
        call dellns
        ld hl,(L1)
        dec hl
        jr append
capp:   call addr0
append: ld (DOT),hl
ap1:    call accept
        ld de,TIB
        ld a,(de)
        cp '.'
        jr nz,ap2
        inc de
        ld a,(de)
        cp 0Dh
        ret z
        dec de
ap2:    ld hl,(DOT)
        inc hl
        ld (DOT),hl
        call lnad
        push hl
        call llen
        pop hl
        call insb
        jr ap1

; M d, T d: move or copy lines L1-L2 to after line d.
ccopy:  ld a,1
        jr mv1
cmove:  xor a
mv1:    push af
        call def1
        call getadr
        jp c,eraddr
        ld (DEST),hl
        call cmpc
        jp c,eraddr         ; d past the end
        ld hl,(DEST)        ; d from L1 to L2-1: no
        ld de,(L1)
        or a
        sbc hl,de
        jr c,mv2
        ld hl,(DEST)
        ld de,(L2)
        or a
        sbc hl,de
        jp c,eraddr
mv2:    call rngad          ; HL = the lines, DE = after them
        push hl
        ex de,hl
        pop de
        or a
        sbc hl,de           ; HL = their length
        push hl
        push de
        ld hl,(DEST)
        inc hl
        call lnad           ; where they go
        pop de
        pop bc
        push hl
        or a
        sbc hl,de
        pop hl
        jr z,mv3
        jr nc,mv4
mv3:    ex de,hl            ; there or before: the lines move up
        add hl,bc
        ex de,hl
mv4:    call insb
        ld hl,(L2)          ; DE = K, the number of lines
        ld de,(L1)
        or a
        sbc hl,de
        inc hl
        ex de,hl
        ld hl,(DEST)
        add hl,de
        pop af
        or a
        jr nz,mv9           ; T: dot = d + K
        ld bc,(L1)          ; M: delete the old ones
        ld hl,(DEST)
        or a
        sbc hl,bc
        jr nc,mv5
        ld hl,(L1)          ; d before them: they are K further on
        add hl,de
        ld (L1),hl
        ld hl,(L2)
        add hl,de
        ld (L2),hl
        push de
        call dellns
        pop de
        ld hl,(DEST)
        add hl,de
        jr mv9
mv5:    call dellns
        ld hl,(DEST)
mv9:    ld (DOT),hl
        ret

; S/OLD/NEW/[G]: in each line L1-L2, change OLD to NEW.
csub:   call def1
        ld a,(de)
        cp 0Dh
        jp z,erpat
        ld c,a              ; the separator
        inc de
        ld a,(de)
        cp c
        jr z,su1            ; S//NEW/ uses the last pattern
        ld hl,PAT
        call cpto
        dec de
su1:    inc de
        ld hl,REP
        call cpto
        ld a,(de)
        sub 'G'
        ld a,0
        jr nz,su2
        ld a,2
su2:    ld (SFLAG),a        ; bit 1: every one; bit 0: changed something
        ld hl,(L1)
su3:    push hl
        call lnad
        ex de,hl            ; DE = the line
        ld hl,TIB2
        push de
su4:    ex de,hl            ; HL = the text, DE = the new line
        push hl
        ld bc,PAT
        call match
        pop bc              ; BC = the text left
        jr nc,su8
        push hl             ; copy up to the match
        or a
        sbc hl,bc
        ld b,h
        ld c,l
        pop hl
        push hl
        or a
        sbc hl,bc
        ld a,b
        or c
        jr z,su5
        ldir
su5:    ld hl,REP           ; then the new text
su6:    ld a,(hl)
        cp 0Dh
        jr z,su7
        ld (de),a
        inc hl
        inc de
        bit 7,e
        jp nz,erlong
        jr su6
su7:    pop hl              ; past the old text
        ld bc,PAT
pt1:    ld a,(bc)
        cp 0Dh
        jr z,pt2
        inc bc
        inc hl
        jr pt1
pt2:    ld a,(SFLAG)
        or 1
        ld (SFLAG),a
        and 2
        jr z,su8b
        ld a,(PAT)
        cp 0Dh
        jr z,su8b           ; an empty pattern only once
        ex de,hl
        jr su4
su8b:   ld b,h
        ld c,l
su8:    ld h,b              ; copy the rest of the line
        ld l,c
su9:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        bit 7,e
        jp nz,erlong
        cp 0Dh
        jr nz,su9
        pop de              ; the old line
        pop hl              ; its number
        push hl
        ld a,(SFLAG)
        rra
        jr nc,su10
        ld (DOT),hl
        ex de,hl            ; replace it
        push hl
        call nextl
        ex de,hl
        pop hl
        push hl
        call delb
        ld de,TIB2
        call llen
        pop hl
        call insb
        ld a,(SFLAG)
        or 4
        and 0FEh
        ld (SFLAG),a
su10:   pop hl
        ld de,(L2)
        or a
        sbc hl,de
        add hl,de
        inc hl
        jp c,su3
        ld a,(SFLAG)
        and 4
        ret nz
        jp ernone

; G/PAT/CMD: CMD on each line with PAT in it.
cglob:  ld a,(NADR)
        or a
        call z,setall
        call chk
        ld a,(de)
        cp 0Dh
        jp z,erpat
        ld c,a
        inc de
        ld hl,GPAT
        call cpto
        ld hl,GCMD
        ld c,0Dh
        call cpto
        ld a,(GCMD)
        cp 0Dh
        jr nz,gl2
        ld hl,'P'+0D00h
        ld (GCMD),hl
gl2:    ld hl,(L1)
gl3:    ld (GN),hl
        call lnad
        ld bc,GPAT
        call match
        jr nc,gl4
        call count
        ld (GOLD),hl
        ld hl,(GN)
        ld (DOT),hl
        ld de,(L2)
        push de
        ld de,GCMD
        call docmd
        pop hl
        ld (L2),hl
        call count          ; lines lost (or gained)
        ex de,hl
        ld hl,(GOLD)
        or a
        sbc hl,de
        ex de,hl
        ld hl,(L2)
        or a
        sbc hl,de
        ld (L2),hl
        ld hl,(GN)
        or a
        sbc hl,de
        ld (GN),hl
gl4:    ld hl,(GN)
        inc hl
        ld de,(L2)
        ex de,hl
        or a
        sbc hl,de
        ex de,hl
        jr nc,gl3
        ret

; ---------------------------------------------------------------- errors

erpat:  call error
        db "PATTERN",0
erlong: call error
        db "TOO LONG",0
erfull: call error
        db "FULL",0
ertape: call error
        db "NO TEXT",0

error:  call newl
        call prsi
        db "? ",0
        pop hl
        call prs
        call crlf
        jp getln

; ---------------------------------------------------------------- keyboard

; Wait for a key.  A = glyph to show at the cursor meanwhile.  Returns A =
; ASCII key, 0Dh for Return, 08h for rubout.  Leaves the screen as it was
; (the NMI handler's echo is undone).  Keeps HL, DE.
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

; Read a line into TIB, echoing it, ending with 0Dh.
accept: ld de,TIB
ac1:    ld a,1Fh            ; cursor: _
        call rawkey
        cp 0Dh
        jr z,ac9
        cp 8
        jr z,ac3
        ld (de),a
        ld a,e
        cp 79
        jr nc,ac1           ; line full
        ld a,(de)
        inc de
        call putc
        jr ac1
ac3:    ld a,e
        or a
        jr z,ac1
        dec de
        ld hl,(CURS)
        dec hl
        ld (hl),' '
        ld (CURS),hl
        jr ac1
ac9:    ld (de),a
        jp crlf

part2_end:
        ds 0C00h-$,0FFh
