; COMP80 APL
;
; A small APL for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that held
; BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS key
; enters it: the monitor's NMI handler jumps to 0800h.
;
; The keyboard has no APL characters, so the functions are spelt in ASCII:
;   + - * %          add, subtract, times, divide; monadic - negates
;   = # < > <= >=    comparisons, giving 1 or 0 (# is not equal)
;   MAX              the larger (MAX/ is the largest)
;   A MOD B          the remainder of A divided by B
;   IOTA N           1 to N
;   RHO B, A RHO B   the shape of B; B reshaped to A (N, or R C)
;   A / B            each element of B repeated A times (A of 1s and 0s
;                    picks some out)
;   F/ B  F! B       reduce and scan (APL's / and \) with a scalar F
;   A .F B           outer product (APL's jot-dot)
;   V[I]             indexing, from 1; the result has the shape of I
;   X: expression    assignment, to a single letter, A-Z
;   "TEXT"           a character vector
; A function takes everything to its right, as in APL: 2*3+4 is 14.  The
; operands are read from the left, so an assignment within a line counts
; only to its left.  Numbers are 16-bit integers; negative ones print with
; -.  % and MOD work on the sizes of negative numbers.  A line that isn't an
; assignment prints its value.  ) on a line of its own forgets all the
; variables.
;
; Arrays are rank 0, 1 or 2.  Each has a header: type (rank in bits 0-1,
; 80h for characters), rows, columns, number of elements, then the elements,
; a word each.  A vector is one row and a scalar one row of one, and a
; result of one element is always a scalar.  The values of the variables
; are kept from the bottom of the heap up to VTOP, each new one on the end
; (and ) starts afresh when it is full).  The values worked out on a line go
; down from the top of the heap (TMP), and are thrown away at the end of
; the line.
;
; Most functions make their result an element at a time: they set up the
; result's shape, and BUILD calls a routine (IY) for each element number.
;
; Keys and screen are handled as in COMP80 FORTH: RS while waiting is a
; rubout, and any key while a line is being worked out resets to the
; monitor; RS comes back with the variables kept.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the variables below are valid
VTOP:   equ 0C02h           ; end of the variables' values
VTAB:   equ 0C04h           ; A-Z: a word each, the value or 0
CURS:   equ 0C38h           ; output position in screen memory
TMP:    equ 0C3Ah           ; bottom of this line's values
FN:     equ 0C3Ch           ; the scalar function being applied
FM:     equ 0C3Dh           ; 3 for an outer product
TYP:    equ 0C3Eh           ; type being printed
WID:    equ 0C3Fh           ; width of the numbers being printed
PR:     equ 0C40h           ; where the next element of a result goes
NA:     equ 0C42h           ; rows, or the left count ...
NB:     equ 0C44h           ; ... and columns, or the right count
CNT:    equ 0C46h
LV:     equ 0C48h           ; left argument
RV:     equ 0C4Ah           ; right argument
NBUF:   equ 0C4Ch           ; a number as text (7 bytes)
HEAP0:  equ 0C54h
HEAPE:  equ 1D00h
TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
S0:     equ 1F00h           ; stack (the monitor uses 1Fxx)
MAGICV: equ 0A91Ch

NSCAL:  equ 12              ; functions 0-11 are scalar
F_SUB:  equ 1
F_EQ:   equ 4

        org 0400h

; ---------------------------------------------------------------- parser
; DE is the text pointer throughout.  A value is the address of its header.

; Work out the expression at DE: HL = its value, DE at its end.  A function
; first is monadic, applied to all the rest; otherwise an operand, then if
; anything follows, a dyadic function and all the rest.
expr:   call getfn
        jr nc,ex1
        push bc
        call expr           ; F rest
        pop bc
        jp monad
ex1:    ld a,(de)           ; X: rest
        call isltr
        jr nc,ex2
        ld c,a
        push de
        inc de
        call skips
        cp ':'
        jr nz,ex2p
        pop af
        inc de
        push bc
        call expr
        pop bc
        jp assign
ex2p:   pop de
ex2:    call primary        ; operand F rest
        call skips
        call isend
        ret z
        push hl
        call getfn
        jp nc,ersyn
        push bc
        call expr
        pop bc
        ex (sp),hl
        ld (LV),hl
        pop hl
        jp dyad

