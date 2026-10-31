; COMP80 LISP
;
; A small LISP for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that
; held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS
; key enters it: the monitor's NMI handler jumps to 0800h.
;
; Objects are 16-bit words:
;   NIL          0
;   number n     2n+1 (odd), so -16384..16383
;   built-in     2k for built-in function k (below 100h)
;   symbol       address of its record in 0C20h-0EFFh: value (2), length
;                (1), name; records start on even addresses
;   cell         address of a 4-byte cell, car then cdr, in the heap
;                (1000h up, or 8800h up with the 32 KB expansion)
; so anything from 1000h up that is even is a cell.
;
; Variables are dynamically scoped with shallow binding: a symbol's value is
; in its record, and calling a LAMBDA saves the old values of its parameters
; on the binding stack and puts them back when it returns, or when an error
; unwinds.  The binding stack grows up from the end of the mark bitmap
; (BMEND) and the Z80 stack down from STOP towards it.
;
; Garbage collection is mark and sweep, with a mark bitmap.  The roots are
; the symbol table, the binding stack and the Z80 stack, which is scanned
; conservatively: any word on it that could be a cell is taken as one.  So
; code only has to keep what it still needs on the stack when it conses.
; Free cells have UNB in their car and are chained through their cdr.
;
; Text is kept in ASCII (20h-5Fh) and converted to the display's 6-bit codes
; on output.  Keys and the screen work as in COMP80 FORTH (forth/forth.asm):
; RS while waiting for a key is rubout, any key while a program runs resets
; to the monitor, and RS from there comes back to LISP with everything kept.

MAGIC:  equ 0C00h           ; MAGICV when the RAM below holds a LISP world
SYMEND: equ 0C02h           ; end of the symbol table
FREE:   equ 0C04h           ; free list
HEAP:   equ 0C06h           ; first cell        } set at cold start
HSIZE:  equ 0C08h           ; heap size, bytes  } from MEM16 or MEM48
BMAP:   equ 0C0Ah           ; mark bitmap       }
BMEND:  equ 0C0Ch           ; end of the bitmap }
BSP:    equ 0C0Eh           ; binding stack pointer
NFREE:  equ 0C10h           ; free cells after the last collection
CURS:   equ 0C12h           ; output position in screen memory
TOIN:   equ 0C14h           ; byte: read offset into TIB
NTIB:   equ 0C15h           ; byte: characters in TIB
SYMS:   equ 0C20h           ; symbol table, up to SYMTOP
SYMTOP: equ 0F00h
TIB:    equ 0F00h           ; input line (80 bytes; page aligned)
WBUF:   equ 0F50h           ; atom being read, counted
STOP:   equ 1F00h           ; Z80 stack grows down from here (monitor uses 1Fxx)
MARGIN: equ 80              ; room kept between the two stacks
MAGICV: equ 0D15Ah
UNB:    equ 0FEh            ; value of an unbound symbol; car of a free cell

NILSYM: equ SYMS            ; the first four symbol records (see NAMES)
TSYM:   equ SYMS+6
QUOSYM: equ SYMS+10
LAMSYM: equ SYMS+18
FSLIM:  equ 18              ; built-ins below this are special forms

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

        org 0400h

; ---------------------------------------------------------------- cells

; HL = car or cdr of HL; NIL gives NIL.  Changes A.
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

; HL = car, DE = cdr of the cell HL; Z if the cdr is NIL.  Changes A.
uncons: ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        or h
        ex de,hl
        ret

; NC if HL is a cell, C if an atom.  Changes A.
consq:  ld a,h
        cp 10h
        ret c
        ld a,l
        rra
        ret

; HL = a new cell (DE . HL), collecting garbage if there are none free.
; Changes A, BC, DE.
cons:   push de
        push hl
        ld hl,(FREE)
        ld a,h
        or l
        jr nz,cn1
        call gc
        ld hl,(FREE)
        ld a,h
        or l
        jp z,nomem
