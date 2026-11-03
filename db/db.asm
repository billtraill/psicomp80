; COMP80 FILE
;
; A little card-file database for the PSI COMP80, in the 2 KB of ROM
; (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh) is unchanged.  As
; with BURP, the RS key enters it: the monitor's NMI handler jumps to 0800h.
;
;   FIELDS NAME,TOWN,AGE      names the fields (up to 8)
;   ADD SMITH,LEEDS,42        adds a card
;   LIST [WHERE ...]          the cards as a table, numbered
;   FIND TEXT                 the cards with TEXT anywhere in them
;   SHOW n                    card n in full
;   SORT BY FIELD [DESC]      sorts the cards
;   COUNT [WHERE ...]         how many cards
;   SUM FIELD [WHERE ...]     adds up a field;  AVG FIELD [WHERE ...]
;   DELETE n, DELETE WHERE ...
;   NEW                       clears everything
; WHERE takes up to four conditions FIELD op VALUE joined by AND or OR,
; worked out from left to right; op is = < > <> <= >=, and a * at the end
; of VALUE matches any ending.  Fields that are both numbers compare as
; numbers, others as text.  Numbers may have two decimals: they are kept
; as 32-bit hundredths.
;
; The cards are kept as typed, one line each: the fields with commas
; between them and 0Dh at the end, from RECS up to RECEND.  The field
; names are a line of the same kind at FLDS.  So TAPE 0C00 <RECEND> saves
; the whole file.
;
; Keys and screen are handled as in COMP80 FORTH: the monitor's NMI handler
; echoes each key and wakes the HALT in RAWKEY; RS while waiting is a
; rubout, and RS at any other time (re)starts FILE with the cards kept.
; Line 0 shows COMP80 FILE; lines 1-31 scroll.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the file below is valid
RECEND: equ 0C02h           ; end of the cards
NF:     equ 0C04h           ; number of fields
FLDS:   equ 0C05h           ; field names, NAME,TOWN,...0Dh (to 0C3Fh)
RECS:   equ 0C40h           ; first card
MAGICV: equ 0F11Eh
TOP:    equ 1C00h           ; the cards end below here
MAXF:   equ 8

TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
CURS:   equ 1DA0h           ; output position in screen memory
RECNO:  equ 1DA2h           ; number of the card being looked at
NCOND:  equ 1DA4h           ; conditions in CONDS
MODE:   equ 1DA5h           ; 0: match by CONDS; 1: by FTEXT
DESC:   equ 1DA6h           ; sort downwards
FIDX:   equ 1DA7h           ; field to sort or add up
CNT:    equ 1DA8h           ; cards counted (word)
TOTAL:  equ 1DAAh           ; their sum (4 bytes)
FTEXT:  equ 1DAEh           ; text for FIND
WPOS:   equ 1DB0h           ; a card being worked on
NPTR:   equ 1DB2h           ; a field name, or the best card in SORT
P1:     equ 1DB4h           ; the two sides of COMPARE
P2:     equ 1DB6h
WID:    equ 1DB8h           ; column widths for LIST (8 bytes)
CONDS:  equ 1DC0h           ; 4 x 5 bytes: field, mask, AND/OR, value
BUF:    equ 1E00h           ; a card being swapped
S0:     equ 1F00h           ; stack (monitor uses 1Fxx)

        org 0400h

; ---------------------------------------------------------------- cards

; HL = past the 0Dh that ends the line at HL.  Changes A, BC.
nextr:  ld a,0Dh
        ld bc,0
        cpir
        ret

; CY if HL is at or past the end of the cards.
atend:  push de
        ld de,(RECEND)
        or a
        sbc hl,de
        add hl,de
        ccf
        pop de
        ret

; HL = card number HL (from 1); CY if there is none.  Changes A, BC.
recn:   ld b,h
        ld c,l
        ld hl,RECS
rn1:    call atend
        ret c
        dec bc
        ld a,b
        or c
        ret z
        push bc
        call nextr
        pop bc
        jr rn1

; HL = start of field A of the line at HL (at its 0Dh if it is short).
getfld: or a
        ret z
        ld c,a
