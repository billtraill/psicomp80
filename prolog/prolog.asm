; COMP80 PROLOG
;
; A small Prolog for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that
; held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS
; key enters it: the monitor's NMI handler jumps to 0800h.
;
; The keyboard and screen have no lower case, so a variable is a single
; letter, or a letter followed by digits (X, Y, L1); any other name is an
; atom.  ? is an anonymous variable, and [H:T] is a list with head H and
; tail T, as | and _ can't be typed.
;
; Terms are 16-bit words:
;   number n     2n+1 (odd), so -16384..16383
;   atom         address of its record in 0C30h-0EFFh: length (1), name;
;                records start on addresses that are multiples of 4
;   cell         address of a 4-byte cell, car then cdr, in the heap
;                (1000h up, or 8800h up with the 32 KB expansion)
;   variable     address of a cell + 2: the cell's car is what it is bound
;                to, or 0 while it is unbound
; A compound term f(a,b) is the list of cells (f a b ...) ending in 0, and
; a list [a,b] is cells (a . (b . [])) ending in the atom [].  Inside a
; stored clause, variable k is 4k+6 and the end of the body is 2 (the hole).
;
; A clause is the cell (head . body), the body a list of goals ending in the
; hole, and the database is a list of clauses.  To use a clause, the solver
; copies it into the heap with fresh variables, the hole replaced by the
; goals still to be done (the continuation) and each ! by the depth of the
; choice point stack to cut back to (as an odd number, so a goal that is a
; number is a cut).  So a goal list is just a list, ending in 0 when the
; query is proved.
;
; Choice points are on the Z80 stack: the continuation, the next clause to
; try, the trail pointer and the heap pointer.  Every binding goes on the
; trail, which grows down from the top of the heap.  Backtracking pops a
; choice point, unbinds what was bound since, and gives the heap back.
; Nothing is collected: the heap is cleared after each query.
;
; Text is kept in ASCII (20h-5Fh) and converted to the display's 6-bit codes
; on output.  Keys and the screen work as in COMP80 FORTH (forth/forth.asm):
; RS while waiting for a key is rubout, any key while a program runs resets
; to the monitor, and RS from there comes back to Prolog with the clauses
; kept.

MAGIC:  equ 0C00h           ; MAGICV when the RAM below holds clauses
SYMEND: equ 0C02h           ; end of the symbol table
DBHEAD: equ 0C04h           ; first cell of the database, or 0: the cdr
DBTAIL: equ 0C06h           ; of a cell at 0C02h, the last one at first
HPERM:  equ 0C08h           ; heap top after the clauses
HP:     equ 0C0Ah           ; heap top
TR:     equ 0C0Ch           ; the trail: a list of the variables bound
CURS:   equ 0C0Eh           ; output position in screen memory
TOIN:   equ 0C10h           ; byte: read offset into TIB
NTIB:   equ 0C11h           ; byte: characters in TIB
NVARS:  equ 0C12h           ; byte: variables in the clause read
HOLE:   equ 0C14h           ; what COPY puts in place of the hole
B0:     equ 0C16h           ; what COPY puts in place of ! (less 1)
CONT:   equ 0C18h           ; goals still to prove
REST:   equ 0C1Ah           ; the goals after GOAL
GOAL:   equ 0C1Ch           ; the goal being proved
KEY:    equ 0C1Eh           ; its name
SPSV:   equ 0C20h           ; SP with the choice points, for FAIL
BASE:   equ 0C22h           ; SP with no choice points
HBASE:  equ 0C24h           ; first cell        } set at cold start
HLIM:   equ 0C26h           ; end of the heap   } from MEM8 or MEM32
SLIM:   equ 0C28h           ; lowest SP for a new choice point
CLS:    equ 0C2Ah           ; the clause being tried
SYMS:   equ 0C30h           ; symbol table, up to SYMTOP
SYMTOP: equ 0F00h
TIB:    equ 0F00h           ; input line (80 bytes; page aligned)
FRAME:  equ 0F50h           ; the 16 variables of the clause being copied
VNAMES: equ 0F70h           ; the names of the variables read
QVS:    equ 0F90h           ; the variables of the query
WBUF:   equ 0FB0h           ; name being read, counted (80 bytes, so any
                            ; name on a line fits)
STOP:   equ 1F00h           ; Z80 stack grows down from here (monitor uses 1Fxx)
MAGICV: equ 0D16Ah

