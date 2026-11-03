; COMP80 FOCAL
;
; FOCAL, DEC's 1968 interactive language, for the PSI COMP80, in the 2 KB
; of ROM (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh) is
; unchanged.  As with BURP, the RS key enters it: the monitor's NMI handler
; jumps to 0800h.
;
; Numbers are floating point, 8 digits, done by the MM57109 calculator chip
; as in BURP.  An expression is worked out by sending it to the chip as it
; is parsed: each number or variable is keyed into the chip, which pushes
; its stack, and each operator is sent after its right-hand side.  The chip
; stack holds four numbers, so an expression can have at most four values
; waiting at once (2+3*(4-5/6) is fine; deeper nesting loses the oldest).
; A variable keeps the 12 digits the chip's OUT instruction gives (exponent,
; signs, mantissa) and is keyed back in digit by digit.
;
; Commands are known by their first letter, as in FOCAL:
;   TYPE  ASK  SET  IF  GOTO  DO  RETURN  FOR  COMMENT  QUIT  WRITE  ERASE
; Functions: FSQT FABS FSIN FCOS FATN FEXP FLOG FITR FRAN.
;
; A program line is stored as its number (step, group: so the word is
; group*256 + step) followed by its text and a 0.  Lines go up from PROG;
; variables (2 bytes of name, 12 of digits) go down from VTOP.
;
; Keys.  As in FORTH: RS while waiting for a key is rubout; any key while a
; program runs makes the monitor's NMI handler reset to the monitor, and RS
; then comes back to FOCAL with the program kept.  FS goes to the monitor.

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
PEND:   equ 0C02h           ; end of the program
VBOT:   equ 0C04h           ; lowest variable
SEED:   equ 0C06h           ; FRAN
CURS:   equ 0C08h           ; output position in screen memory
CUR:    equ 0C0Ah           ; line running (0 in direct mode)
JUMP:   equ 0C0Ch           ; line to go to
FLOW:   equ 0C0Eh           ; byte: 0 go on, 1 GOTO (JUMP), 2 RETURN
ASKF:   equ 0C0Fh           ; byte: 1 in ASK, 0 in TYPE
FV:     equ 0C10h           ; the FOR running: its variable,
FS:     equ 0C12h           ; the text of its step (0: 1),
FE:     equ 0C14h           ; of its end,
FB:     equ 0C16h           ; and of the rest of the line
PROG:   equ 0C18h
VTOP:   equ 1C00h           ; variables grow down from here
TIB:    equ 1C00h           ; command line
NBUF:   equ 1C60h           ; 12 digits from the chip
ABUF:   equ 1C80h           ; ASK's input line
STK:    equ 1F00h           ; the monitor uses 1Fxx
MAGICV: equ 0F0CAh

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

        org 0400h

; ---------------------------------------------------------------- the chip
; Send instruction A to the MM57109, as BURP does: wait until it is ready,
; put the instruction on its lines, wait until it takes it, then set HOLD so
; it stops after it.  Keeps everything but AF.
mmsend: push bc
        ld b,a
ms1:    in a,(3)
        and 20h
        jr nz,ms1
        ld a,b
        out (60h),a
ms2:    in a,(3)
        and 20h
        jr z,ms2
        ld a,b
        or 80h
        out (60h),a
        pop bc
        ret

; Send the byte after the CALL to the chip.
mmi:    ex (sp),hl
        ld a,(hl)
        inc hl
        ex (sp),hl
        jr mmsend

; Send test instruction A (TX=0 11h, TXLT0 12h).  Z if the test is true.
; A true test pulses BR and waits for a second word: send it a NOP.
mmtest: push bc
        call mmsend
mt1:    in a,(3)
        ld b,a
        and 60h
        jp pe,mt1           ; still running (or both lines low)
        cp 30h
        jr nc,mt2
        ld a,3Fh
        out (60h),a
mt2:    in a,(3)
        and 20h
        jr nz,mt2
        ld a,b
        and 40h
        pop bc
        ret