gf1:    ld a,(hl)
        cp 0Dh
        ret z
        inc hl
        cp ','
        jr nz,gf1
        dec c
        jr nz,gf1
        ret

; B = length of the field at HL.  Keeps HL.
flen:   push hl
        ld b,0
fl1:    ld a,(hl)
        call endc
        jr z,fl2
        inc b
        inc hl
        jr fl1
fl2:    pop hl
        ret

; A = 0 (and Z) if A ends a field: a comma or 0Dh.
endc:   cp ','
        jr z,ec1
        cp 0Dh
        ret nz
ec1:    xor a
        ret

; Remove the card at HL; HL stays, now at the card after it.
delrec: push hl
        call nextr
        ex de,hl
        ld hl,(RECEND)
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        pop de
        push de
        ld a,b
        or c
        jr z,dr1
        ldir
dr1:    ld (RECEND),de
        pop hl
        ret

; ---------------------------------------------------------------- comparing

; Compare the field at HL with the one at DE: as numbers if both are,
; otherwise as text, where a * in DE's field matches the rest.  Z if they
; are the same, CY if HL's is less.  Keeps HL, DE.
compare: ld (P1),hl
        ld (P2),de
        ld ix,(P1)
        call pnum
        jr nz,cstr
        push de
        push hl
        ld ix,(P2)
        call pnum
        jr nz,cstr2
        pop bc              ; first - second
        ld a,c
        sub l
        ld l,a
        ld a,b
        sbc a,h
        ld h,a
        pop bc
        ld a,c
        sbc a,e
        ld e,a
        ld a,b
        sbc a,d
        ld d,a
        or e
        or h
        or l
        jr z,cpret          ; the same: Z, NC
        ld a,d
        rla                 ; CY if negative, still NZ
        jr cpret
cstr2:  pop hl
        pop hl
cstr:   ld hl,(P1)
        ld de,(P2)
scmp:   ld a,(de)
        cp '*'
        jr z,sc2
        call endc
        ld c,a
        ld a,(hl)
        call endc
        sub c
        jr nz,cpret
        or c
        jr z,cpret
        inc hl
        inc de
        jr scmp
sc2:    xor a
cpret:  ld hl,(P1)
        ld de,(P2)
        ret

; DEHL = the number at IX in hundredths, Z if the field is a number to its
; end.  Changes A, BC, IX.
pnum:   ld hl,0
        ld d,h
        ld e,l
        ld b,h              ; decimals
        ld c,h              ; 1 after the point
        ld a,(ix+0)
        sub '-'
        push af             ; Z if negative
        jr nz,pn2
        inc ix
pn2:    ld a,(ix+0)
        inc ix
        cp '.'
        jr nz,pn3
        inc c
        jr pn2
pn3:    sub '0'
        cp 10
        jr nc,pn5
        dec c
        inc c
        jr z,pn4            ; before the point
        inc b
        ex af,af'
        ld a,b
        cp 3
        jr nc,pnx           ; a third decimal: left out
        ex af,af'
pn4:    call mul10
        add a,l
        ld l,a
        jr nc,pn2
        inc h
        jr nz,pn2
        inc de
        jr pn2
pnx:    dec b
        jr pn2
pn5:    add a,'0'
        call endc
        jr nz,pn8
pn6:    ld a,b
        cp 2
        jr nc,pn7
        call mul10
        inc b
        jr pn6
pn7:    pop af
        call z,neg32
        xor a
        ret
pn8:    pop af
        or 1
        ret

; DEHL = DEHL * 10.  Keeps A, BC.
mul10:  push bc
        call dbl
        push de
        push hl
        call dbl
        call dbl
        pop bc
        add hl,bc
        pop bc
        ex de,hl
        adc hl,bc
        ex de,hl
        pop bc
        ret
dbl:    add hl,hl
        ex de,hl
        adc hl,hl
        ex de,hl
        ret

; DEHL = -DEHL.
neg32:  xor a
        sub l
        ld l,a
        ld a,0
        sbc a,h
        ld h,a
        ld a,0
        sbc a,e
        ld e,a
        ld a,0
        sbc a,d
        ld d,a
        ret