CUTA:   equ SYMS            ; the first symbol records, 8 bytes apart
NILA:   equ SYMS+8          ; (see NAMES)
BUILT:  equ SYMS+16         ; the built-in predicates
NBUILT: equ 7

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

        org 0400h

; ---------------------------------------------------------------- cells

; HL = car, DE = cdr of the cell HL.  Changes A.
uncons: ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        ret

; Set the cdr of cell HL to DE.
setcdr: inc hl
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; HL = car or cdr of the cell HL; 0 gives 0.  Changes A.
cdr:    ld a,h
        or l
        ret z
        inc hl
        inc hl
        jr car1
car:    ld a,h
        or l
        ret z
car1:   ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

; HL = a new cell, not filled in.  Keeps BC, DE.
newcell: ld hl,(HP)
        push hl
        inc hl
        inc hl
        inc hl
        inc hl
        ld (HP),hl
        push de
        ld de,(HLIM)
        or a
        sbc hl,de
        pop de
        pop hl
        ret c
        ret z
        jp nomem

; HL = a new cell (DE . HL).  Keeps BC.
cons:   push hl
        call newcell
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        pop de
        ld (hl),e
        inc hl
        ld (hl),d
        dec hl
        dec hl
        dec hl
        ret

; NC if HL is a cell, C if not.  Changes A.
cellq:  ld a,l
        and 3
        scf
        ret nz
        ld a,h
        cp 10h
        ret

; Z if HL is a run-time variable.  Changes A.
varq:   ld a,l
        and 3
        cp 2
        ret nz
        ld a,h
        cp 10h
        sbc a,a
        ret

; HL = what HL is bound to, following variables.  Changes A.
deref:  call varq
        ret nz
        push hl
        res 1,l
        call car
        ld a,h
        or l
        jr z,dr9            ; unbound
        pop af
        jr deref
dr9:    pop hl
        ret

; Bind variable HL to DE, and put it on the trail.
bind:   res 1,l
        ld (hl),e
        inc hl
        ld (hl),d
        dec hl
        ex de,hl
        ld hl,(TR)
        call cons
        ld (TR),hl
        ret

; Unify HL and DE, or FAIL.
unify:  call deref
        ex de,hl
        call deref
        or a
        sbc hl,de
        add hl,de
        ret z
        call varq
        jr z,bind
        ex de,hl
        call varq
        jr z,bind
        call cellq
        jp c,fail
        ex de,hl
        call cellq
        jp c,fail
        push hl
        push de
        ex de,hl
        call car
        ex de,hl
        call car
        call unify          ; the cars
        pop hl
        call cdr
        ex de,hl
        pop hl
        call cdr
        jr unify            ; then the cdrs

; ---------------------------------------------------------------- copying

; HL = a copy of the clause HL, with new variables.
copyc:  push hl
        ld hl,FRAME
        ld b,32
cc0:    ld (hl),0
        inc hl
        djnz cc0
        pop hl

; HL = a copy of the stored term HL: variable k becomes FRAME[k] (made if
; it is new), the hole becomes HOLE and ! becomes B0+1.  Changes A, BC, DE.
copy:   bit 0,l
        ret nz              ; a number
        ld a,h
        or a
        jr z,cp2            ; 0, the hole or a variable
        cp 10h
        jr nc,cp4           ; a cell
        ld de,CUTA
        or a
        sbc hl,de
        add hl,de
        ret nz              ; an atom
        ld hl,(B0)
        inc hl
        ret
cp2:    ld a,l
        or a
        ret z
        cp 2
        jr nz,cp3
        ld hl,(HOLE)
        ret
cp3:    sub 6
        rrca
        ld e,a
        ld d,0
        ld hl,FRAME
        add hl,de
        ld a,(hl)
        inc hl
        or (hl)
        jr nz,cp3b          ; made already
        push hl
        call newcell
        ld (hl),0
        inc hl
        ld (hl),0
        inc hl
        ex de,hl
        pop hl
        ld (hl),d
        dec hl
        ld (hl),e
        ex de,hl
        ret
cp3b:   ld a,(hl)
        dec hl
        ld l,(hl)
        ld h,a
        ret

cp4:    push hl         ; a cell: copy its car and cdr
        call car
        call copy
        ex (sp),hl
        call cdr
        call copy
        pop de
        jp cons

; ---------------------------------------------------------------- solver