cn1:    ld b,h
        ld c,l
        pop de
        inc hl
        inc hl
        ld a,(hl)
        ld (hl),e
        ld e,a
        inc hl
        ld a,(hl)
        ld (hl),d
        ld d,a
        ld (FREE),de
        pop de
        ld h,b
        ld l,c
        ld (hl),e
        inc hl
        ld (hl),d
        dec hl
        ret

; ---------------------------------------------------------------- eval

; HL = the value of HL.
eval:   push hl
        ld hl,(BSP)
        ld de,MARGIN
        add hl,de
        sbc hl,sp           ; C: the stacks are still MARGIN apart
        pop hl
        jp nc,deep
        call consq
        jr nc,evcons
        bit 0,l
        ret nz              ; number
        ld a,h
        cp SYMS/256
        ret c               ; NIL or a built-in
        ld e,(hl)           ; symbol: its value
        inc hl
        ld d,(hl)
        dec hl
        ld a,e
        xor UNB
        or d
        ex de,hl
        ret nz
        ex de,hl
        call erro
        db "UNBOUND ",0
evcons: call uncons
        push de             ; the arguments
        call eval           ; the function
        pop de

; Apply function HL to the arguments DE, not yet evaluated.
apply:  ld a,h
        or a
        jr nz,aplam
        or l
        jr z,badfn          ; NIL
        rra
        jr c,badfn          ; a number
        ld c,l
        ld b,h
        ld hl,subtab-4
        add hl,bc
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        push hl             ; the code: RET goes there
        ld a,c
        cp FSLIM
        ex de,hl
        ret c               ; special form: HL = the arguments as they are
        call evlis
        ld b,h              ; BC = the argument list
        ld c,l
        push hl
        call cdr
        call car
        ex de,hl            ; DE = the second argument
        pop hl
        jp car              ; HL = the first

; (LAMBDA params . body): bind the parameters to the values of the
; arguments, evaluate the body, and put the old values back.
aplam:  call consq
        jr c,badfn
        push hl
        call car
        ld bc,LAMSYM
        or a
        sbc hl,bc
        pop hl
        jr nz,badfn
        push hl
        ex de,hl
        call evlis
        ex de,hl            ; DE = the values
        pop hl
        call cdr            ; HL = (params . body)
        ld bc,(BSP)
        push bc
        push hl
        call car
        call bind
        pop hl
        call cdr
        call progn
        pop de
        jp unbind

badfn:  call erro
        db "BAD FN ",0

; HL = a new list of the values of the list HL.
evlis:  ld a,h
        or l
        ret z
        call uncons
        push de
        call eval
        ex (sp),hl
        call evlis
        pop de
        jp cons

; Evaluate each of the list HL; HL = the last value (NIL if none).
progn:  ld a,h
        or l
        ret z
pg1:    call uncons
        jp z,eval           ; the last one
        push de
        call eval
        pop hl
        jr pg1

; Bind each symbol in the list HL to the next of the list DE (NIL when that
; runs out).
bind:   ld a,h
        or l
        ret z
        push de
        call uncons         ; HL = symbol, DE = the rest
        call symchk
        ld b,h
        ld c,l
        pop hl
        push de
        push hl
        call cdr
        ex (sp),hl
        call car
        ex de,hl            ; DE = value, BC = symbol
        ld hl,(BSP)         ; push symbol and old value
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        ld a,(bc)
        ld (hl),a
        inc hl
        ld a,e
        ld (bc),a
        inc bc
        ld a,(bc)
        ld (hl),a
        inc hl
        ld a,d
        ld (bc),a
        ld (BSP),hl
        pop de
        pop hl
        jr bind