; DEHL = DEHL / C, A = the remainder (unsigned).  Keeps C.
divc:   xor a
        ld b,32
dv1:    add hl,hl
        rl e
        rl d
        rla
        jr c,dv2
        cp c
        jr c,dv3
dv2:    sub c
        inc l
dv3:    djnz dv1
        ret

; ---------------------------------------------------------------- matching

; NZ if the card at HL matches the WHERE conditions, or has the FIND text
; in it.  Keeps HL.
match:  ld a,(MODE)
        or a
        jr nz,mfind
        ld a,(NCOND)
        or a
        jr z,my
        push hl
        ld ix,CONDS
        ld b,a
        ld c,0              ; the answer so far
mc1:    push bc
        push hl
        ld a,(ix+0)
        call getfld
        ld e,(ix+3)
        ld d,(ix+4)
        push ix
        call compare
        pop ix
        ld a,2              ; =
        jr z,mc2
        dec a               ; <
        jr c,mc2
        ld a,4              ; >
mc2:    and (ix+1)
        pop hl
        pop bc
        jr z,mc3
        ld a,1
mc3:    ld e,a
        ld a,(ix+2)
        cp 'A'
        ld a,c
        jr nz,mc4
        and e
        jr mc5
mc4:    or e
mc5:    ld c,a
        ld de,5
        add ix,de
        djnz mc1
        pop hl
        ld a,c
        or a
        ret
my:     inc a
        ret
mfind:  push hl
mf1:    ld a,(hl)
        cp 0Dh
        jr z,mf9
        ld de,(FTEXT)
        push hl
mf2:    ld a,(de)
        cp 0Dh
        jr z,mf8
        cp (hl)
        inc hl
        inc de
        jr z,mf2
        pop hl
        inc hl
        jr mf1
mf8:    pop hl
        or 1
mf9:    pop hl
        ret

; Call (IY) with HL at each card that matches, its number in RECNO.
forall: ld hl,0
        ld (RECNO),hl
        ld hl,RECS
fa1:    call atend
        ret c
        push hl
        ld hl,(RECNO)
        inc hl
        ld (RECNO),hl
        pop hl
        call match
        push hl
        call nz,calliy
        pop hl
        call nextr
        jr fa1
calliy: jp (iy)

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

space:  ld a,' '
        jr putc

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

; WID = the widest of each field and its name, cut down to fit 64 columns.
widths: ld hl,WID
        ld b,MAXF
wd1:    ld (hl),0
        inc hl
        djnz wd1
        ld hl,FLDS
        call fwid
        ld hl,RECS
wd2:    call atend
        jr c,wfit
        call fwid
        jr wd2
fwid:   ld de,WID
fw1:    call flen
        ld a,b
        cp 24
        jr c,fw2
        ld b,24
fw2:    ld a,(de)
        cp b
        jr nc,fw3
        ld a,b
        ld (de),a
fw3:    call nextf
        jr z,fw4            ; the end of the line
        inc de
        ld a,e
        cp (WID+MAXF) & 0FFh
        jr c,fw1
        jp nextr
fw4:    inc hl
        ret
; HL = the next field (past the comma), Z at the end of the line.
nextf:  ld a,(hl)
        cp 0Dh
        ret z
        inc hl
        cp ','
        jr nz,nextf
        or a
        ret
wfit:   ld a,(NF)
        or a
        ret z
        ld b,a
        ld hl,WID
        ld c,4
wf1:    ld a,(hl)
        inc a
        add a,c
        ld c,a
        inc hl
        djnz wf1
        cp 64
        ret c
        ld hl,WID           ; too wide: narrow the widest
        ld de,WID
        ld a,(NF)
        ld b,a
wf2:    ld a,(de)
        cp (hl)
        jr nc,wf3
        ld d,h
        ld e,l
wf3:    inc hl
        djnz wf2
        ex de,hl
        dec (hl)
        jr wfit

; Print HL, or DEHL from prdec (unsigned).
prn16:  ld de,0
prdec:  ld c,10
        call divc
        push af
        ld a,d
        or e
        or h
        or l
        call nz,prdec
        pop af
        add a,'0'
        jp putc