; Prove the goals CONT.  The Z80 stack holds only choice points.
solve:  ld (SPSV),sp
        ld hl,(CONT)
        ld a,h
        or l
        jp z,success
        call getgoal
        bit 0,l
        jr z,sv1
        dec hl              ; a cut: drop the choice points made since
        ld sp,hl
next:   ld hl,(REST)
        ld (CONT),hl
        jr solve
sv1:    ld hl,(KEY)
        ld de,-BUILT
        add hl,de
        ld a,h
        or a
        jr nz,sv2
        ld a,l
        cp NBUILT*8
        jr nc,sv2
        rrca
        rrca
        ld l,a
        ld de,btab
        add hl,de
        call car
        jp (hl)
sv2:    ld bc,(DBHEAD)

; Try the clauses for GOAL from clause cell BC on.
try:    call match
        ld a,b
        or c
        jp z,fail
        ld (CLS),bc
        call mnext          ; is there another?
        ld (B0),sp
        ld a,b
        or c
        jr z,tr1
        ld hl,(CONT)        ; a choice point
        push hl
        push bc
        ld hl,(HP)
        push hl
        ld hl,(SLIM)
        or a
        sbc hl,sp
        jp nc,deep
tr1:    ld (SPSV),sp
        ld hl,(REST)
        ld (HOLE),hl
        ld hl,(CLS)
        call car
        call copyc
        call uncons         ; HL = head, DE = body
        ld (CONT),de
        ld de,(GOAL)
        call unify
        jp solve

; Go back to the last choice point.
fail:   ld sp,(SPSV)
        ld hl,(BASE)
        or a
        sbc hl,sp
        jp z,nomore
        pop bc
        ld (HP),bc
        ld hl,(TR)          ; undo the bindings made since: the trail
bk1:    or a                ; cells above the old heap top
        sbc hl,bc
        add hl,bc
        jr c,bk2
        call uncons
        ld (hl),0
        inc hl
        ld (hl),0
        ex de,hl
        jr bk1
bk2:    ld (TR),hl
        pop bc
        pop hl
        ld (CONT),hl
        call getgoal
        jp try

; BC = the first clause cell from BC on whose head has the name KEY, or 0.
match:  ld a,b
        or c
        ret z
        ld h,b
        ld l,c
        call car
        call car
        call keyof
        ld de,(KEY)
        or a
        sbc hl,de
        ret z
mnext:  ld h,b
        ld l,c
        call cdr
        ld b,h
        ld c,l
        jr match

; HL = the name of the term HL.
keyof:  call cellq
        ret c
        jp car

; GOAL, REST and KEY from CONT; HL = GOAL.
getgoal: ld hl,(CONT)
        call uncons
        ld (REST),de
        call deref
        ld (GOAL),hl
        push hl
        call keyof
        ld (KEY),hl
        pop hl
        ret

; ---------------------------------------------------------------- built-ins

btab:   dw beq,bsum,btimes,bless,bwrite,bnl,fail

; HL, DE, BC = the arguments of GOAL (0 where there are none).
args:   ld hl,(GOAL)
        call cdr
        call uncons
        call deref
        push hl
        ex de,hl
        call uncons
        call deref
        push hl
        ex de,hl
        call car
        call deref
        ld b,h
        ld c,l
        pop de
        pop hl
        ret

; EQ(X,Y): X and Y unify.
beq:    call args
unext:  call unify
next2:  jp next

; SUM(X,Y,Z): X + Y = Z, given any two of them.
bsum:   call args
        bit 0,l
        jr z,sm2            ; X = Z - Y
        bit 0,e
        jr z,sm1            ; Y = Z - X
        add hl,de
        dec hl
        ld d,b
        ld e,c
        jr unext
sm1:    ex de,hl
sm2:    push hl
        ld h,b
        ld l,c
        bit 0,l
        jp z,fail
        bit 0,e
        jp z,fail
        or a
        sbc hl,de
        inc hl
        pop de
        jr unext

; TIMES(X,Y,Z): X * Y = Z, given X and Y (which must be numbers).
btimes: call args
        push bc
        sra h
        rr l
        ex de,hl
        sra h
        rr l
        ld b,h              ; HL = HL * DE
        ld c,l
        ld hl,0
        ld a,16
mu1:    add hl,hl
        sla c
        rl b
        jr nc,mu2
        add hl,de
mu2:    dec a
        jr nz,mu1
        add hl,hl
        inc hl
        pop de
        jr unext