; One operand: numbers, "text", (expression) or a variable, then [index]s.
primary:
        call skips
        cp '('
        jr z,pr_par
        cp 22h
        jr z,pr_str
        call isdig
        jr c,pr_num
        call isltr
        jp nc,ersyn
        sub 'A'             ; a variable
        inc de
        ld b,a
        call slot
        call ldw
        ld a,h
        or l
        jr nz,pr_idx
        call error
        db "VALUE",0
pr_par: inc de
        call expr
        call skips
        cp ')'
        jp nz,ersyn
        inc de
pr_idx: call skips
        cp '['
        ret nz
        inc de
        push hl
        call expr
        call skips
        cp ']'
        jp nz,ersyn
        inc de
        ex (sp),hl
        ld (LV),hl
        pop hl
        ld (RV),hl
        push de
        call index
        pop de
        jr pr_idx

pr_num: ld ix,0              ; numbers: each kept on the stack
pn1:    call getnum
        push hl
        inc ix
        call skips
        call isdig
        jr c,pn1
        xor a
        jr pr_vec
pr_str: ld ix,0              ; "text": the same with each character
ps1:    inc de
        ld a,(de)
        cp 0Dh
        jp z,ersyn
        cp 22h
        jr z,ps2
        ld l,a
        ld h,0
        push hl
        inc ix
        jr ps1
ps2:    inc de
        ld a,80h
pr_vec: ld (CNT),de         ; make a vector of the IX on the stack, type A
        push ix
        pop bc
        call vector
        ld hl,(PR)          ; fill it from the end
        add hl,bc
        add hl,bc
pv1:    ld a,b
        or c
        jr z,pv2
        pop de
        dec hl
        ld (hl),d
        dec hl
        ld (hl),e
        dec bc
        jr pv1
pv2:    ld hl,(TMP)
        ld de,(CNT)
        jr pr_idx

; A function at DE?  Carry if so, with C = its number and B = 0, or 1 for
; reduce, 2 for scan, 3 for outer product; DE past it.
getfn:  call skips
        ld b,3
        cp '.'
        jr nz,gf1
        push de
        inc de
        call gfname
        jr nc,gfno
        call scalar
        jr nc,gfno
        pop hl              ; (keeps the carry)
        ret
gfno:   pop de
        or a
        ret
gf1:    call gfname
        ret nc
        ld b,0
        call scalar
        jr nc,gfy           ; not scalar: no / or !
        ld a,(de)
        cp '/'
        jr z,gfr
        cp '!'
        jr nz,gfy
        inc b
gfr:    inc b
        inc de
gfy:    scf
        ret

; The function name at DE: carry and C = its number, DE past it.
gfname: ld hl,names
        ld c,0
gn1:    push de
gn2:    ld a,(de)
        xor (hl)
        jr nz,gn4
        inc hl
        inc de
        jr gn2
gn4:    and 7Fh
        jr nz,gn5           ; different
        inc de              ; the last character matched
        ld a,(hl)
        and 7Fh
        call isltr
        jr nc,gn6           ; a sign
        ld a,(de)
        call isltr
        jr c,gn5            ; a word, but it goes on
gn6:    pop af
        scf
        ret
gn5:    ld a,(hl)           ; on to the next name
        inc hl
        rla
        jr nc,gn5
        inc c
        pop de
        ld a,(hl)
        or a
        jr nz,gn1
        ret

names:  db 0ABh               ; 0 +    (the number of each is its place)
        db 0ADh               ; 1 -
        db 0AAh               ; 2 *
        db 0A5h               ; 3 %
        db 0BDh               ; 4 =
        db 0A3h               ; 5 #
        db "<",0BDh           ; 6 <=
        db ">",0BDh           ; 7 >=
        db 0BCh               ; 8 <
        db 0BEh               ; 9 >
        db "MA",0D8h          ; 10
        db "MO",0C4h          ; 11
        db 0AFh               ; 12 /
        db "IOT",0C1h         ; 13
        db "RH",0CFh          ; 14
        db 0

; Carry if C is a scalar function.
scalar: ld a,c
        cp NSCAL
        ret

; ---------------------------------------------------------------- small parts

skips:  ld a,(de)           ; A = the next character that isn't a space
        cp ' '
        ret nz
        inc de
        jr skips

isend:  cp 0Dh              ; Z at the end of an expression
        ret z
        cp ')'
        ret z
        cp ']'
        ret