; Print DEHL hundredths: with two decimals unless it is a whole number.
prval:  bit 7,d
        jr z,pv1
        call neg32
        ld a,'-'
        call putc
pv1:    ld c,100
        call divc
        push af
        call prdec
        pop af
        or a
        jr z,pv2
        push af
        ld a,'.'
        call putc
        pop af
        ld l,a
        ld h,0
        ld d,h
        ld e,h
        ld c,10
        call divc
        push af
        ld a,l
        add a,'0'
        call putc
        pop af
        add a,'0'
        call putc
pv2:    jp crlf

; COUNT, SUM FIELD and AVG FIELD, each [WHERE ...].
scount: call where
        call zero
        ld iy,cnt1
        call forall
        ld hl,(CNT)
        call prn16
        jp crlf
ssum:   ld b,0
        jr sa1
savg:   ld b,1
sa1:    push bc
        call fname
        ld (FIDX),a
        call where
        call zero
        ld iy,sum1
        call forall
        ld hl,(TOTAL)
        ld de,(TOTAL+2)
        pop bc
        djnz prval
        ld a,(CNT)
        or a
        jr z,prval
        ld c,a
        call divc
        jr prval
zero:   ld hl,CNT
        ld b,6
z1:     ld (hl),0
        inc hl
        djnz z1
        ret
sum1:   ld a,(FIDX)
        call getfld
        push hl
        pop ix
        call pnum
        jr nz,cnt1
        ld bc,(TOTAL)
        add hl,bc
        ld (TOTAL),hl
        ld hl,(TOTAL+2)
        adc hl,de
        ld (TOTAL+2),hl
cnt1:   ld hl,(CNT)
        inc hl
        ld (CNT),hl
        ret

; SHOW n: card n, a field a line.
sshow:  call getnum
        call recn
        jp c,norec
        ld (WPOS),hl
        call dashes
        ld hl,FLDS
sh1:    ld a,(hl)
        inc hl
        call endc
        jr z,sh2
        call putc
        jr sh1
sh2:    call space
        ld a,(CURS)
        and 3Fh
        cp 10
        jr c,sh2
        ld (NPTR),hl
        ld hl,(WPOS)
sh3:    ld a,(hl)
        call endc
        jr z,sh4
        call putc
        inc hl
        jr sh3
sh4:    call nextf
        ld (WPOS),hl
        call crlf
        ld hl,(NPTR)
        dec hl
        ld a,(hl)
        inc hl
        cp 0Dh
        jr nz,sh1
dashes: ld b,40
ds1:    ld a,'-'
        call putc
        djnz ds1
        jp crlf

skipsp: ld a,(de)
        cp ' '
        ret nz
        inc de
        jr skipsp

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If FILE was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) FILE.

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
        call nz,snew        ; no file in RAM: start an empty one
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " COMP80 FILE",0
        call crlf
        call CLS64

ready:  ld sp,S0
        call newl
        call prsi
        db "OK",0
        call crlf
getln:  ld sp,S0
        call accept
        ld de,TIB
        call skipsp
        cp 0Dh
        jr z,getln
        call docmd
        jr ready

; Look the command up and run it, with DE at the rest of the line.
docmd:  ld hl,cmds
dc1:    ld a,(hl)
        or a
        jp z,erwhat
        call kw
        jr z,dc3
dc2:    bit 7,(hl)
        inc hl
        jr z,dc2
        inc hl
        inc hl
        jr dc1
dc3:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call skipsp
        jp (hl)

; Z, with DE past the word, if the word at DE starts with the one at HL
; (whose last letter has bit 7 set), HL then past it.  Otherwise NZ with HL
; and DE kept.  Commands need only their first three letters.
kw:     push hl
        push de
kw1:    ld a,(hl)
        and 7Fh
        ex de,hl
        cp (hl)
        ex de,hl
        jr nz,kw2
        inc de
        bit 7,(hl)
        inc hl
        jr z,kw1
kw3:    ld a,(de)           ; the rest of the word typed
        call isal
        jr c,kw4
        inc de
        jr kw3
kw4:    pop af
        pop af
        xor a
        ret
kw2:    pop de
        pop hl
        or 1
        ret