; Pop the binding stack down to DE, putting old values back.  Keeps HL.
unbind: push hl
ub1:    ld hl,(BSP)
        or a
        sbc hl,de
        jr z,ub9
        add hl,de
        dec hl
        ld b,(hl)
        dec hl
        ld c,(hl)           ; BC = old value
        dec hl
        ld a,(hl)
        dec hl
        ld (BSP),hl
        ld l,(hl)
        ld h,a
        ld (hl),c
        inc hl
        ld (hl),b
        jr ub1
ub9:    pop hl
        ret

; Error unless HL is a symbol.
symchk: bit 0,l
        jr nz,sc9
        ld a,h
        cp SYMS/256
        jr c,sc9
        cp SYMTOP/256
        ret c
sc9:    call erro
        db "BAD ARG ",0

; ---------------------------------------------------------------- special forms
; Entered with HL = the arguments, unevaluated.

; (COND (test e...)...)
cond:   ld a,h
        or l
        ret z
        call uncons
        push de             ; the other clauses
        push hl             ; this one
        call car
        call eval
        pop de
        ld a,h
        or l
        pop bc
        jr nz,cd1
        ld h,b
        ld l,c
        jr cond
cd1:    ex de,hl
        call cdr
        jp progn

; (DEFUN name params e...) sets name to (LAMBDA params e...).
defun:  call uncons
        call symchk
        push hl
        ex de,hl
        ld de,LAMSYM
        call cons
        ex de,hl
        pop hl
        push hl
        call set
        pop hl              ; the value of DEFUN is the name
        ret

; (SETQ symbol e)
setq:   call uncons
        call symchk
        push hl
        ex de,hl
        call car
        call eval
        ex de,hl
        pop hl
set:    ld (hl),e
        inc hl
        ld (hl),d
        dec hl
        ex de,hl
        ret

; (AND e...) and (OR e...)
fand:   ld a,h
        or l
        jp z,rett
an1:    call uncons
        jp z,eval
        push de
        call eval
        pop de
        ld a,h
        or l
        ret z
        ex de,hl
        jr an1

for:    ld a,h
        or l
        ret z
        call uncons
        jp z,eval
        push de
        call eval
        pop de
        ld a,h
        or l
        ret nz
        ex de,hl
        jr for

; ---------------------------------------------------------------- tables

; Names of the built-ins, in order: NIL is 0, T is 1 (its value is T), then
; the special forms (below FSLIM/2), then the functions.  The first four
; give the addresses NILSYM, TSYM, QUOSYM and LAMSYM.
names:  db 3,"NIL",1,"T",5,"QUOTE",6,"LAMBDA"
        db 4,"COND",5,"DEFUN",4,"SETQ",3,"AND",2,"OR"
        db 3,"CAR",3,"CDR",4,"CONS",4,"ATOM",2,"EQ",4,"NULL"
        db 4,"LIST",7,"NUMBERP",4,"CADR",5,"CADDR"
        db 1,"+",1,"-",1,"*",1,"/",3,"REM",1,"<",1,">"
        db 5,"PRINT",5,"PRIN1",6,"TERPRI",3,"TYO",4,"EVAL",2,"GC",0

; Their code, from QUOTE on.
subtab: dw car,lambda,cond,defun,setq,fand,for
        dw xcar,xcdr,xcons,atom,eq,null
        dw list,nump,cadr,caddr
        dw plus,minus,times,divi,remi,lt,gt
        dw xprint,prin1,terpri,tyo,eval,xgc

        ds 06B4h-$,0FFh
; Life (life/life.asm) uses these two ROM words as return addresses: SP
; points just above them while it runs.  They were here in the BURP ROM.
        dw 127Eh,1013h

; ---------------------------------------------------------------- built-ins
; Entered with HL = the first argument, DE = the second, BC = the list of
; them all.  Return the value in HL.

xcar:   call lstchk
        jp car
xcdr:   call lstchk
        jp cdr
cadr:   call xcdr
        jr xcar
caddr:  call xcdr
        jr cadr

lstchk: call consq
        ret nc
        ld a,h
        or l
        ret z
        jp sc9