; OUT: the 12 digits of X to (HL): exponent tens and units, signs (8 the
; mantissa's, 1 the exponent's), 0Bh, then 8 mantissa digits.  Each digit
; comes with an interrupt, which the monitor's IM 1 handler at 0038h stores
; at (HL)+.  Keeps HL.
mmout:  push hl
        ei                  ; (HL mustn't change till DI)
        ld a,16h
        call mmsend
        ld a,2Bh            ; the second word, ignored
        call mmsend
        di
        pop hl
        ret

; Key the number at IX (12 digits as from OUT) into the chip, B mantissa
; digits of it (mmldb), 8 (mmload).  Keeps HL.
mmload: ld b,8
mmldb:  ld a,(ix+4)
        or a
        jr z,push0
        push hl
        push ix
        pop hl
        ld de,4
        add hl,de
        call lastnz
        ld b,d
        ld a,(hl)
        inc hl
        call mmsend
        call mmi            ; DP after the first digit
        db 0Ah
        jr ml2
ml1:    ld a,(hl)
        inc hl
        call mmsend
ml2:    djnz ml1
        bit 3,(ix+2)
        ld a,0Ch            ; CS
        call nz,mmsend
        call gete
        or a
        jr z,ml3
        call mmi            ; EE
        db 0Bh
        ld a,(ix+0)
        or a
        call nz,mmsend
        ld a,(ix+1)
        call mmsend
        bit 0,(ix+2)
        ld a,0Ch
        call nz,mmsend
ml3:    pop hl
        jr endnum
push0:  xor a
        call mmsend
endnum: ld a,3Fh            ; a NOP ends number entry
        jp mmsend

; D = how many of the B digits at HL to keep: up to the last that isn't 0.
; Keeps HL.
lastnz: push hl
        ld c,0
        ld d,c
lz1:    inc c
        ld a,(hl)
        inc hl
        or a
        jr z,lz2
        ld d,c
lz2:    djnz lz1
        pop hl
        ret

; A = the exponent at IX, without its sign.
gete:   ld a,(ix+0)
        add a,a
        ld c,a
        add a,a
        add a,a
        add a,c
        add a,(ix+1)
        ret

; X to the variable at IX.  Keeps HL, IX.
store:  push hl
        push ix
        pop hl
        call mmout
        pop hl
        ret

; Key in the number at HL (digits and a point; A is the first), moving HL
; past it.
literal: sub '0'
        jr nc,li2
        ld a,0Ah            ; the point
li2:    call mmsend
        inc hl
        ld a,(hl)
        call isnum
        jr c,literal
        jr endnum

; ---------------------------------------------------------------- expressions
; Work out the expression at HL, leaving it in the chip's X.
expr:   call skipsp
        cp '-'
        jr nz,ex1
        inc hl
        call term
        call mmi            ; CS: change sign
        db 0Ch
        jr ex2
ex1:    call term
ex2:    ld bc,2B39h         ; + is 39h,
        ld de,2D3Ah         ; - is 3Ah
        call ops
        ret nz
        push af
        call term
        pop af
        call mmsend
        jr ex2

term:   call factor
te1:    ld bc,2A3Bh         ; * is 3Bh,
        ld de,2F3Ch         ; / is 3Ch
        call ops
        ret nz
        push af
        call factor
        pop af
        call mmsend
        jr te1

; If the next character is B or D, move past it with Z and A = C or E.
ops:    call skipsp
        cp b
        jr z,op1
        cp d
        ret nz
        ld c,e
op1:    inc hl
        ld a,c
        cp a
        ret

; X ** Y is X to the power Y (^ is the RS key, so it can't be typed).
factor: call prim
        call skipsp
        cp '*'
        ret nz
        inc hl
        ld a,(hl)
        cp '*'
        jr z,fa1
        dec hl
        ret
fa1:    inc hl
        call factor
        ld a,38h            ; Y to the power X
        jp mmsend

prim:   call skipsp
        cp '('
        jr nz,pr1
        inc hl
        call expr
close:  call skipsp
        cp ')'
        jp nz,err
        inc hl
        ret
pr1:    call isnum
        jp c,literal
        cp 'F'
        jr z,func
        call letvar
        jp mmload

; A function: F and two letters name it, then (expression).
func:   inc hl
        ld d,(hl)
        inc hl
        ld e,(hl)
        call skipal
        push hl
        ld hl,ftab
fu1:    ld a,(hl)
        or a
        jp z,err
        inc hl
        cp d
        jr nz,fu2
        ld a,(hl)
        cp e
        jr z,fu3
fu2:    inc hl
        inc hl
        jr fu1
fu3:    inc hl
        ld c,(hl)
        pop hl
        ld a,(hl)
        cp '('
        jp nz,err
        inc hl
        ld a,c
        or a
        jr z,fran
        push bc
        call expr
        call close
        pop bc
        ld a,c
        cp 1
        jr z,fabs
        cp 2
        jr z,fitr
        jp mmsend

; A = 0 if X < 0, 1 if X = 0, 2 if X > 0.
sign:   ld a,12h
        call mmtest
        ld a,0
        ret z
        ld a,11h
        call mmtest
        ld a,1
        ret z
        inc a
        ret

fabs:   ld a,12h            ; X < 0?
        call mmtest
        ret nz
        ld a,0Ch
        jp mmsend

; FITR: the integer part.  OUT, drop X and key it back in with only the
; digits in front of the point.
fitr:   push hl
        ld hl,NBUF
        call mmout
        pop hl
        ld ix,NBUF
        call mmi            ; POP
        db 2Eh
        bit 0,(ix+2)
        jp nz,push0         ; less than 1
        call gete
        inc a
        cp 9
        jr c,fi1
        ld a,8
fi1:    ld b,a
        jp mmldb

; FRAN(): a random number from 0 to 1, keyed in as a point and 8 digits.
fran:   call close
        call mmi
        db 0Ah
        ld b,8
fr2:    push hl
        ld hl,(SEED)        ; xorshift: x ^= x<<7, x ^= x>>9, x ^= x<<8
        ld a,h
        rra
        ld a,l
        rra
        xor h
        ld h,a
        ld a,l
        rra
        ld a,h
        rra
        xor l
        ld l,a
        xor h
        ld h,a
        ld (SEED),hl
        ld a,h              ; a digit: 4 bits, if under 10
        pop hl
        and 0Fh
        cp 10
        jr nc,fr2
        call mmsend
        djnz fr2
        jp endnum

ftab:   db "SQ",34h,"AB",1,"SI",24h,"CO",25h
        db "EX",31h,"LO",35h,"IT",2,"RA",0,0

; ---------------------------------------------------------------- variables
; IX = the value of the variable named at HL (a letter, then a letter or
; digit; more letters and digits are ignored), made 0 if it is new.
letvar: call skipsp
        call isalpha
        jp nc,err
        ld d,a
        inc hl
        ld e,0
        ld a,(hl)
        call isalnum
        jr nc,fv1
        ld e,a
fv0:    inc hl
        ld a,(hl)
        call isalnum
        jr c,fv0
fv1:    push hl
        ld hl,(VBOT)
fv2:    ld a,h
        cp 1Ch              ; VTOP
        jr z,fv4
        ld a,(hl)
        inc hl
        cp d
        jr nz,fv3
        ld a,(hl)
        cp e
        jr z,fv5
fv3:    ld bc,13
        add hl,bc
        jr fv2
fv4:    ld hl,(VBOT)        ; a new one
        ld bc,-14
        add hl,bc
        ld (VBOT),hl
        call atend
        jp c,err
        ld (hl),d
        inc hl
        ld (hl),e
        push hl
        ld b,12
fvz:    inc hl
        ld (hl),0
        djnz fvz
        pop hl
fv5:    inc hl
        push hl
        pop ix
        pop hl
        ret

; ---------------------------------------------------------------- characters
skipal: ld a,(hl)           ; skip letters, then spaces
        call isalpha
        jr nc,skipsp
        inc hl
        jr skipal

skipsp: ld a,(hl)           ; A = the next character that isn't a space
        cp ' '
        ret nz
        inc hl
        jr skipsp

isnum:  cp '.'              ; C if A is a digit or a point
        scf
        ret z
isdig:  cp '0'              ; C if A is a digit
        ccf
        ret nc
        cp '9'+1
        ret

isalnum: call isdig
        ret c
isalpha: cp 'A'             ; C if A is a letter
        ccf
        ret nc
        cp 'Z'+1
        ret

; A = the number at HL (0-255), moving HL past it.
getint: ld c,0
gi1:    ld a,(hl)
        call isdig
        jr nc,gi2
        sub '0'
        ld b,a
        ld a,c
        add a,a
        add a,a
        add a,c
        add a,a
        add a,b
        ld c,a
        inc hl
        jr gi1
gi2:    ld a,c
        ret

; DE = the line number at HL: D the group, E the step (1.1 is step 10).
; C if there is no point (a whole group).
lineno: call getint
        ld d,a
        ld e,0
        ld a,(hl)
        cp '.'
        scf
        ret nz
        inc hl
        ld a,(hl)
        call isdig
        jr nc,ln1
        sub '0'
        ld c,a
        add a,a
        add a,a
        add a,c
        add a,a
        ld e,a
        inc hl
        ld a,(hl)
        call isdig
        jr nc,ln1
        sub '0'
        add a,e
        ld e,a
        inc hl
ln1:    or a
        ret

; COMMENT: the rest of the line is ignored.
ccom:   ld a,(hl)
        or a
        ret z
        cp ';'
        ret z
        inc hl
        jr ccom

; FOR V=A,B,C; ...  The rest of the line runs with V = A, A+B, ... until
; V passes C.  FOR V=A,C counts in 1s.  B and C are worked out again each
; time round.  The FOR running is in FV-FB; an outer one's is kept on the
; stack meanwhile.
cfor:   call letvar
        push ix
        call skipsp
        cp '='
        jp nz,err
        inc hl
        call expr
        pop ix
        call store          ; V = A
        ex de,hl
        ld hl,-8
        add hl,sp
        ld sp,hl
        push de
        ex de,hl
        ld hl,FV
        ld bc,8
        ldir
        pop hl
        ld (FV),ix
        inc hl              ; the comma
        push hl
        call expr
        call skipsp
        pop de
        ld bc,0
        cp ','
        jr nz,fo1
        inc hl              ; three values: B then C
        push de
        push hl
        call expr
        pop de
        pop bc
fo1:    ld (FS),bc
        ld (FE),de
        ld (FB),hl
fo2:    ld hl,(FB)
        call stmts
        ld a,(FLOW)
        or a
        jr nz,fo9
        ld ix,(FV)          ; V = V + B
        call mmload
        call fstep
        call mmi
        db 39h
        ld ix,(FV)
        call store
        ld hl,(FE)          ; go on while (V - C) * B is not above 0
        call expr
        call mmi
        db 3Ah
        call fstep
        call mmi
        db 3Bh
        call sign
        cp 2
        jr c,fo2
fo9:    ld hl,0
        add hl,sp
        ld de,FV
        ld bc,8
        ldir
        ld sp,hl
        ld hl,null
        ret

fstep:  ld hl,(FS)
        ld a,h
        or l
        jp nz,expr
        ld a,1
        call mmsend
        jp endnum

; WRITE lists the program.
cwrite: ld hl,PROG
wr1:    call atend
        jr nc,wr9
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        call prline
        ld a,' '
wr2:    call putc
        ld a,(hl)
        inc hl
        or a
        jr nz,wr2
        call crlf
        jr wr1
wr9:    ld hl,null
        ret

; ERASE clears the variables, ERASE ALL the program too.
cerase: cp 'A'
        jr nz,er1
        ld hl,PROG
        ld (PEND),hl
er1:    ld hl,VTOP
        ld (VBOT),hl
        jp cmd

; Something is wrong: ? and the line, then back to the command line.
err:    ld a,'?'
        call putc
        ld hl,(CUR)
        ld a,h
        or l
        jp z,cmd
        ld e,(hl)
        inc hl
        ld d,(hl)
        call prline
        jp cmd

; Print line number DE as GG.SS.
prline: ld a,d
        call p2d
        call putci
        db '.'
        ld a,e
p2d:    ld c,'0'-1          ; print A (0-99) as two digits
p2a:    inc c
        sub 10
        jr nc,p2a
        push af
        ld a,c
        call putc
        pop af
        add a,10+'0'
        jp putc

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If FOCAL was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) FOCAL.

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

warm:   ld sp,STK
        im 1
        ld a,(MAGIC)
        cp MAGICV & 0FFh
        jr z,wm1
        ld hl,newprog       ; no program in RAM: start an empty one
        ld de,MAGIC
        ld bc,8
        ldir
wm1:    ld hl,mminit
        ld b,3              ; NOP (a second word, in case the chip
wm2:    ld a,(hl)           ; was left waiting for one), MCLR, TOGM:
        inc hl              ; scientific notation for OUT
        call mmsend
        djnz wm2
        ld hl,VRAM
        ld (CURS),hl
        ld hl,title
        call pstr
        call crlf
        ld hl,VRAM+40h
        ld (CURS),hl
        call CLS64
        jr cmd

title:  db " FOCAL",0

newprog: dw MAGICV,PROG,VTOP,1
mminit: db 3Fh,2Fh,22h

; ---------------------------------------------------------------- commands
; Read a line.  With a number in front it goes into the program (and a
; number alone deletes that line); otherwise it runs straight away.
cmd:    ld sp,STK
        ld hl,0
        ld (CUR),hl
        xor a
        ld (FLOW),a
        ld a,(CURS)         ; start a new line if need be
        and 3Fh
        call nz,crlf
        call putci
        db '*'
        ld de,TIB
        call accept
        ld hl,TIB
        call skipsp
        call isdig
        jr c,edit
        call stmts
        ld a,(FLOW)
        dec a
        jr nz,cmd
        ld (FLOW),a
        ld hl,(JUMP)
        ld bc,0
        call run
        jr cmd

edit:   call lineno         ; DE = line number
        call skipsp
        push hl             ; (text)
        call seek           ; HL = where it goes
        call z,delline
        pop bc
        ld a,(bc)
        or a
        jr z,cmd            ; a number alone: deleted
        push de             ; (number)
        push bc             ; (number, text)
        push hl             ; (number, text, place)
        ld h,b
        ld l,c
        ld bc,2
ed1:    inc bc              ; BC = 2 + length + 1
        ld a,(hl)
        inc hl
        or a
        jr nz,ed1
        ld hl,(PEND)
        push hl
        add hl,bc
        ex de,hl            ; DE = new end
        ld hl,(VBOT)
        or a
        sbc hl,de
        jp c,err
        pop hl              ; old end
        ld (PEND),de
        pop bc              ; place
        push bc
        push hl
        or a
        sbc hl,bc           ; bytes to move up
        ld b,h
        ld c,l
        pop hl
        ld a,b
        or c
        jr z,ed2
        dec hl
        dec de
        lddr
ed2:    pop hl              ; place
        pop de              ; text
        pop bc              ; number
        ld (hl),c
        inc hl
        ld (hl),b
ed3:    inc hl
        ld a,(de)
        inc de
        ld (hl),a
        or a
        jr nz,ed3
        jp cmd

; Take out the line at HL.  Keeps DE, HL.
delline: push de
        push hl
        ld d,h
        ld e,l
        call nextl          ; HL = the line after
        push hl
        push de
        ld de,(PEND)
        ex de,hl
        or a
        sbc hl,de           ; bytes after it
        ld b,h
        ld c,l
        pop de
        pop hl
        ld a,b
        or c
        jr z,dl1
        ldir
dl1:    ld (PEND),de
        pop hl
        pop de
        ret

; HL = the first line numbered DE or more (or PEND).  Z if it is DE.
; Keeps DE.
seek:   ld hl,PROG
sk1:    call atend
        jr nc,sk9
        ld a,(hl)
        inc hl
        ld b,(hl)
        dec hl
        push hl
        ld h,b
        ld l,a
        or a
        sbc hl,de
        pop hl
        ret nc
        call nextl
        jr sk1
sk9:    or 1
        ret

; NC if HL is at (or past) the end of the program.  Keeps DE, HL.
atend:  push de
        ld de,(PEND)
        or a
        sbc hl,de
        add hl,de
        pop de
        ret

nextl:  inc hl              ; HL = the line after the one at HL
        inc hl
nl1:    ld a,(hl)
        inc hl
        or a
        jr nz,nl1
        ret

; Run the program from the line at HL.  B = the group to keep to (0: any),
; C = 1 to run one line only.
run:    call atend
        ret nc
        ld a,b
        or a
        jr z,rn1
        inc hl
        ld a,(hl)
        dec hl
        cp b
        ret nz              ; out of the group
rn1:    ld (CUR),hl
        push bc
        push hl
        inc hl
        inc hl
        call stmts
        pop hl
        pop bc
        ld a,(FLOW)
        or a
        jr nz,rn2
        bit 0,c
        ret nz
        call nextl
        jr run
rn2:    dec a
        ret nz              ; RETURN
        ld (FLOW),a
        ld hl,(JUMP)
        ld c,a
        jr run

; Run the statements at HL until the end of the line, or until FLOW is set.
stmts:  call skipsp
        or a
        ret z
        inc hl
        cp ';'
        jr z,stmts
        ld de,ctab
        ld b,a
st1:    ld a,(de)
        or a
        jp z,err
        inc de
        cp b
        jr z,st2
        inc de
        inc de
        jr st1
st2:    ld a,(de)
        ld c,a
        inc de
        ld a,(de)
        ld b,a
        call skipal
        call callbc
        ld a,(FLOW)
        or a
        ret nz
        jr stmts
callbc: push bc
        ret

ctab:   db 'T'
        dw ctype
        db 'S'
        dw cset
        db 'I'
        dw cif
        db 'G'
        dw cgoto
        db 'D'
        dw cdo
        db 'F'
        dw cfor
        db 'A'
        dw cask
        db 'R'
        dw cret
        db 'C'
        dw ccom
        db 'Q'
        dw cmd
        db 'W'
        dw cwrite
        db 'E'
        dw cerase
        db 0

; SET V=E
cset:   call letvar
        push ix
        call skipsp
        cp '='
        jp nz,err
        inc hl
        call expr
        pop ix
        jp store

; TYPE "TEXT", !, E, ...  and  ASK "TEXT", V, ...: for ASK each variable
; gets a number typed after a colon.
cask:   ld a,1
        jr ty0
ctype:  xor a
ty0:    ld (ASKF),a
ty1:    call skipsp
        or a
        ret z
        cp ';'
        ret z
        inc hl
        cp ','
        jr z,ty1
        cp '!'
        jr nz,ty2
        call crlf
        jr ty1
ty2:    cp '"'
        jr nz,ty3
        call pstr
        jr ty1
ty3:    dec hl
        ld a,(ASKF)
        or a
        jr nz,ty4
        call expr
        call prnum
        jr ty1
ty4:    call letvar
        push hl
        push ix
        call putci
        db ':'
        ld de,ABUF
        call accept
        ld hl,ABUF
        call expr           ; the answer can be any expression
        pop ix
        call store
        pop hl
        jr ty1

; Print up to the closing quote (or a 0).
pstr:   ld a,(hl)
        or a
        ret z
        inc hl
        cp '"'
        ret z
        call putc
        jr pstr

; IF (E) L1,L2,L3: to L1 if E < 0, L2 if 0, L3 if more.  If that line
; number isn't there, go on with the line.
cif:    call expr
        call sign
        ld b,a
if1:    call skipsp
        call isdig
        jr nc,if4
        ld a,b
        or a
        jr z,cgoto
if2:    ld a,(hl)           ; not this one
        call isnum
        jr nc,if3
        inc hl
        jr if2
if3:    call skipsp
if4:    cp ','
        jp nz,ccom
        inc hl
        dec b
        jr if1

; GOTO L (GO alone: from the start)
cgoto:  call skipsp
        ld de,PROG
        call isdig
        jr nc,go1
        call lineno
        call seek
        jp nz,err
        ex de,hl
go1:    ld (JUMP),de
        ld a,1
go2:    ld (FLOW),a
        ret

; RETURN from DO
cret:   ld a,2
        jr go2

; DO G.S runs that line, DO G the whole group, then comes back.
cdo:    call skipsp
        call lineno
        push hl
        ld bc,1
        jr nc,do1
        ld e,0
        ld b,d
        dec c
do1:    push bc
        call seek
        pop bc
        jr z,do2
        ld a,b              ; a missing line is an error, a group needn't be
        or a
        jp z,err
do2:    ld de,(CUR)
        push de
        call run
        pop de
        ld (CUR),de
        ld a,(FLOW)
        cp 2
        jr nz,do3
        xor a
        ld (FLOW),a
do3:    pop hl
        ret

; ---------------------------------------------------------------- numbers
; Print X: a space or -, then 12, 0.5, 3.1415927 or 1.5E-7.
prnum:  push hl
        ld hl,NBUF
        call mmout
        ld ix,NBUF
        ld a,' '
        bit 3,(ix+2)
        jr z,pn1
        ld a,'-'
pn1:    call putc
        call gete           ; (0 comes out as 0 here)
        ld c,a
        bit 0,(ix+2)
        jr nz,pn4
        cp 8
        jr nc,pn6
        inc a               ; 1 to 99999999: the point after e+1 digits
        ld b,a
        jr pn8
pn4:    cp 4
        jr nc,pn6
        call putci            ; 0.1 to 0.001: 0. and the zeros first
        db '0'
        ld a,'.'
pn5:    call putc
        ld a,'0'
        dec c
        jr nz,pn5
        ld b,c
        jr pn8
pn6:    ld b,1              ; scientific
        call pdig
        call putci
        db 'E'
        bit 0,(ix+2)
        ld a,'-'
        call nz,putc
        ld a,(ix+0)
        or a
        jr z,pn7
        add a,'0'
        call putc
pn7:    ld a,(ix+1)
        add a,'0'
        call putc
        jr pn9
pn8:    call pdig
pn9:    pop hl
        ret

; Print the mantissa at IX with a point after B digits (none if B is 0),
; leaving out zeros at the end.
pdig:   push bc
        push ix
        pop hl
        ld de,4
        add hl,de
        ld b,8
        call lastnz
        pop bc
        ld a,d
        cp b
        jr nc,pd1
        ld a,b
pd1:    ld e,a
        ld c,b
pd2:    ld a,(hl)
        inc hl
        add a,'0'
        call putc
        dec e
        ret z
        dec c
        jr nz,pd2
        call putci
        db '.'
        jr pd2

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

; Read a line into (DE), echoing it, ending it with a 0.  The time between
; keys stirs FRAN's seed.
accept: ld c,0
ac1:    ld a,1Fh            ; cursor: _
        call rawkey
        cp 0Dh
        jr z,ac9
        cp 8
        jr z,ac3
        ld b,a
        ld a,c
        cp 60
        jr nc,ac1           ; line full
        ld a,b
        ld (de),a
        inc de
        inc c
        call putc
        ld a,r
        ld hl,SEED
        xor (hl)
        ld (hl),a
        jr ac1
ac3:    ld a,c
        or a
        jr z,ac1
        dec c
        dec de
        ld hl,(CURS)
        dec hl
        ld (hl),' '
        ld (CURS),hl
        jr ac1
ac9:    xor a
        ld (de),a
        jr crlf

; Print the character after the CALL.
putci:  ex (sp),hl
        ld a,(hl)
        inc hl
        ex (sp),hl

; Print character A.  ASCII 40h-5Fh go to the display's 5-bit codes.
; Keeps everything but AF.
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

null:   db 0                ; an empty line
lastrom:
        ds 0C00h-$,0FFh
