; COMP80 CALC
;
; A spreadsheet for the PSI COMP80, after VisiCalc (1979), in the 2 KB of
; ROM (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh) is
; unchanged.  As with BURP, the RS key enters it: the monitor's NMI handler
; jumps to 0800h.
;
; The sheet is 6 columns, A-F, of 10 characters and 24 rows.  Each line
; typed goes into the cell marked >, which then moves down (or right, after
; /R):
;   123.45  -6  +A1*B2  (A1+A2)/2  @SUM(A1...A5)   a value: a formula
;   RENT  "123                                     a label (a letter or ")
;   >B3                                            go to B3
;   /B blank  /C clear all  /D /R move down or right  /F0-2 decimals
;   /U copy the cell above, /L the cell on the left, moving its references
;   down or right (a column or row with $ in front stays as it is: $A1 B$2)
; An empty line just moves on.
;
; Numbers are 32-bit fixed point in hundredths: -21474836.48 to 21474836.47,
; with two decimals.  * and / work through a 64-bit product, rounded.
; Formulas have the usual precedence, brackets, cell references A1-F24 and
; @SUM of a range (the @ is optional).  Labels and empty cells count as 0.  After every
; change all the formulas are worked out again, row by row, until nothing
; changes (8 times at most, for references to cells further on).  A formula
; that can't be worked out shows ERROR, and so does any that uses it.
;
; Each cell is 32 bytes: its kind (0 empty, 1 label, 2 value, 3 error), its
; value (4 bytes, low first) and its text (27 bytes with the 0).
;
; Keys are handled as in COMP80 FORTH: the monitor's NMI handler echoes each
; key and wakes the HALT in RAWKEY; RS while waiting is a rubout and RS at
; any other time (re)starts CALC, keeping the sheet.  Any key while it is
; working resets to the monitor; RS comes back with the sheet kept.

VRAM:   equ 8000h
MAGIC:  equ 0C00h           ; MAGICV when the sheet below is valid
CURS:   equ 0C02h           ; output position in screen memory
ROW:    equ 0C04h           ; the cell marked: row 0-23,
COL:    equ 0C05h           ; column 0-5
DIRN:   equ 0C06h           ; 0 move down, 1 move right
DEC:    equ 0C07h           ; decimals shown, 0-2
ERRSP:  equ 0C08h           ; stack to go back to on an error
CHG:    equ 0C0Ah           ; something changed in this pass
TYPN:   equ 0C0Bh           ; a cell's new kind,
OPB:    equ 0C0Ch           ; and value; the right operand
XV:     equ 0C10h           ; |left|
YV:     equ 0C14h           ; the multiplier
ZV:     equ 0C18h           ; the divisor
PV:     equ 0C1Ch           ; the 64-bit product; quotient and remainder
RLO:    equ 0C26h           ; range: first row, first column
RHI:    equ 0C28h           ;        last row, last column
CR:     equ 0C2Ah           ; the cell being added in
CC:     equ 0C2Bh
SGN:    equ 0C2Ch           ; (in * and /) the sign of the answer
TIB:    equ 0C40h           ; the line typed (26 characters and a 0)
NEND:   equ 0C70h           ; numbers are formatted backwards from here
CELLS:  equ 0C80h           ; 144 cells of 32 bytes, to 1E80h
S0:     equ 1F00h           ; stack (the monitor uses 1Fxx)
MAGICV: equ 0CA1Ch

        org 0400h

; ---------------------------------------------------------------- arithmetic
; A number is in DE:HL (DE the high word).

neg32:  ld a,l
        cpl
        ld l,a
        ld a,h
        cpl
        ld h,a
        ld a,e
        cpl
        ld e,a
        ld a,d
        cpl
        ld d,a
inc32:  inc l
        ret nz
        inc h
        ret nz
        inc e
        ret nz
        inc d
        ret

shl32:  add hl,hl
        rl e
        rl d
        ret

putb:   ld (OPB),hl         ; keeps the flags
        ld (OPB+2),de
        ret

addb:   ld bc,(OPB)
        add hl,bc
        ex de,hl
        ld bc,(OPB+2)
        adc hl,bc
        ex de,hl
        ret

subb:   or a
        ld bc,(OPB)
        sbc hl,bc
        ex de,hl
        ld bc,(OPB+2)
        sbc hl,bc
        ex de,hl
        ret

