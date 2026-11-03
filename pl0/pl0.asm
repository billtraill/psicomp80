; COMP80 PL/0
;
; A compiler for PL/0, Niklaus Wirth's teaching language, in the 2 KB of ROM
; (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh) is unchanged.  As
; with BURP, the RS key enters it: the monitor's NMI handler jumps to 0800h.
;
; The program is typed in numbered lines and kept as typed, as in COMP80
; BASIC: each line its number (2 bytes, low first), its text and 0Dh, from
; 0C04h up to TXTEND.  RUN compiles the whole program in one pass, by
; recursive descent, straight into Z80 machine code after the text, and
; calls it.  CODE compiles it and says how long the code is.
;
;   program   = block "." .
;   block     = [CONST name = number {, name = number} ;]
;               [VAR name {, name} ;]
;               {PROCEDURE name ; block ;} statement .
;   statement = [name := expression | CALL name | ? name | ! expression
;               | BEGIN statement {; statement} END | IF condition THEN
;               statement | WHILE condition DO statement
;               | PLOT expression , expression | CLS] .
;   condition = ODD expression | expression (= # < <= > >=) expression .
;   expression = [-] term {(+|-) term} .
;   term      = factor {(*|/) factor} .
;   factor    = name | number | ( expression ) .
;
; Names follow the blocks they are declared in, but every variable has one
; place in memory (1C00h up), so a procedure that calls itself shares its
; variables with itself, as in FORTRAN.
;
; Code: an expression leaves its value in HL.  A number is LD HL,n and a
; variable LD HL,(v); an operator is PUSH HL, the right operand, POP DE and
; the operation on DE and HL (ADD HL,DE, or a call for * / and the
; comparisons).  When the right operand is a single load, the PUSH becomes
; EX DE,HL and there is no POP.  Assignment is LD (v),HL; IF and WHILE test
; with LD A,H / OR L / JP Z; CALL is CALL; a procedure ends with RET.  A block
; jumps over its procedures to its statement.
;
; Keys and screen are handled as in COMP80 BASIC and FORTH: the monitor's
; NMI handler echoes each key and wakes the HALT in RAWKEY; RS while waiting
; is a rubout and RS at any other time (re)starts PL/0, keeping the program.
; Any key while a program runs resets to the monitor; RS comes back with the
; program kept.  Line 0 shows PL/0; lines 1-31 scroll.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
TXTEND: equ 0C02h           ; end of the program text; the code follows it
PROG:   equ 0C04h           ; first line
MAGICV: equ 0A0F0h
TOPH:   equ 18h             ; the text ends below 1800h
CODEH:  equ 1Ah             ; the code ends below 1A00h
SYMS:   equ 1A00h           ; names: the name (80h on its last letter),
SYMH:   equ 1Ch             ;   its kind (0 CONST, 1 VAR, 2 PROCEDURE)
VARS:   equ 1C00h           ;   and its value; then the variables
TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
IDBUF:  equ 1D50h           ; the last name read (80 bytes)
CURS:   equ 1DA0h           ; output position in screen memory
LINEP:  equ 1DA2h           ; the line being compiled, 0 if none
SRCP:   equ 1DA4h           ; where the compiler is reading
TOK:    equ 1DA6h           ; the token just read
TOKV:   equ 1DA7h           ; its value, for a number
CODEP:  equ 1DA9h           ; where the next byte of code goes
SYMEND: equ 1DABh           ; end of the names
VARP:   equ 1DADh           ; the next free variable
KEYBUF: equ 1DC0h           ; digits and keys while KEY waits
S0:     equ 1F00h           ; stack (monitor uses 1Fxx)

; Tokens: 0 end of the text, 1 a name, 2 a number, 3 :=, 4 <=, 5 >=, the
; other signs as themselves, and the words from 80h in the order of kwtab.
TNAME:  equ 1
TNUM:   equ 2
TBEC:   equ 3
KCONST: equ 80h
KVAR:   equ 81h
KPROC:  equ 82h
KBEGIN: equ 83h
KEND:   equ 84h
KCALL:  equ 85h
KIF:    equ 86h
KTHEN:  equ 87h
KWHILE: equ 88h
KDO:    equ 89h
KODD:   equ 8Ah
KPLOT:  equ 8Bh
KCLS:   equ 8Ch
KPEEK:  equ 8Dh
KPOKE:  equ 8Eh
KKEY:   equ 8Fh
KRUN:   equ 90h             ; the commands
KLIST:  equ 91h
KCODE:  equ 92h
KNEW:   equ 93h

        org 0400h

kwtab:  db "CONS",0D4h,"VA",0D2h,"PROCEDUR",0C5h,"BEGI",0CEh,"EN",0C4h
        db "CAL",0CCh,"I",0C6h,"THE",0CEh,"WHIL",0C5h,"D",0CFh,"OD",0C4h
        db "PLO",0D4h,"CL",0D3h,"PEE",0CBh,"POK",0C5h,"KE",0D9h
        db "RU",0CEh,"LIS",0D4h,"COD",0C5h,"NE",0D7h,0

; The comparisons: the token, then which of < = > make it true (1 2 4).
reltab: db '=',2,'#',5,'<',1,'>',4,4,3,5,6

; ---------------------------------------------------------------- scanning
; Read the next token into TOK (and TOKV or IDBUF).  Changes everything.

next:   ld hl,(SRCP)
nx0:    ld a,(hl)
        cp 0Dh
        jr nz,nx2
        inc hl
nxline: ld de,(TXTEND)      ; HL = the start of a line
        or a
        sbc hl,de
        add hl,de
        ld a,0              ; past the last line: the end
        jp nc,settok
        ld (LINEP),hl
        inc hl
        inc hl
        jr nx0
nx2:    inc hl
        cp ' '
        jr z,nx0
        cp 'A'
        jr c,nx4
        cp 'Z'+1
        jr nc,nx4
        dec hl              ; a name: copy it to IDBUF
        ld de,IDBUF
nx3:    ld a,(hl)
        sub '0'
        cp 10
        jr c,nx3a
        sub 'A'-'0'
        cp 26
        jr nc,nx3e
nx3a:   ld a,(hl)
        ld (de),a
        inc de
        inc hl
        jr nx3
nx3e:   ld (SRCP),hl
        dec de
        ld a,(de)
        or 80h
        ld (de),a
        ld hl,kwtab         ; one of the words?
        ld b,80h
kw1:    ld a,(hl)
        or a
        ld a,TNAME
        jr z,settok
        ld de,IDBUF
kw2:    ld a,(de)
        cp (hl)
        jr nz,kw3
        inc hl
        inc de
        rla
        jr nc,kw2
        ld a,b
        jr settok
kw3:    ld a,(hl)
        inc hl
        rla
        jr nc,kw3
        inc b
        jr kw1
nx4:    cp '0'
        jr c,nx5
        cp '9'+1
        jr nc,nx5
        dec hl              ; a number
        ex de,hl
        call getnum
        ld (TOKV),hl
        ex de,hl
        ld a,TNUM
        jr nx7
nx5:    ld c,a              ; a sign: := <= >= or one character
        ld a,(hl)
        cp '='
        ld a,c
        jr nz,nx7
        ld b,TBEC
        cp ':'
        jr z,nx6
        inc b
        cp '<'
        jr z,nx6
        inc b
        cp '>'
        jr nz,nx7
nx6:    inc hl
        ld a,b
nx7:    ld (SRCP),hl
settok: ld (TOK),a
        ret

; The token must be the byte after the CALL: go past it.
expect: ex (sp),hl
        ld b,(hl)
        inc hl
        ex (sp),hl
        ld a,(TOK)
        cp b
        jp nz,ersyn
        jp next

; After an item of CONST or VAR: Z if a comma follows (gone past), NZ if
; the semicolon at the end does.
sepq:   call next
sepq2:  ld a,(TOK)
        cp ','
        ret z
        call expect
        db ';'
        or 1
        ret

; The token must be a name.
wantid: ld a,(TOK)
        cp TNAME
        ret z
        jp ersyn

; ---------------------------------------------------------------- names

; Add the name in IDBUF, of kind A, with value HL.
define: push hl
        push af
        ld de,(SYMEND)
        ld hl,IDBUF
df1:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        rla
        jr nc,df1
        pop af
        ld (de),a
        inc de
        pop hl
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (SYMEND),hl
        ld a,h
        cp SYMH
        ret c
        jp ermem

; Find the name in IDBUF, the latest if there are several: A = its kind, DE
; = its value.
lookup: ld hl,SYMS
        ld bc,0
lk1:    ld de,(SYMEND)
        or a
        sbc hl,de
        add hl,de
        jr nc,lk9
        ld de,IDBUF
lk2:    ld a,(de)
        cp (hl)
        jr nz,lk4
        inc de
        inc hl
        rla
        jr nc,lk2
        ld b,h              ; this one: BC = its kind
        ld c,l
        jr lk5
lk4:    ld a,(hl)
        inc hl
        rla
        jr nc,lk4
lk5:    inc hl
        inc hl
        inc hl
        jr lk1
lk9:    ld a,b
        or c
        jp z,ername
        ld h,b
        ld l,c
        ld a,(hl)
        inc hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ret

; A variable's name: DE = its address.
varid:  call wantid
varid2: call lookup
        dec a
        ret z
        jp ername

; ---------------------------------------------------------------- code

; Put A, then HL, into the code.  emit1 keeps HL.
emcall: ld a,0CDh           ; CALL HL
emit3:  call emit1
emit2:  ld a,l
        call emit1
        ld a,h
emit1:  push hl
        ld hl,(CODEP)
        ld (hl),a
        inc hl
        ld (CODEP),hl
        ld a,h
        cp CODEH
        pop hl
        ret c
        jp ermem

; PUSH HL, the code of the routine at HL, POP DE.  If that code is a single
; 3-byte load, EX DE,HL in front of it does the same.
pushop: push hl
        ld a,0E5h           ; PUSH HL
        call emit1
        ld hl,(CODEP)
        ex (sp),hl
        call jphl
        pop hl
        ld de,(CODEP)
        ex de,hl
        or a
        sbc hl,de
        ld a,l
        cp 3
        ld a,0D1h           ; POP DE
        jp nz,emit1
        dec de
        ld a,0EBh           ; EX DE,HL
        ld (de),a
        ret
jphl:   jp (hl)

; Jump if the condition just compiled is false (its routine returns Z):
; HL = where the jump's address goes.
test:   ld a,0CAh           ; JP Z,
; A jump A forward: HL = where its address goes.
jfwd:   call emit3
        ld hl,(CODEP)
        dec hl
        dec hl
        ret

; Put the address of the next byte of code at HL.
patch:  ld de,(CODEP)
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; ---------------------------------------------------------------- compiler

; Compile the program.  Leaves the code from TXTEND to CODEP.
compile:
        ld hl,SYMS
        ld (SYMEND),hl
        ld hl,VARS
        ld (VARP),hl
        ld hl,(TXTEND)
        ld (CODEP),hl
        ld hl,PROG
        call nxline
        call block
        call expect
        db '.'
        ld hl,0
        ld (LINEP),hl
        ld a,0C9h           ; RET
        jp emit1

block:  ld hl,(SYMEND)      ; its names go at the end
        push hl
        ld a,(TOK)
        cp KCONST
        jr nz,bl3
bl1:    call next           ; CONST name = number, ...
        call wantid
        call next
        call expect
        db '='
        call expect
        db TNUM
        ld hl,(TOKV)
        xor a
        call define
        call sepq2
        jr z,bl1
bl3:    ld a,(TOK)
        cp KVAR
        jr nz,bl5
bl4:    call next           ; VAR name, ...
        call wantid
        ld hl,(VARP)
        push hl
        inc hl
        inc hl
        ld (VARP),hl
        pop hl
        ld a,1
        call define
        call sepq
        jr z,bl4
bl5:    ld a,0C3h           ; JP over the procedures
        call jfwd
        push hl
bl6:    ld a,(TOK)
        cp KPROC
        jr nz,bl7
        call next           ; PROCEDURE name ; block ;
        call wantid
        ld hl,(CODEP)
        ld a,2
        call define
        call next
        call expect
        db ';'
        call block
        ld a,0C9h           ; RET
        call emit1
        call expect
        db ';'
        jr bl6
bl7:    pop hl              ; the JP goes to the statement
        call patch
        call stmt
        pop hl              ; forget its names
        ld (SYMEND),hl
        ret

; A statement: go past its first token, then to its routine; anything else
; is an empty statement.
stmt:   ld a,(TOK)
        ld hl,stab
        ld b,10
st0:    cp (hl)
        inc hl
        jr z,st1
        inc hl
        inc hl
        djnz st0
        ret
st1:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl
        jp next

stab:   db TNAME
        dw sset
        db KCALL
        dw scall
        db '?'
        dw sread
        db '!'
        dw swrite
        db KBEGIN
        dw sbegin
        db KIF
        dw sif
        db KWHILE
        dw swhile
        db KPLOT
        dw splot
        db KCLS
        dw scls
        db KPOKE
        dw spoke

sset:   call varid2         ; name := expression
        push de
        call expect
        db TBEC
        call expr
        pop hl
sst1:   ld a,22h            ; LD (v),HL
        jp emit3

scall:  call wantid
        call lookup
        cp 2
        jp nz,ername
        ex de,hl
        call emcall
        jp next

sread:  call varid
        push de
        ld hl,rinput
        call emcall
        call next
        pop hl
        jr sst1

swrite: call expr
        ld hl,rprint
        jp emcall

sbegin: call stmt
        ld a,(TOK)
        cp ';'
        jr nz,sb1
        call next
        jr sbegin
sb1:    call expect
        db KEND
        ret

sif:    call cond
        call test
        push hl
        call expect
        db KTHEN
        call stmt
        pop hl
        jp patch

swhile: ld hl,(CODEP)
        push hl
        call cond
        call test
        push hl
        call expect
        db KDO
        call stmt
        pop de
        pop hl
        push de
        ld a,0C3h           ; JP back to the test
        call emit3
        pop hl
        jp patch

splot:  ld hl,rplot
        ld a,0CDh           ; CALL rplot
spl:    push hl
        push af
        call expr
        call expect
        db ','
        ld hl,expr
        call pushop
        pop af
        pop hl
        jp emit3

spoke:  ld hl,0012h         ; LD A,L / LD (DE),A / NOP
        ld a,7Dh
        jr spl

scls:   ld hl,cls
        jp emcall

cond:   ld a,(TOK)
        cp KODD
        jr nz,cd1
        call next
        call expr
        ld hl,45CBh         ; BIT 0,L
        jp emit2
cd1:    call expr
        ld a,(TOK)
        ld hl,reltab
        ld b,6
cd2:    cp (hl)
        inc hl
        jr z,cd3
        inc hl
        djnz cd2
        jp ersyn
cd3:    ld a,(hl)
        push af
        call next
        ld hl,expr
        call pushop
        ld hl,rrel
        call emcall
        pop af
        jp emit1

expr:   ld a,(TOK)
        push af
        cp '-'
        call z,next
        call term
        pop af
        cp '-'
        ld hl,neghl
        call z,emcall
ex1:    ld a,(TOK)
        cp '+'
        jr z,ex2
        cp '-'
        ret nz
ex2:    push af
        call next
        ld hl,term
        call pushop
        pop af
        cp '+'
        ld a,19h            ; ADD HL,DE
        jr z,ex3
        ld hl,0B7EBh        ; EX DE,HL / OR A
        call emit2
        ld hl,52EDh         ; SBC HL,DE
        call emit2
        jr ex1
ex3:    call emit1
        jr ex1

; ---------------------------------------------------------------- run time
; (the rest is after the entry)

rinput: ld a,'?'
        call putc
        call accept
        ld de,TIB
        jp getnum

; HL = -HL, and HL = |HL|.
neghl:  xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

abshl:  bit 7,h
        ret z
        jr neghl

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS, which comes only in a
; HALT.  If it was RAWKEY's, the NMI's return address (KEYRET) is on top of
; the stack: give RAWKEY a rubout (0FFh).  Otherwise, at READY or in KEY,
; start (or restart) PL/0.  The low byte of the address tells them apart.

entry:  ex (sp),hl
        ld a,l
        ex (sp),hl
        cp keyret & 0FFh
        jr nz,warm
        ld a,0FFh
        ret

warm:   ld sp,S0
        ld hl,(MAGIC)
        ld de,MAGICV
        or a
        sbc hl,de
        call nz,new0        ; no program in RAM: start an empty one
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " PL/0",0
        call crlf
        call cls

ready:  ld sp,S0
        ld hl,0
        ld (LINEP),hl
        call newl
        call prsi
        db "OK",0
        call crlf
getln:  call accept
        ld de,TIB
        call getnum
        jr c,gl1
        ld (SRCP),de        ; not numbered: a command,
        ld hl,ready         ; which returns to READY
        push hl
        call next
        ld a,(TOK)
        ld de,(SRCP)
        cp KRUN
        jr z,srun
        cp KLIST
        jp z,slist
        cp KCODE
        jr z,scode
        cp KNEW
        jp z,new0
        jp ersyn
gl1:    push de             ; a numbered line: replace the old one
        push hl
        call findln
        call z,delln
        pop hl
        push hl
        call findln         ; where it goes
        pop bc
        pop de
        ld a,(de)           ; keep the indenting after one space
        cp ' '
        jr nz,gl2
        inc de
gl2:    push de
        call skipsp
        pop de
        cp 0Dh
        jr z,getln          ; just the number: deleted
        push bc             ; number
        push de             ; text
        push hl             ; where
        ld bc,2             ; length with the number
ed1:    ld a,(de)
        inc de
        inc bc
        cp 0Dh
        jr nz,ed1
        ld hl,(TXTEND)
        push hl
        add hl,bc
        ld a,h
        cp TOPH
        jp nc,ermem
        ld (TXTEND),hl
        ex de,hl
        dec de              ; last byte of the new end
        pop hl              ; old end
        pop bc              ; where
        push bc
        or a
        sbc hl,bc           ; bytes to move up
        ld b,h
        ld c,l
        pop hl
        push hl
        add hl,bc
        dec hl
        ld a,b
        or c
        jr z,ed2
        lddr
ed2:    pop hl
        pop de
        pop bc
        ld (hl),c
        inc hl
        ld (hl),b
ed3:    inc hl
        ld a,(de)
        ld (hl),a
        inc de
        cp 0Dh
        jr nz,ed3
        jp getln

; ---------------------------------------------------------------- commands

srun:   call compile
        ld hl,VARS          ; the variables start at 0
        ld b,0
ru1:    ld (hl),0
        inc hl
        djnz ru1
        ld hl,(TXTEND)
        jp (hl)

scode:  call compile
        ld hl,(CODEP)
        ld de,(TXTEND)
        or a
        sbc hl,de
        jp prnum

slist:  call getnum
        call findln
ls1:    ld bc,(TXTEND)
        or a
        sbc hl,bc
        add hl,bc
        ret nc
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call prnum
        ld a,' '
        call putc
        pop hl
        inc hl
ls2:    inc hl
        ld a,(hl)
        cp 0Dh
        jr z,ls3
        call putc
        jr ls2
ls3:    inc hl
        call crlf
        jr ls1

new0:   ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,PROG
        ld (TXTEND),hl
        ret

; ---------------------------------------------------------------- program

; HL = the first line numbered HL or more (TXTEND if none), Z if it is
; numbered HL.  Keeps DE.
findln: push de
        ex de,hl
        ld hl,PROG
fl1:    ld bc,(TXTEND)
        or a
        sbc hl,bc
        add hl,bc
        jr nc,fl3
        ld c,(hl)
        inc hl
        ld b,(hl)
        dec hl
        push hl
        ld h,b
        ld l,c
        or a
        sbc hl,de
        pop hl
        jr nc,fl4
        call nxtln
        jr fl1
fl3:    or 1
fl4:    pop de
        ret

; HL = the line after the line at HL.
nxtln:  inc hl
        inc hl
nl1:    ld a,(hl)
        inc hl
        cp 0Dh
        jr nz,nl1
        ret

; Take the line at HL out of the program.
delln:  ld d,h
        ld e,l
        call nxtln
        push hl
        ld hl,(TXTEND)
        pop bc
        or a
        sbc hl,bc
        push bc
        ld b,h
        ld c,l
        pop hl
        ld a,b
        or c
        jr z,dl1
        ldir
dl1:    ld (TXTEND),de
        ret

; ---------------------------------------------------------------- scanning

; A = the next character at DE that isn't a space.
skipsp: ld a,(de)
        cp ' '
        ret nz
        inc de
        jr skipsp

; If DE is at a number, CY and HL = it; if not, NC and HL = 0.  Changes BC.
getnum: call skipsp
        ld hl,0
        sub '0'
        cp 10
        ret nc
gn1:    ld b,h
        ld c,l
        add hl,hl
        add hl,hl
        add hl,bc
        add hl,hl
        ld c,a
        ld b,0
        add hl,bc
        inc de
        ld a,(de)
        sub '0'
        cp 10
        jr c,gn1
        scf
        ret

; ---------------------------------------------------------------- graphics

; Set the point X = DE (0-127), Y = HL (0-61) on lines 1-31, if it is on
; the screen.
rplot:  ld b,d
        ld c,e
        ld a,b
        or h
        ret nz
        ld a,c
        cp 128
        ret nc
        ld a,l
        cp 62
        ret nc
        ld b,1              ; top left 1, top right 2,
        srl c               ; bottom right 4, bottom left 8
        jr nc,rp1
        ld b,2
rp1:    srl l
        jr nc,rp2
        ld a,b
        xor 3
        add a,a
        add a,a
        ld b,a
rp2:    inc l
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,l
        or c
        ld l,a
        set 7,h
        ld a,(hl)           ; the points already set
        xor 40h
        cp 10h
        jr c,rp3
        xor a
rp3:    or b
        or 40h
        ld (hl),a
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

cls:    ld hl,VRAM+40h
        ld (CURS),hl
        jp CLS64

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

; Print HL, signed.  Keeps DE.
prnum:  bit 7,h
        jr z,pn1
        ld a,'-'
        call putc
        call neghl
pn1:    push de
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

; ---------------------------------------------------------------- errors

ersyn:  call error
        db "SYNTAX?",0
ername: call error
        db "NAME?",0
erdiv:  call error
        db "DIVIDE?",0
ermem:  call error
        db "FULL",0

error:  call newl
        pop hl
        call prs
        ld hl,(LINEP)
        ld a,h
        or l
        jr z,er1
        call prsi
        db " IN ",0
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call prnum
er1:    call crlf
        jp ready

; ---------------------------------------------------------------- keyboard

; Wait for a key, showing _ at the cursor meanwhile.  Returns A = the ASCII
; key, 5Fh for Return and 0FFh for rubout.  Leaves the screen as it was (the
; NMI handler's echo is undone).  Keeps HL, DE.
rawkey: push de
        push hl
        ld de,(CURS)
        ld a,(de)
        ld l,a
        ld a,1Fh            ; cursor: _
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
        cp 20h
        ret nc
        add a,40h
        ret

; Read a line into TIB, echoing it, ending with 0Dh.  Changes DE.
accept: ld de,TIB
ac1:    call rawkey
        cp 5Fh              ; Return
        jr z,ac9
        cp 0FFh             ; rubout
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
ac9:    ld a,0Dh
        ld (de),a
        jp crlf

; ---------------------------------------------------------------- compiler
; (continued: terms and factors)

term:   call factor
tm1:    ld a,(TOK)
        ld hl,rmul
        cp '*'
        jr z,tm2
        ld hl,rdiv
        cp '/'
        ret nz
tm2:    push hl
        call next
        ld hl,factor
        call pushop
        pop hl
        call emcall
        jr tm1

factor: ld a,(TOK)
        cp TNUM
        jr nz,fa1
        ld hl,(TOKV)
        ld a,21h            ; LD HL,n
fa0:    call emit3
        jp next
fa1:    cp TNAME
        jr nz,fa3
        call lookup
        ex de,hl
        ld b,21h            ; a constant: LD HL,n
        or a
        jr z,fa2
        ld b,2Ah            ; a variable: LD HL,(v)
        dec a
        jp nz,ername
fa2:    ld a,b
        jr fa0
fa3:    cp KPEEK
        jr nz,fa4
        call next
        call factor
        ld hl,0026h         ; LD L,(HL) / LD H,0
        ld a,6Eh
        jp emit3
fa4:    cp KKEY
        ld hl,rkey
        ld a,0CDh           ; CALL rkey
        jr z,fa0
        call expect
        db '('
        call expr
        call expect
        db ')'
        ret

; ---------------------------------------------------------------- run time
; Called by the compiled code: values in HL, left operands in DE.

rprint: call prnum
        jp crlf


; DE compared with HL, by the byte after the CALL: Z if false.
rrel:   ex (sp),hl
        ld c,(hl)
        inc hl
        ex (sp),hl
        ex de,hl
        or a
        sbc hl,de
        ld a,2              ; 1 <, 2 =, 4 >
        jr z,rr1
        ld a,h              ; less if the sign is set, unless it overflowed
        jp po,rr0
        cpl
rr0:    rla
        ld a,1
        jr c,rr1
        ld a,4
rr1:    and c
        ret

; ---------------------------------------------------------------- arithmetic

; HL = DE * HL.
rmul:   ld b,h
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
        ret

; HL = DE / HL, signed, rounding towards zero.
rdiv:   ld a,h
        or l
        jp z,erdiv
        ld a,d
        xor h
        push af
        call abshl
        ex de,hl
        call abshl
        call udiv
        ld h,b
        ld l,c
        pop af
        ret p
        jp neghl

; BC = HL / DE, HL = remainder (unsigned; DE below 8001h).
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

; ---------------------------------------------------------------- KEY

; Wait about 8 ms and give the last key pressed in that time, or 0: the
; MM57109 puts out a number, a digit at a time, and each digit interrupts
; a HALT, so a key is taken there rather than resetting the COMP80.  The
; monitor's interrupt handler puts each digit at (HL), and its NMI handler
; puts the key at (DE): both go in KEYBUF.  The OUT is finished by the NOP
; that starts the next KEY, so RS in the middle of one does no harm.
rkey:   push de             ; keeps DE: the code for X + KEY takes KEY as
        ld a,3Fh            ; one load.  3Fh is a NOP, or the second word an
        call mmcmd          ; OUT waits for
        ld a,16h            ; OUT
        call mmcmd
        im 1
        ld hl,KEYBUF
        ld d,h
        ld e,l
        ld c,0
rky1:   xor a
        ei
        halt
keyrt2: di
        or a
        jr z,rky2
        ld c,a
rky2:   ld a,l
        cp (KEYBUF+12) & 0FFh
        jr nz,rky1
        pop de
        ld l,c
        ld h,0
        ret

; Give the MM57109 the instruction in A, once it is ready.
mmcmd:  ld b,a
mm1:    in a,(3)
        and 20h
        jr nz,mm1
        ld a,b
        out (60h),a
        or 80h
        out (60h),a
        ret

part2_end:
        ds 0C00h-$,0FFh