; LESS(X,Y): X < Y.
bless:  call args
        ld a,h              ; signed HL < DE
        xor 80h
        ld h,a
        ld a,d
        xor 80h
        ld d,a
        sbc hl,de
        jp nc,fail
        jr next2

bwrite: call args
        call print
        jr next2

bnl:    call crlf
        jr next2

; ---------------------------------------------------------------- arithmetic

neghl:  xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
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

; Print number HL.
prnum:  sra h
        rr l
        bit 7,h
        jr z,pn1
        ld a,'-'
        call putc
        call neghl
pn1:    ld de,10
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
        jp putc

; ---------------------------------------------------------------- printer

; Print term HL.
print:  call deref
        bit 0,l
        jr nz,prnum
        call cellq
        jr nc,prcell
        ld a,h
        cp 10h
        jr nc,prvar         ; an unbound variable
        ld b,(hl)           ; an atom
        inc hl
        jp typen
prvar:  ld a,'_'
        call putc
        res 7,h
        jr prnum

prcell: push hl             ; a compound term ends in 0
pc1:    call cdr
        call deref
        call cellq
        jr nc,pc1
        ld a,h
        or l
        pop hl
        jr nz,prlist
        push hl
        call car
        call print
        ld a,'('
        call putc
        pop hl
        call cdr
        call prseq
        ld a,')'
        jp putc
prlist: ld a,'['
        call putc
        call prseq
        ld de,NILA
        or a
        sbc hl,de
        add hl,de
        jr z,pl9
        ld a,':'
        call putc
        call print
pl9:    ld a,']'
        jp putc

; Print the list HL with commas between; HL = what it ends in.
prseq:  push hl
        call car
        call print
        pop hl
        call cdr
        call deref
        call cellq
        ret c
        ld a,','
        call putc
        jr prseq

; ---------------------------------------------------------------- names

; NC if A is a letter or a digit.
alnum:  cp '0'
        ret c
        cp '9'+1
        ccf
        ret nc
        cp 'A'
        ret c
        cp 'Z'+1
        ccf
        ret

; Read a name; HL = it as an atom.
rname:  ld de,WBUF+1
rnm1:   call peekc
        call alnum
        jr c,rnm9
        ld (de),a
        inc e
        call getc
        jr rnm1
rnm9:   ld a,e
        sub (WBUF+1)&0FFh
        ld (WBUF),a

; HL = the atom named in WBUF, made if it is new.
intern: ld hl,SYMS
in1:    ld de,(SYMEND)
        or a
        sbc hl,de
        add hl,de
        jr z,in5
        push hl
        ld de,WBUF
        ld a,(de)
        ld b,a
        inc b
in2:    ld a,(de)
        cp (hl)
        jr nz,in3
        inc hl
        inc de
        djnz in2
        pop hl
        ret
in3:    pop hl
        ld a,(hl)
        add a,4
        and 0FCh
        add a,l
        ld l,a
        jr nc,in1
        inc h
        jr in1
in5:    ld a,(WBUF)         ; new: is there room?
        add a,4
        and 0FCh
        ld c,a
        ld b,0
        push hl
        add hl,bc
        ld a,h
        cp SYMTOP/256
        jp nc,nomem
        ld (SYMEND),hl
        pop de
        push de
        ld hl,WBUF
        ld c,(hl)
        inc c
        ldir
        pop hl
        ret

cls:    ld hl,VRAM+40h
        ld (CURS),hl
        jp CLS64

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If Prolog was
; waiting for a key, the NMI's return address (KEYRET) is on top of the
; stack: give RAWKEY a rubout (0FFh).  Otherwise start (or restart).

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

warm:   ld sp,STOP
        ld hl,(MAGIC)
        ld de,MAGICV
        or a
        sbc hl,de
        jr z,wm2
        ld hl,8000h         ; cold start.  Without the expansion, 8800h
        ld a,(hl)           ; is the screen again.
        cpl
        ld (8800h),a
        cp (hl)
        ld hl,mem8
        jr z,wm1
        ld hl,mem32
wm1:    ld de,HBASE
        ld bc,6
        ldir
        ld hl,SYMS          ; the built-in names, 8 bytes apart, with
        ld b,NAMES8         ; 0s between for INTERN to step over
wm3:    ld (hl),0
        inc hl
        djnz wm3
        ld hl,names
        ld de,SYMS