; DE:HL = DE:HL * 10 + A.  Changes BC and OPB.
mul10:  push af
        call putb
        call shl32
        call shl32
        call addb
        call shl32
        pop af
        ld c,a
        ld b,0
        add hl,bc
        ret nc
        inc de
        ret

; DE:HL = DE:HL / 10 (unsigned), A = the remainder.  Keeps BC.
div10:  push bc
        ld b,32
        xor a
dv1:    add hl,hl
        rl e
        rl d
        rla
        cp 10
        jr c,dv2
        sub 10
        inc l
dv2:    djnz dv1
        pop bc
        ret

; * and /: left in DE:HL, right in OPB.  Both are made positive, the
; product of two goes into PV, and is divided by the third, rounding.
;   A * B = |A| * |B| / 100      A / B = |A| * 100 / |B|
signs:  ld a,(OPB+3)
        xor d
        ld (SGN),a
        bit 7,d
        call nz,neg32
        ld (XV),hl
        ld (XV+2),de
        ld hl,(OPB)
        ld de,(OPB+2)
        bit 7,d
        jp nz,neg32
        ret

mulop:  call signs
        ld (YV),hl
        ld (YV+2),de
        ld hl,100
        ld de,0
        jr md

divop:  call signs
        ld a,h
        or l
        or d
        or e
        jp z,everr          ; dividing by 0
        push hl
        ld hl,100
        ld (YV),hl
        ld l,h              ; (H is 0)
        ld (YV+2),hl
        pop hl
md:     ld (ZV),hl
        ld (ZV+2),de
        call umul
        call udiv
        ld hl,(PV)
        ld de,(PV+2)
        bit 7,d
        jp nz,everr         ; too big
        ld a,(SGN)
        rla
        ret nc
        jp neg32

; PV = XV * YV.  The top bytes of YV that are 0 are skipped first.
umul:   ld hl,PV
        ld b,8
um0:    ld (hl),0
        inc hl
        djnz um0
        ld c,32
um1:    ld a,(YV+3)
        or a
        jr nz,um2
        ld hl,(YV+1)
        ld (YV+2),hl
        ld a,(YV)
        ld (YV+1),a
        xor a
        ld (YV),a
        ld a,c
        sub 8
        ret z
        ld c,a
        jr um1
um2:    ld hl,PV
        ld b,8
        or a
um3:    rl (hl)
        inc hl
        djnz um3
        ld hl,YV
        ld b,4
        or a
um4:    rl (hl)
        inc hl
        djnz um4
        jr nc,um6
        ld hl,PV
        ld de,XV
        ld b,4
        or a
um5:    ld a,(de)
        adc a,(hl)
        ld (hl),a
        inc hl
        inc de
        djnz um5
        ld b,4
um5b:   ld a,(hl)
        adc a,0
        ld (hl),a
        inc hl
        djnz um5b
um6:    dec c
        jr nz,um2
        ret

; PV = PV / ZV, the quotient in the low 4 bytes and the remainder in the
; high 4, then rounded.  The high half starts as the remainder, so a
; quotient that won't fit in 32 bits is an error.
udiv:   call cmphz
        jp nc,everr
        ld c,32
ud1:    ld hl,PV
        ld b,8
        or a
ud2:    rl (hl)
        inc hl
        djnz ud2
        call cmphz
        jr c,ud4
        ld de,PV+4
        ld hl,ZV
        ld b,4
        or a
ud3:    ld a,(de)
        sbc a,(hl)
        ld (de),a
        inc de
        inc hl
        djnz ud3
        ld hl,PV
        inc (hl)
ud4:    dec c
        jr nz,ud1
        ld hl,PV+4          ; twice the remainder at least the divisor:
        ld b,4              ; round up
        or a
ud5:    rl (hl)
        inc hl
        djnz ud5
        call cmphz
        ret c
        ld hl,(PV)
        ld de,(PV+2)
        call inc32
        ld (PV),hl
        ld (PV+2),de
        ret

; Carry if the high half of PV is less than ZV.
cmphz:  ld de,PV+4
        ld hl,ZV
        ld b,4
        or a
ch1:    ld a,(de)
        sbc a,(hl)
        inc de
        inc hl
        djnz ch1
        ret

; ---------------------------------------------------------------- formulas
; IY points at the text.

skipsp: ld a,(iy+0)
        cp ' '
        ret nz
        inc iy
        jr skipsp

; Work out the formula at IY into DE:HL.  Carry if it can't be (everr
; comes back here from anywhere inside).
eval:   ld (ERRSP),sp
        call expr
        call skipsp
        or a
        ret z