isltr:  cp 'A'              ; carry if A is a letter
        ccf
        ret nc
        cp 'Z'+1
        ret

; HL = the slot of variable B (0-25).
slot:   ld a,b
        add a,a
        add a,VTAB & 0FFh
        ld l,a
        ld h,VTAB/256
        ret

; HL = element HL of RV (gath), element BC of the value at HL (elemc).
gath:   ld b,h
        ld c,l
        ld hl,(RV)
elemc:  add hl,bc
        add hl,bc
        ld bc,7
        add hl,bc
ldw:    ld a,(hl)           ; HL = (HL)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; HL = the number at DE (DE past it).  Changes BC.
getnum: ld hl,0
gt1:    ld a,(de)
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
        jr gt1

; For the value at HL: A = type, BC = number of elements, DE = the first.
info:   push hl
        ld a,(hl)
        ld de,5
        add hl,de
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ex de,hl
        pop hl
        ret

; BC = the size in bytes of the value at HL.
size:   push hl
        call info
        ld h,b
        ld l,c
        add hl,hl
        ld bc,7
        add hl,bc
        ld b,h
        ld c,l
        pop hl
        ret

; HL = a new value of type A, BC rows and DE columns, taken from the bottom
; of this line's space; PR = its first element.
alloc:  push de
        push bc
        push af
        ld h,b
        ld l,c
        ld b,d
        ld c,e
        call mul
        ld a,h
        and 0C0h
        jr nz,erfull
        push hl
        add hl,hl
        ld bc,7
        add hl,bc
        ex de,hl
        ld hl,(TMP)
        or a
        sbc hl,de
        jr c,erfull
        ld (TMP),hl
        ld de,(VTOP)
        sbc hl,de
        jr c,erfull
        ld hl,(TMP)
        pop bc              ; the count
        pop af
        ld (hl),a
        inc hl
        ex de,hl
        pop hl              ; rows
        call stw
        pop hl              ; columns
        call stw
        ld h,b
        ld l,c
        call stw
        ld (PR),de
        ld hl,(TMP)
        ret
stw:    ld a,l              ; the word HL at DE
        ld (de),a
        inc de
        ld a,h
        ld (de),a
        inc de
        ret
erfull: call error
        db "WS FULL",0

; HL = a new vector of BC elements, A = 0 or 80h for characters (a scalar
; if there is just one).  Keeps BC.
vector: push bc
        ld d,b
        ld e,c
        dec bc
        ld h,a
        ld a,b
        or c
        ld a,h
        jr z,ve1
        or 1
ve1:    ld bc,1
        call alloc
        pop bc
        ret

; HL = a new value the shape of the one at HL, of type A.
likea:  ld b,a
        ld a,(hl)
        and 3
        or b
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        jr alloc

; Put HL at PR, the next element of a result.  Keeps everything.
store:  push de
        ex de,hl
        ld hl,(PR)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (PR),hl
        ex de,hl
        pop de
        ret

; NA, NB = rows and columns of RV.
dims:   ld hl,(RV)
        inc hl
        ld de,NA
        ld bc,4
        ldir
        ret

; Fill the new value HL with IY(element number) for each element.
build:  push hl
        call info
        ld hl,0
bl1:    ld a,b
        or c
        jr z,bl9
        push bc
        push hl
        call calliy
        call store
        pop hl
        inc hl
        pop bc
        dec bc
        jr bl1
bl9:    pop hl
        ret
calliy: jp (iy)

; ---------------------------------------------------------------- functions
; Monadic function C (modifier B) of HL, or dyadic of LV and HL.  Both
; keep DE.
monad:  ld (RV),hl
        push de
        call mon1
        pop de
        ret
dyad:   ld (RV),hl
        push de
        call dy1
        pop de
        ret

mon1:   ld a,b
        dec a
        jr z,reduce
        dec a
        jr z,scan
        dec a
        jr z,ersyn
        ld a,c
        cp F_SUB
        jr z,negate
        cp 13
        jr z,iota
        cp 14
        jp z,shape
ersyn:  call error
        db "SYNTAX",0

negate: ld hl,zero0         ; 0 - RV
        ld (LV),hl
        jp scal2
zero0:  db 0                ; the scalar 0
        dw 1,1,1,0

; IOTA N: 1 to N.
iota:   ld hl,0
        call gath
        ld b,h
        ld c,l
        xor a
        call vector
        ld iy,iotaf
        jr build