wm4:    push de
        ld c,(hl)
        inc c
        ldir
        pop de
        ld a,e
        add a,8
        ld e,a
        ld a,(hl)
        or a
        jr nz,wm4
        ld (SYMEND),de
        ld h,a
        ld l,a
        ld (DBHEAD),hl
        ld hl,DBHEAD-2
        ld (DBTAIL),hl
        ld hl,(HBASE)
        ld (HPERM),hl
        ld hl,MAGICV
        ld (MAGIC),hl
wm2:    ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " PROLOG",0
        call crlf
        call cls
        jr repl

;               HBASE  HLIM   SLIM
mem8:   dw      1000h, 1C00h, 1C80h
mem32:  dw      8800h, 0FFF0h, 1080h

names:  db 1,"!",2,"[]",2,"EQ",3,"SUM",5,"TIMES",4,"LESS"
        db 5,"WRITE",2,"NL",4,"FAIL",0
NAMES8: equ 9*8

; Print the message after the CALL and start again.
erro:   call fresh
        pop hl
        call prs
abort:  call crlf
        ld a,(NTIB)         ; forget the rest of the line
        ld (TOIN),a

; Read a clause and keep it, or a query and answer it.
repl:   ld sp,STOP
        ld hl,(HPERM)
        ld (HP),hl
        ld hl,0
        ld (TR),hl
        ld (NVARS),hl
        call skipws
        cp '?'
        jr z,query
        call rterm          ; the head
        push hl
        call skipws
        ld de,2             ; a fact: the body is just the hole
        cp ':'
        jr nz,rc1
        call getc
        ld a,'-'
        call expect
        call rgoals
rc1:    push de
        ld a,'.'
        call expect
        pop hl
        pop de
        call cons           ; (head . body)
        ex de,hl
        ld hl,0
        call cons           ; on the end of the database
        ex de,hl
        ld hl,(DBTAIL)
        ld (DBTAIL),de
        call setcdr
        ld hl,(HP)
        ld (HPERM),hl
        jr repl

query:  call getc
        ld a,'-'
        call expect
        call rgoals
        push de
        ld a,'.'
        call expect
        pop hl
        ld (BASE),sp
        ld (B0),sp
        ld de,0
        ld (HOLE),de
        call copyc
        ld (CONT),hl
        ld hl,FRAME
        ld de,QVS
        ld bc,32
        ldir
        jp solve

; The query is proved: show the variables (or YES), and on ; look for
; another answer.
success: ld hl,VNAMES
        ld a,(NVARS)
        or a
        jr z,yes
su1:    push af
        push hl
        call car            ; the name
        ld a,h
        or a
        jr z,su2            ; ?
        call fresh
        call print
        call prsi
        db " = ",0
        pop hl
        push hl
        ld de,QVS-VNAMES
        add hl,de
        call car
        call print
su2:    pop hl
        inc hl
        inc hl
        pop af
        dec a
        jr nz,su1
su3:    ld hl,(BASE)
        or a
        sbc hl,sp
        jr z,done           ; no other way to try
        ld a,'?'
        call rawkey
        cp ';'
        jr nz,done
        call putc
        jp fail
yes:    call fresh
        call prsi
        db "YES",0
        jr su3
nomore: call fresh
        call prsi
        db "NO",0
done:   call crlf
        jp repl

deep:   call erro
        db "TOO DEEP",0
nomem:  call erro
        db "NO MEM",0
synerr: call erro
        db "SYNTAX",0

; ---------------------------------------------------------------- reader

; HL = a term.
rterm:  call skipws
        cp '['
        jp z,rlist
        cp '!'
        jr nz,rp2
        call getc
        ld hl,CUTA
        ret
rp2:    cp '?'
        jr z,ranon
        cp '-'
        jr z,rnum
        call alnum
        jp c,synerr
        cp 'A'
        jr c,rnum
        call rname          ; HL = the name as an atom
        ld a,(WBUF)         ; a letter then digits is a variable
        ld b,a
        ld de,WBUF+2
rv0:    dec b
        jr z,rvar
        ld a,(de)
        inc de
        cp 'A'
        jr c,rv0
        push hl             ; an atom, or f(...)
        call peekc
        pop hl
        cp '('
        ret nz
        push hl
        call getc
        call rseq
        ld a,')'
        call expect
        pop de
        jp cons

ranon:  call getc
        ld hl,0