everr:  ld sp,(ERRSP)
        scf
        ret

expr:   call term
ex1:    call skipsp
        cp '+'
        jr z,ex2
        cp '-'
        ret nz
ex2:    inc iy
        push af
        push de
        push hl
        call term
        call putb
        pop hl
        pop de
        pop af
        cp '+'
        jr nz,ex3
        call addb
        jr ex1
ex3:    call subb
        jr ex1

term:   call prim
te1:    call skipsp
        cp '*'
        jr z,te2
        cp '/'
        ret nz
te2:    inc iy
        push af
        push de
        push hl
        call prim
        call putb
        pop hl
        pop de
        pop af
        cp '*'
        jr nz,te3
        call mulop
        jr te1
te3:    call divop
        jr te1

prim:   call skipsp
        inc iy
        cp '-'
        jr nz,pr1
        call prim
        jp neg32
pr1:    cp '+'
        jr z,prim
        cp '('
        jr nz,pr2
        call expr
        jr close
pr2:    dec iy
        cp '.'
        jr z,lit
        sub '0'
        cp 10
        jr c,lit
        ld a,(iy+0)
        cp '$'
        jr z,pr3
        cp '@'
        jr z,fun0
        ld a,(iy+1)         ; a letter and a digit or $: a cell
        cp '$'
        jr z,pr3
        sub '0'
        cp 10
        jr nc,func
pr3:    call getref
        jp cellv

close:  call skipsp
        cp ')'
        jp nz,everr
        inc iy
        ret

; A number: digits with a point anywhere, in hundredths.
lit:    ld hl,0
        ld d,h
        ld e,l
        ld bc,0             ; B: 1 after the point; C: digits after it
li1:    ld a,(iy+0)
        cp '.'
        jr nz,li2
        inc b
        jr li3
li2:    sub '0'
        cp 10
        jr nc,li4
        push bc
        call mul10
        pop bc
        ld a,c
        add a,b
        ld c,a
li3:    inc iy
        jr li1
li4:    ld a,c
        cp 2
        ret z
        jr nc,li5
        inc c
        xor a
        push bc
        call mul10
        pop bc
        jr li4
li5:    dec c
        call div10
        jr li4

; @SUM(A1...A5): the sum of a range, a cell, dots (or :) and a cell, the
; corners in either order.  (Only SUM: the @ is optional, the name must
; start with S.)
fun0:   inc iy
func:   ld a,(iy+0)
        cp 'S'
        jp nz,everr
fu1:    inc iy
        ld a,(iy+0)
        sub 'A'
        cp 26
        jr c,fu1
        ld a,(iy+0)
        cp '('
        jp nz,everr
        inc iy
        call getref
        push bc
rg1:    ld a,(iy+0)
        cp '.'
        jr z,rg2
        cp ':'
        jr nz,rg3
rg2:    inc iy
        jr rg1
rg3:    call getref
        call close
        pop de
        ld a,b
        cp d
        jr nc,rg4
        ld b,d
        ld d,a
rg4:    ld a,c
        cp e
        jr nc,rg5
        ld c,e
        ld e,a
rg5:    ld (RLO),de
        ld (RHI),bc
        ld hl,0
        ld d,h
        ld e,l
        ld a,(RLO)
        ld (CR),a
rg6:    ld a,(RLO+1)
        ld (CC),a
rg7:    push de
        push hl
        ld bc,(CR)
        call cellv
        call putb
        pop hl
        pop de
        call addb
        ld a,(CC)
        inc a
        ld (CC),a
        ld b,a
        ld a,(RHI+1)
        cp b
        jr nc,rg7
        ld a,(CR)
        inc a
        ld (CR),a
        ld b,a
        ld a,(RHI)
        cp b
        jr nc,rg6
        ret

; A cell's name at IY ($ in front is passed over): B = column, C = row.
getref: call skipsp
        cp '$'
        jr nz,gr1
        inc iy
        ld a,(iy+0)
gr1:    sub 'A'
        cp 6
        jp nc,everr
        ld b,a
        inc iy
        ld a,(iy+0)
        cp '$'
        jr nz,gr1a
        inc iy
        ld a,(iy+0)
gr1a:   sub '0'
        cp 10
        jp nc,everr
        ld c,a
gr2:    inc iy
        ld a,(iy+0)
        sub '0'
        cp 10
        jr nc,gr3
        ld e,a
        ld a,c
        add a,a
        add a,a
        add a,c
        add a,a
        add a,e
        ld c,a
        jr gr2