iotaf:  inc hl
        ret

; Reduce: f/ of each row, from the right; scan: of the first 1, 2, ...
reduce: call chksc
        call dims
        ld bc,(NA)
        xor a
        call vector         ; one for each row
        ld iy,redf
        jp build
redf:   ld bc,(NB)
        push bc
        call mul
        pop bc
fold1:  ld de,(RV)          ; f/ of BC elements of RV from element HL
        add hl,hl
        add hl,de
        ld de,7
        add hl,de
        jr foldr
scan:   call chksc
        call dims
        ld hl,(RV)
        xor a
        call likea
        ld iy,scanf
        jp build
scanf:  push hl
        ld de,(NB)
        call udiv           ; HL = the column
        ld b,h
        ld c,l
        inc bc
        ex de,hl
        pop hl
        or a
        sbc hl,de
        jr fold1

chksc:  call scalar
        jp nc,ersyn
        ld (FN),a
        ret

; HL = f reduced over the BC elements at HL, from the right.
foldr:  ld a,b
        or c
        jr nz,fr0
        ld h,a
        ld l,a
        ret
fr0:    dec bc
        add hl,bc
        add hl,bc
        push hl
        call ldw
        ex de,hl
        pop hl
fr1:    ld a,b
        or c
        jr z,fr9
        dec hl
        dec hl
        push hl
        push bc
        call ldw
        ld a,(FN)
        call callf
        ex de,hl
        pop bc
        pop hl
        dec bc
        jr fr1
fr9:    ex de,hl
        ret

dy1:    ld a,b
        ld (FM),a
        cp 3
        jr z,outer
        or a
        jp nz,ersyn
        ld a,c
        cp NSCAL
        jr c,scal2
        jp z,repl
        cp 14
        jp z,reshape
        jp ersyn

; Scalar function C of LV and RV, element by element; a single element (or
; the shorter, over and over) goes with every element of the other.
scal2:  ld a,c
        ld (FN),a
        call counts         ; the shape of the one with more elements
        ld hl,(LV)
        ex de,hl
        or a
        sbc hl,bc
        ex de,hl
        jr nc,sc5
        ld hl,(RV)
sc5:    xor a
        call likea
zip:    ld iy,zipf
        jp build

; Outer product: f of each element of LV with each of RV, a row for each
; element of LV.
outer:  call chksc
        call counts
        ld bc,(NA)
        ld de,(NB)
        ld a,2
        call alloc
        jr zip

; Element I: f(LV[I mod NA], RV[I mod NB]), or for an outer product
; f(LV[I / NB], RV[I mod NB]).
zipf:   push hl
        ld de,(NB)
        call udiv
        ex (sp),hl
        ld a,(FM)
        cp 3
        jr z,zp1
        ld de,(NA)
        call udiv
        ld b,h
        ld c,l
zp1:    ld hl,(LV)
        call elemc
        ex (sp),hl
        call gath
        ex de,hl
        pop hl
        ld a,(FN)
        jp callf

; NA, DE = elements in LV; NB, BC = elements in RV.
counts: ld hl,(LV)
        call info
        ld (NA),bc
        push bc
        ld hl,(RV)
        call info
        ld (NB),bc
        pop de
        ret

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If APL was waiting for
; a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) APL.

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
        call nz,clear       ; nothing in RAM: start afresh
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " APL",0
        call crlf
        call CLS64

getln:  ld sp,S0
        ld hl,HEAPE
        ld (TMP),hl
        call accept
        ld de,TIB
        call skips
        cp 0Dh
        jr z,getln
        cp ')'
        jr nz,gl0
        call clear          ; ): forget the variables
        jr getln
gl0:    ld b,0              ; an assignment first is not printed
        call isltr
        jr nc,gl1
        push de
        inc de
        call skips
        pop de
        cp ':'
        jr nz,gl1
        inc b
gl1:    push bc
        call expr
        call skips
        cp 0Dh
        jp nz,ersyn
        pop bc
        dec b
        call nz,print
        jr getln

clear:  ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,VTAB
        ld b,52
cl1:    ld (hl),0
        inc hl
        djnz cl1
        ld hl,HEAP0
        ld (VTOP),hl
        ret

; ---------------------------------------------------------------- scalars
; HL = f(HL, DE) for scalar function A.  Changes BC, DE.
callf:  ld bc,ftab          ; (the table and the routines each in one page)
        add a,c
        ld c,a
        ld a,(bc)
        push hl
        ld l,a
        ld h,f_add/256
        ex (sp),hl
        ret