; NC if A is a letter or a digit.
isal:   cp '0'
        ret c
        cp '9'+1
        ccf
        ret nc
        cp 'A'
        ret c
        cp 'Z'+1
        ccf
        ret

; HL = the number at DE.
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

; A = the number of the field named at DE, DE past the name.
fname:  ld hl,FLDS
        ld c,0
fn1:    push de
fn2:    ld a,(hl)
        call endc
        jr z,fn3
        ex de,hl
        cp (hl)
        ex de,hl
        jr nz,fn4
        inc hl
        inc de
        jr fn2
fn3:    ld a,(de)
        call isal
        jr nc,fn4           ; the word typed goes on
        pop af
        ld a,c
        ret
fn4:    pop de
fn5:    ld a,(hl)
        inc hl
        cp ','
        jr z,fn6
        cp 0Dh
        jr nz,fn5
erfld:  call error
        db "FIELD?",0
fn6:    inc c
        jr fn1

; Read an optional WHERE and its conditions at DE into CONDS.
where:  xor a
        ld (MODE),a
        ld (NCOND),a
        call skipsp
        cp 0Dh
        ret z
        ld hl,kwhere
        call kw
        jr nz,erwhat
        ld ix,CONDS
        ld c,a              ; 0: the first
wh1:    ld a,(NCOND)
        cp 4
        jr nc,erwhat
        call skipsp
        push bc
        call fname
        pop bc
        ld (ix+0),a
        ld (ix+2),c
        ld b,0
wh2:    ld a,(de)
        ld c,2
        cp '='
        jr z,wh3
        dec c
        cp '<'
        jr z,wh3
        ld c,4
        cp '>'
        jr nz,wh4
wh3:    ld a,b
        or c
        ld b,a
        inc de
        jr wh2
wh4:    ld a,b
        or a
        jr z,erwhat
        ld (ix+1),b
        ld (ix+3),e
        ld (ix+4),d
wh5:    ld a,(de)
        cp 0Dh
        jr z,wh6
        inc de
        cp ' '
        jr nz,wh5
        dec de
        ld a,0Dh            ; the value ends here
        ld (de),a
        inc de
wh6:    ld hl,NCOND
        inc (hl)
        ld bc,5
        add ix,bc
        call skipsp
        cp 0Dh
        ret z
        ld c,'A'
        ld hl,kand
        call kw
        jr z,wh1
        ld c,'O'
        ld hl,kor
        call kw
        jr z,wh1
erwhat: call error
        db "WHAT?",0
erfull: call error
        db "FULL",0
norec:  call error
        db "NO CARD",0

error:  call newl
        pop hl
        call prs
        call crlf
        jp ready

; ---------------------------------------------------------------- commands

cmds:   db "LI",80h+'S'
        dw slist
        db "AD",80h+'D'
        dw sadd
        db "FI",80h+'N'
        dw sfind
        db "SH",80h+'O'
        dw sshow
        db "SO",80h+'R'
        dw ssort
        db "CO",80h+'U'
        dw scount
        db "SU",80h+'M'
        dw ssum
        db "AV",80h+'G'
        dw savg
        db "DE",80h+'L'
        dw sdel
        db "FI",80h+'E'
        dw sfields
        db "NE",80h+'W'
        dw snew
        db 0
kwhere: db "WH",80h+'E'
kand:   db "AN",80h+'D'
kor:    db "O",80h+'R'
kby:    db "B",80h+'Y'
kdesc:  db "DE",80h+'S'

; LIST [WHERE ...] and FIND TEXT: a table of the cards that match.
slist:  call where
lst0:   call widths
        call prsi
        db "    ",0
        ld hl,FLDS
        call pline
        ld iy,prow
        jp forall
sfind:  ld (FTEXT),de
        ld a,1
        ld (MODE),a
        jr lst0

; One card as a row: its number, then each field in its column.
prow:   push hl
        ld hl,(RECNO)
        ld a,l
        cp 100
        jr nc,pr1
        call space
        ld a,l
        cp 10
        call c,space
pr1:    call prn16
        call space
        pop hl
pline:  ld de,WID
        ld a,(NF)
        ld c,a