gr3:    dec c
        ld a,c
        cp 24
        jp nc,everr
        ret

; HL = the cell at column B, row C.  Keeps BC, DE.
celladr: ld a,c
        add a,a
        add a,c
        add a,a
        add a,b
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        push de
        ld de,CELLS
        add hl,de
        pop de
        ret

; DE:HL = the value of the cell at column B, row C: 0 if it is empty or a
; label, an error if it is one.
cellv:  call celladr
        ld a,(hl)
        cp 3
        jp z,everr
        cp 2
        jr z,cv1
        ld hl,0
        ld d,h
        ld e,l
        ret
cv1:    inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        ret

; ---------------------------------------------------------------- recalculating
; Work out every value cell, row by row, and again until nothing changes.
recalc: ld b,8
rc1:    push bc
        xor a
        ld (CHG),a
        ld hl,CELLS
rc2:    ld a,(hl)
        cp 2
        jr c,rc6
        push hl
        ld de,5
        add hl,de
        push hl
        pop iy
        call eval
        ld a,2
        jr nc,rc2a
        ld hl,0             ; an error: kind 3, value 0
        ld d,h
        ld e,l
        inc a
rc2a:   ld (TYPN),a
        call putb
        pop de
        push de
        ld hl,TYPN          ; the same as before?
        ld b,5
rc3:    ld a,(de)
        cp (hl)
        jr nz,rc4
        inc hl
        inc de
        djnz rc3
        jr rc5
rc4:    pop de
        push de
        ld hl,TYPN
        ld bc,5
        ldir
        ld a,1
        ld (CHG),a
rc5:    pop hl
rc6:    ld de,32
        add hl,de
        ld a,l
        cp 80h
        jr nz,rc2
        ld a,h
        cp 1Eh
        jr nz,rc2
        pop bc
        ld a,(CHG)
        or a
        ret z
        djnz rc1
        ret

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If CALC was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) CALC.

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
        call nz,clear       ; no sheet in RAM: start an empty one
        ld hl,VRAM          ; the parts of the screen that stay
        ld de,VRAM+1
        ld bc,7FFh
        ld (hl),' '
        ldir
        ld hl,VRAM
        ld de,title
        ld a,13
        call putn
        ld hl,VRAM+48h      ; the column letters
        ld a,1              ; (A)
        ld b,6
wm1:    ld (hl),a
        ld de,10
        add hl,de
        inc a
        djnz wm1
        ld de,VRAM+80h      ; the row numbers
        ld a,1
wm2:    push af
        cp 10
        jr nc,wm3
        inc de
wm3:    call pnum2
        ld a,e
        or 3Fh
        ld e,a
        inc de
        pop af
        inc a
        cp 25
        jr c,wm2
        ld hl,VRAM+780h
        ld de,help
        ld a,64
        call putn

loop:   ld sp,S0
        call recalc
redraw: ld sp,S0
        call draw
        call accept

; The line typed.
        ld a,(TIB)
        or a
        jr z,adv0           ; nothing: just move on
        cp '>'
        jr z,goto
        cp '/'
        jr z,cmd
ent:    ld de,TIB
        ld a,(de)
        ld c,1              ; a label,
        cp 22h
        jr z,en1
        sub 'A'
        cp 26
        jr c,en2
        inc c               ; or a value
        jr en2
en1:    inc de
en2:    push de
        ld b,c
        push bc
        ld bc,(ROW)
        call celladr
        pop bc
        ld (hl),b
        ld bc,5
        add hl,bc
        ex de,hl
        pop hl
        ld bc,27
        ldir
        dec de
        xor a
        ld (de),a
        call advance
        jp loop

adv0:   call advance
        jp redraw

; The marker to the next cell down, or right.
advance: ld a,(DIRN)
        ld hl,ROW
        ld b,23
        or a
        jr z,av2
        inc hl
        ld b,5
av2:    ld a,(hl)
        cp b
        ret nc
        inc (hl)
        ret

goto:   ld iy,TIB+1
        call gotry
        jp redraw
gotry:  ld (ERRSP),sp
        call getref
        ld (ROW),bc
        ret

cmd:    ld a,(TIB+1)
        ld bc,(ROW)
        cp 'C'
        jr nz,cm1
        call clear
        jp loop