ftab:   db f_add&0FFh,f_sub&0FFh,f_mul&0FFh,f_div&0FFh,f_eq&0FFh,f_ne&0FFh
        db f_le&0FFh,f_ge&0FFh,f_lt&0FFh,f_gt&0FFh,f_max&0FFh,f_mod&0FFh

f_add:  add hl,de
        ret
f_sub:  or a
        sbc hl,de
        ret
f_mul:  ld b,d
        ld c,e
        jp mul
f_eq:   ld a,2              ; the comparisons: less 1, equal 2, greater 4
        db 1                ; (LD BC,nn: skip the next two bytes)
f_ne:   ld a,5
        db 1
f_lt:   ld a,1
        db 1
f_gt:   ld a,4
        db 1
f_le:   ld a,3
        db 1
f_ge:   ld a,6
        push af
        call scmp
        ld a,2
        jr z,fc1
        ld a,1
        jr c,fc1
        ld a,4
fc1:    pop bc
        and b
        ld hl,0
        ret z
        inc l
        ret
f_max:  push hl
        push de
        call scmp
        pop de
        pop hl
        ret nc
        ex de,hl
        ret
f_div:  call absde
        push af
        call udiv
        ld h,b
        ld l,c
        pop af
        rla
        ret nc
        jr neghl
f_mod:  ld a,d              ; A MOD B: the remainder of A / B (A if B is 0)
        or e
        ret z
        call absde
        jp udiv

; Compare HL with DE, signed: carry if less, Z if equal.  Changes HL, DE.
scmp:   ld a,h
        xor 80h
        ld h,a
        ld a,d
        xor 80h
        ld d,a
        or a
        sbc hl,de
        ret

; HL = |HL|, DE = |DE|, A bit 7 = the sign of the quotient; DOMAIN if DE = 0.
absde:  ld a,d
        or e
        jr z,erdom
        ld a,h
        xor d
        push af
        call abshl
        ex de,hl
        call abshl
        ex de,hl
        pop af
        ret
abshl:  bit 7,h
        ret z
neghl:  xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret
erdom:  call error
        db "DOMAIN",0

isdig:  cp '0'              ; carry if A is a digit
        ccf
        ret nc
        cp '9'+1
        ret

; ---------------------------------------------------------------- assignment
; Variable C (a letter) = a copy of the value HL, put on the end of the
; variables; HL unchanged.  Keeps DE.
assign: push de
        push hl
        ld a,c
        sub 'A'
        ld b,a
        call slot
        ex (sp),hl          ; HL = the value, the slot on the stack
        call size
        push hl
        ld hl,(VTOP)
        push hl
        add hl,bc
        ex de,hl
        ld hl,(TMP)
        or a
        sbc hl,de
        jp c,erfull
        ld (VTOP),de
        pop de              ; where it goes
        pop hl
        ex (sp),hl          ; HL = the slot, the value on the stack
        ld (hl),e
        inc hl
        ld (hl),d
        pop hl
        push hl
        ldir
        pop hl
        pop de
        ret

; ---------------------------------------------------------------- dyadic

; A RHO B: B's elements, over and over, in the shape A (N, or R C).
reshape:
        ld hl,(RV)
        call info
        ld (CNT),bc
        ld hl,(LV)
        call info           ; BC = how many in the shape, DE = them
        ex de,hl
        ld de,1
        ld a,c
        cp 2
        jr c,rh1
        call nextw          ; rows
rh1:    ld b,a              ; the rank
        push de
        call ldw
        ex de,hl            ; DE = columns
        ld hl,(RV)
        ld a,(hl)
        and 80h
        or b
        pop bc
        call alloc
        ld iy,rhof
        jp build
rhof:   ld de,(CNT)         ; element I mod (elements in RV), or 0
        ld a,d
        or e
        jr nz,rh2
        ld h,a
        ld l,a
        ret
rh2:    call udiv
        jp gath

; A / B: each element of B, as many times as the element of A.
repl:   xor a               ; the total: +/A
        ld (FN),a
        ld hl,(LV)
        call info
        ld (NA),de
        ex de,hl
        call foldr
        ld b,h
        ld c,l
        ld hl,(RV)
        ld a,(hl)
        and 80h
        call vector
        push hl
        ld hl,(RV)
        call info