pl1:    ld a,(de)
        inc a
        ld b,a              ; columns for it, with the gap
pl2:    ld a,(hl)
        call endc
        jr z,pl4
        inc hl
        dec b
        jr z,pl3            ; no room for more
        call putc
        jr pl2
pl3:    inc b
        jr pl2
pl4:    call space
        djnz pl4
        ld a,(hl)
        cp 0Dh
        jr z,pl5
        inc hl
pl5:    inc de
        dec c
        jr nz,pl1
        jp crlf

; SORT BY FIELD [DESC]: a bubble sort, swapping cards next to each other
; until a pass through them swaps none.
ssort:  ld hl,kby
        call kw
        jp nz,erwhat
        call skipsp
        call fname
        ld (FIDX),a
        call skipsp
        ld hl,kdesc
        call kw
        ld a,0
        jr nz,so0
        inc a
so0:    ld (DESC),a
so1:    xor a
        ld (CNT),a          ; nothing swapped yet
        ld hl,RECS
so2:    ld (WPOS),hl
        call nextr
        call atend
        jr c,so4
        push hl
        ld a,(FIDX)
        call getfld
        ex de,hl
        ld hl,(WPOS)
        ld a,(FIDX)
        call getfld
        call compare        ; this card against the next
        pop hl
        jr z,so2
        ld a,(DESC)
        jr c,so3
        xor 1
so3:    or a
        jr z,so2            ; in order
        ld hl,(WPOS)
        call swap
        ld (CNT),a
        ld hl,(WPOS)
        call nextr
        jr so2
so4:    ld a,(CNT)
        or a
        jr nz,so1
        ret

; Swap the card at HL with the one after it.
swap:   push hl
        ld de,BUF
        call cpline
        pop de
        call cpline
        ld hl,BUF
cpline: ld a,(hl)
        ldi
        cp 0Dh
        jr nz,cpline
        ret

; NEW: no fields, no cards.
snew:   ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,RECS
        ld (RECEND),hl
        xor a
        ld (NF),a
        ld a,0Dh
        ld (FLDS),a
        ret


; FIELDS NAME,TOWN,...: the names of the fields (the cards are kept).
sfields: ld hl,FLDS
        ld c,1
sf1:    ld a,(de)
        inc de
        cp ' '
        jr z,sf1
        ld (hl),a
        inc hl
        cp ','
        jr nz,sf2
        inc c
sf2:    cp 0Dh
        jr z,sf3
        ld a,l
        cp RECS & 0FFh
        jr c,sf1
        jp erwhat
sf3:    ld a,c
        cp MAXF+1
        jp nc,erwhat
        ld (NF),a
        ret

; ADD A,B,C: a new card at the end, with empty fields added if it is short.
sadd:   ld a,(NF)
        or a
        jp z,erfld
        ld hl,(RECEND)
        ld a,(de)
        cp 0Dh
        jp z,erwhat
        ld c,1
sa3:    ld a,(de)
        inc de
        ld (hl),a
        inc hl
        cp ','
        jr nz,sa4
        inc c
sa4:    cp 0Dh
        jr nz,sa3
        dec hl
sa4a:   ld a,(NF)           ; too few fields: add empty ones
        dec a
        cp c
        jr c,sa9
        ld (hl),','
        inc hl
        inc c
        jr sa4a
sa9:    ld (hl),0Dh
        inc hl
        ld a,h
        cp TOP/256
        jp nc,erfull
        ld (RECEND),hl
        ret

; DELETE n, or DELETE WHERE ...
sdel:   sub '0'
        cp 10
        jr nc,sd1
        call getnum
        call recn
        jp c,norec
        jp delrec
sd1:    ld a,(de)
        cp 0Dh
        jp z,erwhat
        call where
        call zero
        ld hl,RECS
sd2:    call atend
        jr c,sd4
        call match
        jr z,sd3
        call delrec
        call cnt1
        jr sd2
sd3:    call nextr
        jr sd2
sd4:    ld hl,(CNT)
        call prn16
        call prsi
        db " DELETED",0
        jp crlf

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

; Read a line into TIB, echoing it, ending with 0Dh.  Changes DE, HL.
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