; HL = variable number k for name HL (4k+6), new if it is a new name or 0.
rvar:   ld de,VNAMES
        ld a,(NVARS)
        ld b,a
        ld c,6
rv1:    ld a,b
        or a
        jr z,rv2
        ld a,(de)
        inc de
        cp l
        ld a,(de)
        inc de
        jr nz,rv1b
        cp h
        jr nz,rv1b
        or a
        jr nz,rv3
rv1b:   ld a,c
        add a,4
        ld c,a
        dec b
        jr rv1
rv2:    ld a,(NVARS)
        cp 16
        jp nc,synerr
        inc a
        ld (NVARS),a
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
rv3:    ld h,0
        ld l,c
        ret

; The next character must be A: take it.  Keeps HL.
expect: push hl
        ld b,a
        call skipws
        cp b
        jp nz,synerr
        call getc
        pop hl
        ret

; A number, perhaps negative.  A = its first character.
rnum:   ld de,0
        cp '-'
        push af
        jr nz,rn1
        call getc
rn1:    call peekc
        sub '0'
        cp 10
        jr nc,rn9
        push af
        call getc
        pop af
        ld h,d
        ld l,e
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl
        ld e,a
        ld d,0
        add hl,de
        ex de,hl
        jr rn1
rn9:    pop af
        ex de,hl
        call z,neghl
        add hl,hl
        inc hl
        ret

; [a,b,c], [a:T] or [].
rlist:  call getc
        call skipws
        cp ']'
        jr nz,rl1
        call getc
        ld hl,NILA
        ret
rl1:    call rseq
        push hl
        push de
        cp ':'
        ld hl,NILA
        jr nz,rl2
        call getc
        call rterm
rl2:    ex de,hl
        pop hl
        call setcdr
        ld a,']'
        call expect
        pop hl
        ret

; DE = goals separated by commas, ending in the hole.
rgoals: call rseq
        ex de,hl
        inc hl
        inc hl
        ld (hl),2
        ret

; HL = the list of terms separated by commas, DE = its last cell, A = the
; character after them.
rseq:   ld de,0
        ld h,d
        ld l,e
        call cons           ; a cell in front
        push hl
        push hl             ; the last cell
rs1:    call rterm
        ex de,hl
        ld hl,0
        call cons
        ex de,hl
        pop hl
        call setcdr
        push de
        call skipws
        cp ','
        jr nz,rs9
        call getc
        jr rs1
rs9:    pop de
        pop hl
        push af
        call cdr
        pop af
        ret

; A = the next character of input, not taken; HL -> it.  Reads a new line
; when this one is used up.
peekc:  ld a,(NTIB)
        ld hl,TOIN
        cp (hl)
        jr nz,pk1
        call accept
        jr peekc
pk1:    ld l,(hl)
        ld h,TIB/256
        ld a,(hl)
        ret

getc:   call peekc
        ld hl,TOIN
        inc (hl)
        ret

; Skip spaces and % comments.  A = the next character, not taken.
skipws: call peekc
        cp ' '
        jr z,sk1
        cp '%'
        ret nz
        ld a,(NTIB)
        ld (TOIN),a
        jr skipws
sk1:    call getc
        jr skipws

; ---------------------------------------------------------------- terminal

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

; Read a line into TIB, echoing it, with a space on the end.
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
ac9:    ld a,' '
        ld (de),a
        inc e
        ld a,e
        ld (NTIB),a
        xor a
        ld (TOIN),a
        jr crlf

; Start a new line unless at the start of one.
fresh:  ld a,(CURS)
        and 3Fh
        ret z

; New line: blank the rest of this line and move to the next.  Keeps BC,
; DE, HL.
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

; Print character A.  ASCII 40h-5Fh go to the display's 5-bit codes.
; Keeps everything but AF.
putc:   push hl
        cp 40h
        jr c,pc2
        and 1Fh
pc2:    ld hl,(CURS)
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

; Print the string after the CALL, up to a 0 byte.  Keeps HL.
prsi:   ex (sp),hl
        call prs
        ex (sp),hl
        ret

; Print the string at HL, up to a 0 byte.
prs:    ld a,(hl)
        inc hl
        or a
        ret z
        call putc
        jr prs

; Print B characters from HL.
typen:  inc b
ty1:    dec b
        ret z
        ld a,(hl)
        inc hl
        call putc
        jr ty1

part2_end:
        ds 0C00h-$,0FFh