xcons:  ex de,hl
        jp cons

atom:   call consq
        jr retc

nump:   ld a,l
        rra
        jr retc

eq:     or a
        sbc hl,de
        jr retz

null:   ld a,h
        or l
retz:   jr nz,nil
rett:   ld hl,TSYM
        ret
retc:   jr c,rett
nil:    ld hl,0
        ret

list:   ld h,b
        ld l,c
        ret

numchk: bit 0,l
        jr z,nn9
        bit 0,e
        ret nz
        ex de,hl
nn9:    jp sc9

plus:   call numchk
        add hl,de
        dec hl
        ret

minus:  call numchk
        or a
        sbc hl,de
        inc hl
        ret

times:  call numchk
        sra h
        rr l
        dec de
        call mul16
        inc hl
        ret

remi:   call divi
        ex de,hl
        jr enc

divi:   call numchk
        call dec2
        call sdiv           ; DE = the remainder, for REM
enc:    add hl,hl
        inc hl
        ret

dec2:   sra h
        rr l
        sra d
        rr e
        ret

lt:     call numchk
lt1:    call scmp
        jr retc

gt:     call numchk
        ex de,hl
        jr lt1

xprint: call prin1
        jp crlf

prin1:  push hl
        call print
        pop hl
        ret

terpri: call crlf
        jr nil

tyo:    push hl
        sra h
        rr l
        ld a,l
        call emitc
        pop hl
        ret

xgc:    call gc
        ld hl,(NFREE)
        jp enc

; ---------------------------------------------------------------- arithmetic

; CY = HL < DE, signed.  Changes HL, DE, A.
scmp:   ld a,h
        xor 80h
        ld h,a
        ld a,d
        xor 80h
        ld d,a
        sbc hl,de
        ret

neghl:  xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; HL = HL * DE.  Keeps BC, DE.
mul16:  push bc
        ld b,h
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
        pop bc
        ret

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

; HL = HL / DE, DE = remainder, signed, rounding towards zero.
sdiv:   ld a,h
        xor d
        push af             ; sign of the quotient
        ld a,h
        push af             ; sign of the remainder
        or a
        call m,neghl
        ex de,hl
        bit 7,h
        call nz,neghl
        ex de,hl
        call udiv
        pop af
        or a
        call m,neghl
        ex de,hl
        ld h,b
        ld l,c
        pop af
        or a
        jp m,neghl
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

; Print the string at HL, up to a 0 byte.
prs:    ld a,(hl)
        inc hl
        or a
        ret z
        call putc
        jr prs

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If LISP was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) LISP.

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
        ld hl,mem16
        jr z,wm1
        ld hl,mem48
wm1:    ld de,HEAP
        ld bc,8
        ldir
        ld hl,names         ; the symbol table: the built-ins, with
        ld de,SYMS          ; built-in k as the value of symbol k
cs1:    ld a,(hl)
        or a
        jr z,cs9
        ex de,hl
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        ex de,hl
        ld b,a
        inc b
cs2:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz cs2
        inc de
        res 0,e
        inc c
        inc c
        jr cs1
cs9:    ld (SYMEND),de
        ld hl,TSYM          ; T is T
        ld (TSYM),hl
        ld hl,(BMEND)
        ld (BSP),hl
        ld hl,MAGICV
        ld (MAGIC),hl
wm2:    call gc
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " LISP",0
        call crlf
        call cls
        jr wm3

; Print the message after the CALL and the object HL, and start again.
erro:   ex (sp),hl
        call prs
        pop hl
        call print
abort:  call crlf
wm3:    ld sp,STOP
        ld de,(BMEND)       ; undo the bindings of whatever was running
        call unbind
        ld a,(NTIB)         ; forget the rest of the line
        ld (TOIN),a

repl:   call read
        call eval
        call xprint
        jr repl

deep:   call prsi
        db "TOO DEEP",0
        jr abort