rp1:    ld a,b
        or c
        jr z,rp9
        push bc
        ld hl,(NA)
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld (NA),hl          ; BC = how many
        ex de,hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ex de,hl            ; HL = the element
rp2:    ld a,b
        or c
        jr z,rp3
        call store
        dec bc
        jr rp2
rp3:    pop bc
        dec bc
        jr rp1
rp9:    pop hl
        ret

; LV[RV]: the elements of LV picked by RV, counting from 1.
index:  ld hl,(LV)
        call info
        ld (CNT),bc
        and 80h
        ld hl,(RV)
        call likea
        ld iy,idxf
        jp build
idxf:   call gath
        dec hl
        ld de,(CNT)
        push hl
        or a
        sbc hl,de
        pop hl
        jr nc,erindex
        ld b,h
        ld c,l
        ld hl,(LV)
        jp elemc
erindex:
        call error
        db "INDEX",0

; RHO B: the shape of B.
shape:  ld hl,(RV)
        ld a,(hl)
        and 3
        ld c,a
        ld b,0
        xor a
        call vector
        ld iy,shapef
        jp build
shapef: ld de,(RV)          ; element I: the word at 5 + 2 * (I - rank)
        ld a,(de)
        and 3
        neg
        add a,l
        add a,a
        add a,5
        ld l,a
        ld h,0
        add hl,de
        jp ldw

; HL = HL * BC.  Keeps DE.
mul:    push de
        ex de,hl
        ld hl,0
        ld a,16
mu1:    add hl,hl
        sla c
        rl b
        jr nc,mu2
        add hl,de
mu2:    dec a
        jr nz,mu1
        pop de
        ret

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

; ---------------------------------------------------------------- printing

; Print the value at HL, a row to a line: numbers right-aligned to the
; widest, with a space before each; characters as they are.
print:  ld (RV),hl
        call dims
        ld hl,(RV)
        call info
        ld (TYP),a
        push de
        push bc
        xor a
        ld (WID),a
pt1:    ld a,b              ; the widest number
        or c
        jr z,pt2
        ex de,hl
        call nextw
        push hl
        ex de,hl
        call numstr
        ld hl,WID
        cp (hl)
        jr c,pt1b
        ld (hl),a
pt1b:   pop de
        dec bc
        jr pt1
pt2:    pop bc
        pop hl
        ld de,(NB)
        ld (CNT),de         ; columns left on this row
pt3:    ld a,b
        or c
        jr z,newl
        push bc
        call nextw
        push hl
        ld a,(TYP)
        rla
        ld a,e
        jr c,ptc
        ex de,hl
        call numstr         ; HL = the text, A = its length
        ld b,a
        ld a,(WID)
        sub b
        ld c,a
        inc c
pt6:    ld a,' '
        call putc
        dec c
        jr nz,pt6
pt7:    ld a,(hl)
        inc hl
        call putc
        djnz pt7
        jr pt8
ptc:    call putc
pt8:    ld hl,(CNT)         ; the end of a row?
        dec hl
        ld a,h
        or l
        jr nz,pt9
        call crlf
        ld hl,(NB)
pt9:    ld (CNT),hl
        pop hl
        pop bc
        dec bc
        jr pt3

; DE = the word at HL, HL past it.
nextw:  ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ret

; HL = HL as text (with - if negative) and A = its length.  Keeps BC, DE.
numstr: push bc
        push de
        ld c,h
        call abshl
        ld de,NBUF+7
        ld b,0
ns1:    push de
        ld de,10
        push bc
        call udiv
        ld a,l
        add a,'0'
        ld h,b
        ld l,c
        pop bc
        pop de
        dec de
        ld (de),a
        inc b
        ld a,h
        or l
        jr nz,ns1
        bit 7,c
        jr z,ns2
        dec de
        ld a,'-'
        ld (de),a
        inc b
ns2:    ld a,b
        ex de,hl
        pop de
        pop bc
        ret

newl:   ld a,(CURS)         ; new line unless at the start of one
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

; Print character A (ASCII).  Keeps all but AF.
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

; Print the string after the CALL, up to a 0 byte.
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

; Print the error named after the CALL, and start a new line.
error:  call newl
        pop hl
        call prs
        call prsi
        db " ERROR",0
        call crlf
        jp getln

; ---------------------------------------------------------------- keyboard

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