cm1:    cp 'F'
        jr nz,cm2
        ld a,(TIB+2)
        sub '0'
        cp 3
        jr nc,cm9
        ld (DEC),a
        jr cm9
cm2:    ld hl,DIRN
        cp 'D'
        jr nz,cm3
        ld (hl),0
cm3:    cp 'R'
        jr nz,cm4
        ld (hl),1
cm4:    cp 'B'
        jr nz,cm5
        call celladr
        ld (hl),0
        jp loop
cm5:    ld de,0001h         ; /U: from above, rows + 1
        cp 'U'
        jr nz,cm6
        dec c
        jp p,copy
cm6:    ld de,0100h         ; /L: from the left, columns + 1
        cp 'L'
        jr nz,cm9
        dec b
        jp p,copy
cm9:    jp redraw

; Copy the cell at column B, row C into TIB, adding D to the columns and E
; to the rows of the references in it, and enter it.
copy:   call celladr
        ld a,(hl)
        ld bc,5
        add hl,bc
        ld ix,TIB
        or a
        jp z,adv0           ; empty: nothing
        dec a
        jr nz,cp1
        ld (ix+0),22h       ; a label as it is
        inc ix
cp0:    ld a,(hl)
        ld (ix+0),a
        inc hl
        inc ix
        or a
        jr nz,cp0
        jp ent
cp1:    ld c,d              ; C: the column shift, 0 after a $
        ld a,(hl)
        inc hl
        cp '$'
        jr nz,cp2
        ld (ix+0),a
        inc ix
        ld c,0
        ld a,(hl)
        inc hl
cp2:    ld (ix+0),a
        inc ix
        or a
        jp z,ent
        sub 'A'
        cp 6
        jr nc,cp1
        ld b,a
        ld a,(hl)
        cp '$'
        jr z,cp2a
        sub '0'
        cp 10
        jr nc,cp1           ; a letter but no digit: not a cell
cp2a:   ld a,b
        add a,c
        add a,'A'
        ld (ix-1),a
        ld a,(hl)
        cp '$'
        jr z,cp1            ; $ and the row: copied as they are
        ld c,0
cp3:    ld a,(hl)
        sub '0'
        cp 10
        jr nc,cp4
        ld b,a
        ld a,c
        add a,a
        add a,a
        add a,c
        add a,a
        add a,b
        ld c,a
        inc hl
        jr cp3
cp4:    ld a,c
        add a,e
        push de
        push ix
        pop de
        call pnum2
        push de
        pop ix
        pop de
        jr cp1

; An empty sheet.
clear:  ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,0200h         ; move down, 2 decimals
        ld (DIRN),hl
        ld h,l
        ld (ROW),hl
        ld hl,CELLS
        ld de,CELLS+1
        ld bc,1200h-1
        ld (hl),0
        ldir
        ret

; The cells, the marker, the line about the cell marked and the prompt.
draw:   ld ix,CELLS
        ld hl,VRAM+83h
        ld c,24
dw1:    push hl
        ld de,zero
        ld b,6
dw2:    push bc
        ld a,(ix+0)
        or a
        jr nz,dw3
        ld a,10             ; empty: the rest of a label, or spaces
        call putn
        jr dw9
dw3:    dec a
        jr nz,dw4
        ld (hl),' '         ; a label
        inc hl
        push ix
        pop de
        inc de
        inc de
        inc de
        inc de
        inc de
        ld a,9
        call putn
        jr dw9
dw4:    dec a
        ld de,errs
        ld a,10
        jr nz,dw8           ; an error
        ld de,zero          ; a value, at the right
        call putn
        push hl
        ld l,(ix+1)
        ld h,(ix+2)
        ld e,(ix+3)
        ld d,(ix+4)
        call fmtnum
        pop hl
        cp 10
        jr nc,dw5
        push hl
        ld c,a
        ld b,0
        or a
        sbc hl,bc
        ex de,hl
        push iy
        pop hl
        ldir
        pop hl
        jr dw7
dw5:    push hl             ; too wide: ##########
        ld b,9
dw6:    dec hl
        ld (hl),'#'
        djnz dw6
        pop hl
dw7:    ld de,zero
        jr dw9
dw8:    call putn
        ld de,zero