nomem:  call prsi
        db "NO MEM",0
        jr abort

;               HEAP   HSIZE  BMAP   BMEND
mem16:  dw      1000h, 0A80h, 1A80h, 1AD4h
mem48:  dw      8800h, 7800h, 1000h, 13C0h

; ---------------------------------------------------------------- reader

; Special form (LAMBDA ...) is its own value.
lambda: ld de,LAMSYM
        jp cons

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

; Skip spaces and ; comments.  A = the next character, not taken.
skipws: call peekc
        cp ' '
        jr z,sk1
        cp ';'
        ret nz
        ld a,(NTIB)
        ld (TOIN),a
        jr skipws
sk1:    call getc
        jr skipws

; HL = the next object read.
read:   call skipws
        cp '('
        jr z,rlist
        cp 27h
        jr nz,ratom
        call getc           ; 'x is (QUOTE x)
        call read
        ex de,hl
        ld hl,0
        call cons
        ld de,QUOSYM
        jp cons

rlist:  call getc
        ld hl,0
        ld d,h
        ld e,l
        call cons           ; a dummy cell in front of the list
        push hl
        push hl             ; the last cell
rl1:    call skipws
        cp ')'
        jr z,rl9
        call read
        ex de,hl
        ld hl,0
        call cons
        ex de,hl
        pop hl
        inc hl
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        push de
        jr rl1
rl9:    call getc
        pop hl
        pop hl
        jp cdr

; An atom: the character A, and those after it up to a space, ( ) ' ; or
; anything else below *.
ratom:  ld de,WBUF+1
ra1:    ld (de),a
        inc de
        ld hl,TOIN
        inc (hl)
        call peekc
        cp ';'
        jr z,ra2
        cp '*'
        jr nc,ra1
ra2:    ld a,e
        sub (WBUF+1)&0FFh
        ld (WBUF),a

; WBUF as a number: optional -, then digits.
number: ld hl,WBUF
        ld b,(hl)
        inc hl
        ld a,(hl)
        cp '-'
        push af             ; Z: negative
        jr nz,nu1
        dec b
        jr z,nu9
        inc hl
nu1:    ld de,0
nu2:    ld a,(hl)
        sub '0'
        cp 10
        jr nc,nu9
        push hl
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
        pop hl
        inc hl
        djnz nu2
        pop af
        ex de,hl
        call z,neghl
        jp enc
nu9:    pop af

; WBUF as a symbol, made if it is new.  NIL is read as 0.
intern: ld hl,SYMS
in1:    ld de,(SYMEND)
        or a
        sbc hl,de
        add hl,de
        jr z,in5
        push hl
        inc hl
        inc hl
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
        pop hl              ; found
        ld de,NILSYM
        or a
        sbc hl,de
        ret z
        add hl,de
        ret
in3:    pop hl
        inc hl
        inc hl
        ld e,(hl)
        ld d,0
        add hl,de
        inc hl
        inc hl
        res 0,l
        jr in1
in5:    ld a,(WBUF)         ; new: is there room?
        add a,4
        add a,l
        ld a,h
        adc a,0
        cp SYMTOP/256
        jp nc,nomem
        push hl
        ld (hl),UNB
        inc hl
        ld (hl),0
        inc hl
        ex de,hl
        ld hl,WBUF
        ld c,(hl)
        ld b,0
        inc bc
        ldir
        ex de,hl
        inc hl
        res 0,l
        ld (SYMEND),hl
        pop hl
        ret

; ---------------------------------------------------------------- printer

print:  bit 0,l
        jp nz,prnum
        ld a,h
        or l
        jr nz,pr1
        ld hl,NILSYM
pr1:    ld a,h
        cp 10h
        jr nc,prlist
        cp SYMS/256
        jr c,prsub
        inc hl
        inc hl
        ld b,(hl)
        inc hl
        jp typen
prsub:  call prsi
        db "SUBR",0
        ret
prlist: ld a,'('
pl1:    call putc
        push hl
        call car
        call print
        pop hl
        call cdr
        ld a,h
        or l
        jr z,pl9
        call consq
        ld a,' '
        jr nc,pl1
        call prsi
        db " . ",0
        call print
pl9:    ld a,')'
        jp putc

; ---------------------------------------------------------------- garbage

; Collect garbage: mark what the roots reach, then make a new free list of
; the rest.  NFREE = how many cells are free.  Keeps nothing.
gc:     ld hl,(BMAP)
        ld de,(BMEND)
gc1:    ld (hl),0
        inc hl
        or a
        sbc hl,de
        add hl,de
        jr nz,gc1
        ld hl,SYMS
        ld de,(SYMEND)
        call mrange
        ld hl,(BMEND)
        ld de,(BSP)
        call mrange
        ld hl,0
        add hl,sp
        ld de,STOP
        call mrange
        ld hl,0
        ld (FREE),hl
        ld (NFREE),hl
        ld hl,(HEAP)
        ld de,(BMAP)
sw1:    ld a,(de)
        ld c,a
        ld b,8
sw2:    srl c
        jr c,sw3
        push de
        ld de,(FREE)
        ld (FREE),hl
        ld (hl),UNB
        inc hl
        ld (hl),0
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        dec hl
        dec hl
        dec hl
        ld de,(NFREE)
        inc de
        ld (NFREE),de
        pop de
sw3:    inc hl
        inc hl
        inc hl
        inc hl
        djnz sw2
        inc de
        push hl
        ld hl,(BMEND)
        or a
        sbc hl,de
        pop hl
        jr nz,sw1
        ret

; Mark from each word from HL up to DE.
mrange: or a
        sbc hl,de
        add hl,de
        ret nc
        push de
        push hl
        call car1
        call mark
        pop hl
        inc hl
        inc hl
        pop de
        jr mrange

; Mark HL if it is a cell, and what it points to.
mark:   ld a,l
        and 3
        ret nz
        push hl
        ld de,(HEAP)
        or a
        sbc hl,de
        jr c,mk9
        ld de,(HSIZE)
        sbc hl,de
        add hl,de
        jr nc,mk9           ; not in the heap
        ex (sp),hl
        ld a,(hl)
        cp UNB
        jr nz,mk1
        inc hl
        ld a,(hl)
        dec hl
        or a
        jr z,mk9            ; a free cell
mk1:    ex (sp),hl          ; HL = offset in the heap
        ld a,l
        rrca
        rrca
        and 7
        inc a
        ld b,a
        ld a,80h
mk2:    rlca
        djnz mk2
        ld c,a              ; C = its bit
        ld b,5
mk3:    srl h
        rr l
        djnz mk3
        ld de,(BMAP)
        add hl,de
        ld a,(hl)
        and c
        jr nz,mk9           ; marked already
        ld a,(hl)
        or c
        ld (hl),a
        pop hl
        call uncons
        push de
        call mark           ; the car
        pop hl
        jr mark             ; the cdr
mk9:    pop hl
        ret

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
        jp crlf

; Print character A.  ASCII 40h-7Fh go to the display's 5-bit codes;
; 80h-0FFh print graphics character A-80h; 0Dh is a new line.  Keeps
; everything but AF.
emitc:  cp 0Dh
        jr z,crlf
putc:   push hl
        cp 80h
        jr c,pc1
        sub 40h
        jr pc2
pc1:    cp 40h
        jr c,pc2
        and 1Fh
pc2:    ld hl,(CURS)
        ld (hl),a
        inc hl
        call fixcur
        pop hl
        ret

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

cls:    ld hl,VRAM+40h
        ld (CURS),hl
        jp CLS64

; Print the string after the CALL, up to a 0 byte.  Keeps HL.
prsi:   ex (sp),hl
        call prs
        ex (sp),hl
        ret

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