dw9:    ld bc,32
        add ix,bc
        pop bc
        djnz dw2
        pop hl
        ld de,64
        add hl,de
        dec c
        jr nz,dw1
        call curscr
        ld (hl),'>'
        ld hl,VRAM+6C0h     ; the cell marked: B3 +A1*B2
        call clrln
        ld bc,(ROW)
        ld a,b
        add a,1             ; (A)
        ld (hl),a
        inc hl
        ld a,c
        inc a
        ex de,hl
        call pnum2
        ex de,hl
        inc hl
        push hl
        ld bc,(ROW)
        call celladr
        ld a,(hl)
        ld de,5
        add hl,de
        ex de,hl
        pop hl
        or a
        jr z,dw10
        dec a
        jr nz,dw9a
        ld (hl),22h
        inc hl
dw9a:   ld a,27
        call putn
dw10:   ld hl,VRAM+700h     ; the prompt
        call clrln
        ld (hl),'>'
        inc hl
        inc hl
        ld (CURS),hl
        ret

title:  db " COMP80 CALC",0
help:   db ">B3 GO  /B /C /D /R /U /L /F2",0

; ---------------------------------------------------------------- keyboard

; Wait for a key.  A = glyph to show at the cursor meanwhile.  Returns A =
; the key in ASCII: 0Dh for Return, 8 for a rubout (RS).
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

; Read a line into TIB, echoing it, ending with a 0.
accept: ld de,TIB
ac1:    ld a,1Fh            ; cursor: _
        call rawkey
        cp 0Dh
        jr z,ac9
        cp 8
        jr z,ac3
        ld (de),a
        ld a,e
        cp (TIB & 0FFh)+26
        jr nc,ac1           ; line full
        ld a,(de)
        inc de
        call scode
        ld hl,(CURS)
        ld (hl),a
        inc hl
        ld (CURS),hl
        jr ac1
ac3:    ld a,e
        cp TIB & 0FFh
        jr z,ac1
        dec de
        ld hl,(CURS)
        dec hl
        ld (hl),' '
        ld (CURS),hl
        jr ac1
ac9:    xor a
        ld (de),a
        ret

; ---------------------------------------------------------------- the screen

; A number in DE:HL as text, to DEC decimals, rounded: IY = its first
; character, A = its length.
fmtnum: ld iy,NEND
        ld c,0
        bit 7,d
        jr z,fm1
        call neg32
        inc c
fm1:    ld a,(DEC)
        ld b,a
        cp 2
        jr z,fm3
        push bc
        ld bc,50
        or a
        jr z,fm2
        ld c,5
fm2:    add hl,bc
        jr nc,fm2a
        inc de
fm2a:   call div10
        pop bc
        ld a,b
        or a
        call z,div10
fm3:    ld a,b
        or a
        jr z,fm5
fm4:    call fdig
        djnz fm4
        dec iy
        ld (iy+0),'.'
fm5:    call fdig
        ld a,h
        or l
        or d
        or e
        jr nz,fm5
        dec c
        jr nz,fm6
        dec iy
        ld (iy+0),'-'
fm6:    push iy
        pop bc
        ld a,NEND & 0FFh
        sub c
        ret

fdig:   call div10
        add a,'0'
        dec iy
        ld (iy+0),a
        ret

; Write A characters of the text at DE to the screen at HL, then spaces
; once the text has ended (DE stays at its 0).
putn:   push bc
        ld b,a
pn1:    ld a,(de)
        or a
        jr z,pn2
        inc de
        call scode
        jr pn3
pn2:    ld a,' '
pn3:    ld (hl),a
        inc hl
        djnz pn1
        pop bc
        ret

; A as a screen code: letters are 01h-1Ah.
scode:  cp 40h
        ret c
        and 1Fh
        ret

; Write A, a number 0-99, as text at DE.  Changes B.
pnum2:  ld b,'0'
p2a:    cp 10
        jr c,p2b
        sub 10
        inc b
        jr p2a
p2b:    push af
        ld a,b
        cp '0'
        jr z,p2c
        ld (de),a
        inc de
p2c:    pop af
        add a,'0'
        ld (de),a
        inc de
        ret

; 64 spaces from HL.  Keeps HL.
clrln:  push hl
        ld b,64
cl1:    ld (hl),' '
        inc hl
        djnz cl1
        pop hl
        ret

; HL = where the cell marked starts on the screen.
curscr: ld a,(ROW)
        add a,2
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,(COL)
        ld b,a
        add a,a
        add a,a
        add a,b
        add a,a
        add a,3
        ld e,a
        ld d,80h            ; VRAM
        add hl,de
        ret

zero:   db 0
errs:   db "     ERROR",0

part2_end:
        ds 0C00h-$,0FFh
