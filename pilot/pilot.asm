; COMP80 PILOT
;
; PILOT, the 1970s teaching language, for the PSI COMP80, in the 2 KB of ROM
; (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh) is unchanged.  As
; with BURP, the RS key enters it: the monitor's NMI handler jumps to 0800h.
;
; A line typed with a number in front is stored in the program (a number on
; its own deletes that line); LIST, RUN and NEW work on the program; any
; other line runs at once.  A statement is
;
;   [*LABEL] OP[Y|N][(CONDITION)]:TEXT
;
;   T: type TEXT, with $X and #X replaced by the variables' values
;   A: accept a line into the answer; A:$X or A:#X also keeps it in X
;   M: match: Y if any of TEXT's comma-separated words is in the answer
;   J: jump to a label        U: use a label as a subroutine
;   E: end a subroutine, or the program
;   C: compute: C:#X=EXPRESSION or C:$X=TEXT
;   G: plot point X,Y on the 128 x 62 quarter-block screen; G: alone clears
;   R: remark
;
; OPY and OPN only run when the last M: matched or didn't; Y: and N: are
; short for TY: and TN:.  (CONDITION) is an expression, or two compared with
; < > = <> <= >=.  Expressions are 16-bit integers with + - * / ( ), #X or X
; for a variable and ?N for a random number from 1 to N.
;
; Variables: #A-#Z are numbers, $A-$Z strings of up to 31 characters.
;
; Program lines are kept in order of number from PROG: number (2 bytes),
; length of the whole record (1), text, 0.
;
; Keys and screen are as in FORTH: the monitor's NMI handler echoes each key
; at (DE); RS while waiting for a key is rubout; any key while a program runs
; resets to the monitor and RS comes back with the program kept.  Line 0
; shows PILOT, lines 1-31 scroll.

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
PEND:   equ 0C02h           ; end of the program
SEED:   equ 0C04h           ; random number seed
PROG:   equ 0C06h           ; first program line
PTOP:   equ 1980h           ; the program must end below here
MAGICV: equ 0A11Ch

SVARS:  equ 1980h           ; $A-$Z, 32 bytes each
ANS:    equ 1CC0h           ; the answer (80 bytes)
TIB:    equ 1D10h           ; input line (80 bytes)
NVARS:  equ 1D60h           ; #A-#Z, 2 bytes each
VEND:   equ 1D94h
CURS:   equ 1DA0h           ; output position in screen memory
LP:     equ 1DA2h           ; line running, or 0
NLP:    equ 1DA4h           ; line to run next; 0FFFFh to stop
FLAG:   equ 1DA6h           ; 'Y' or 'N', set by M:
USP:    equ 1DA8h           ; U: stack pointer
USTK:   equ 1DAAh           ; U: stack, 8 return lines
USTKL:  equ 0AAh            ; low bytes of USTK and of its end
USTKE:  equ 0BAh
S0:     equ 1F00h           ; machine stack (the monitor uses 1Fxx)

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

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

; Read a line into the buffer at DE, echoing it, and end it with 0.
accept: ld b,0
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
        jr crlf

; Print character A (ASCII 20h-5Fh).  Keeps everything but AF.
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

; Print HL (signed) in decimal.  Keeps BC, DE.
dot:    bit 7,h
        jr z,udot
        ld a,'-'
        call putc
        call neghl
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

; HL = BC / HL, signed, rounding towards zero.
sdiv:   ld a,h
        or l
        jp z,what
        ex de,hl
        ld h,b
        ld l,c
        ld a,h
        xor d
        push af             ; sign of the quotient
        bit 7,h
        call nz,neghl
        ex de,hl
        bit 7,h
        call nz,neghl
        ex de,hl
        call udiv
        ld h,b
        ld l,c
        pop af
        ret p
        jr neghl

; HL = a random number from 1 to HL.
rnd:    push de
        push hl
        ld hl,(SEED)
        ld de,25173
        call mul16
        ld de,13849
        add hl,de
        ld (SEED),hl
        srl h
        rr l
        pop de
        ld a,d
        or e
        jr z,rn1
        call udiv
        inc hl
rn1:    pop de
        ret

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

; CY if (DE) is a letter; A = 0 for A.
alpha:  ld a,(de)
        sub 'A'
        cp 26
        ret

; HL = the unsigned number at DE.  Keeps BC.
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

; HL = the number at DE, with an optional minus sign.
signum: call skipsp
        cp '-'
        jr nz,getnum
        inc de
        call getnum
        jp neghl

; HL = address of #A + A, skipping the letter.
nvar:   inc de
        add a,a
        ld hl,NVARS
        add a,l
        ld l,a
        ret

; HL = address of $A + A, skipping the letter.
svar:   inc de
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        push bc
        ld bc,SVARS
        add hl,bc
        pop bc
        ret

; Expressions: HL = value.
expr:   call term
ex1:    call skipsp
        cp '+'
        jr z,ex2
        cp '-'
        ret nz
ex2:    inc de
        push af
        push hl
        call term
        pop bc
        pop af
        cp '+'
        jr z,ex3
        call neghl
ex3:    add hl,bc
        jr ex1

term:   call factor
te1:    call skipsp
        cp '*'
        jr z,te2
        cp '/'
        ret nz
te2:    inc de
        push af
        push hl
        call factor
        pop bc
        pop af
        push de
        cp '*'
        jr nz,te3
        ld d,b
        ld e,c
        call mul16
        jr te4
te3:    call sdiv
te4:    pop de
        jr te1

factor: call skipsp
        inc de
        cp '('
        jr nz,fa1
        call expr
        call skipsp
        cp ')'
        jp nz,what
        inc de
        ret
fa1:    cp '-'
        jr nz,fa2
        call factor
        jp neghl
fa2:    cp '?'
        jr nz,fa3
        call factor
        jp rnd
fa3:    cp '#'
        jr z,fa4
        dec de
fa4:    call alpha
        jr nc,fa5
        call nvar
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
fa5:    call isdig
        jp nc,what
        jp getnum

; A condition: HL = 0 if false.  One expression, or two compared.
cond:   call expr
        call skipsp
        cp '<'
        jr z,cd0
        cp '>'
        jr z,cd0
        cp '='
        ret nz
cd0:    ld c,0              ; bit 0 less, bit 1 equal, bit 2 greater
cd1:    ld a,(de)
        cp '<'
        jr nz,cd2
        set 0,c
        jr cd4
cd2:    cp '='
        jr nz,cd3
        set 1,c
        jr cd4
cd3:    cp '>'
        jr nz,cd5
        set 2,c
cd4:    inc de
        jr cd1
cd5:    push bc
        push hl
        call expr
        ex de,hl            ; DE = right
        ex (sp),hl          ; HL = left, text on the stack
        push hl
        or a
        sbc hl,de
        pop hl
        ld a,2
        jr z,cd6
        call scmp
        ld a,1
        jr c,cd6
        ld a,4
cd6:    pop de
        pop bc
        and c
        ld hl,0
        ret z
        inc hl
        ret

; Compare the word at HL (ending 0) with the text: Z if the text has it,
; followed by a space or the end.
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
        pop de
        ret
kw2:    ld a,(de)
        pop de
        or a
        ret z
        cp ' '
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

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If PILOT was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) PILOT.

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
        db " PILOT",0
        call crlf
        call cls

main:   ld sp,S0
        ld hl,0
        ld (LP),hl
        dec hl
        ld (NLP),hl
        ld hl,USTK
        ld (USP),hl
        ld de,TIB
        call accept
        ld de,TIB
        call skipsp
        call isdig
        jp c,edit
        ld hl,s_list
        call kw
        jr z,list
        ld hl,s_run
        call kw
        jr z,runc
        ld hl,s_new
        call kw
        jr z,newc
        call stmt           ; run the line; a J: or U: carries on
        ld hl,(NLP)

; Run the program from line HL until NLP is past the end.
runl:   ld (LP),hl
        call before
        jr nc,main
        call nextrec
        ld (NLP),hl
        ld hl,(LP)
        inc hl
        inc hl
        inc hl
        ex de,hl
        call stmt
        ld hl,(NLP)
        jr runl

runc:   ld hl,SVARS         ; clear the variables
        ld de,SVARS+1
        ld bc,VEND-SVARS-1
        ld (hl),0
        ldir
        ld a,'N'
        ld (FLAG),a
        ld hl,PROG
        jr runl

newc:   call new
        jr main

new:    ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,PROG
        ld (PEND),hl
        ld (SEED),hl
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
s_new:  db "NEW",0

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

; ---------------------------------------------------------------- statements

; Run the statement at DE.
stmt:   call skipsp
        cp '*'
        jr nz,st1
st0:    inc de              ; a label: skip it
        ld a,(de)
        or a
        ret z
        cp ' '
        jr nz,st0
        call skipsp
st1:    or a
        ret z
        ld c,a              ; C = the statement letter
        inc de
        ld b,0              ; B = Y or N, if it has one
        cp 'Y'
        jr z,st2
        cp 'N'
        jr nz,st3
st2:    ld a,(de)           ; Y: and N: are TY: and TN:
        cp ':'
        jr z,st2a
        cp '('
        jr nz,st3
st2a:   ld b,c
        ld c,'T'
        jr st4
st3:    ld a,(de)
        cp 'Y'
        jr z,st3a
        cp 'N'
        jr nz,st4
st3a:   ld b,a
        inc de
st4:    ld a,b
        or a
        jr z,st5
        ld a,(FLAG)
        cp b
        ret nz
st5:    ld a,(de)
        cp '('
        jr nz,st6
        inc de
        push bc
        call cond
        pop bc
        call skipsp
        cp ')'
        jr nz,what
        inc de
        ld a,h
        or l
        ret z
st6:    ld a,(de)
        cp ':'
        jr nz,what
        inc de
        ld hl,optab
st7:    ld a,(hl)
        or a
        jr z,what
        inc hl
        cp c
        jr z,st8
        inc hl
        inc hl
        jr st7
st8:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

optab:  db 'T'
        dw opt
        db 'A'
        dw opa
        db 'M'
        dw opm
        db 'J'
        dw opj
        db 'U'
        dw opu
        db 'E'
        dw ope
        db 'C'
        dw opc
        db 'G'
        dw opg
        db 'R'
        dw opr
        db 0

; Something wrong: say so, with the line number if a program is running.
what:   call prsi
        db "WHAT?",0
wh0:    ld hl,(LP)
        ld a,h
        or l
        jr z,wh1
        call prsi
        db " IN ",0
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        call udot
wh1:    call crlf
        jp main
full:   call prsi
        db "FULL",0
        jr wh0

; T: print the text, putting in the values of $X and #X.
opt:    call ptext
        jp crlf
ptext:  ld a,(de)
        or a
        ret z
        inc de
        cp '$'
        jr z,pt1
        cp '#'
        jr z,pt2
pt0:    call putc
        jr ptext
pt1:    call alpha
        ld a,'$'
        jr nc,pt0
        call alpha
        call svar
        call puts
        jr ptext
pt2:    call alpha
        ld a,'#'
        jr nc,pt0
        call alpha
        call nvar
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call dot
        jr ptext

; A: read the answer; A:$X and A:#X keep it in X too.
opa:    push de
        ld de,ANS
        call accept
        pop de
        call skipsp
        inc de
        cp '$'
        jr z,oa1
        cp '#'
        ret nz
        call alpha
        jp nc,what
        call nvar
        push hl
        ld de,ANS
        call signum
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
opr:    ret
oa1:    call alpha
        jp nc,what
        call svar
        ex de,hl
        ld hl,ANS
scopy:  ld c,31             ; copy a string from HL to DE
sc1:    ld a,(hl)
        ld (de),a
        or a
        ret z
        inc hl
        inc de
        dec c
        jr nz,sc1
        xor a
        ld (de),a
        ret

; M: FLAG = Y if any of the words is in the answer.
opm:    ld a,'N'
        ld (FLAG),a
om1:    call skipsp
        ld hl,ANS
om2:    push hl
        push de
om3:    ld a,(de)
        or a
        jr z,om5
        cp ','
        jr z,om5
        cp (hl)
        jr nz,om4
        inc hl
        inc de
        jr om3
om4:    pop de
        pop hl
        ld a,(hl)
        inc hl
        or a
        jr nz,om2
om6:    ld a,(de)           ; on to the next word
        inc de
        or a
        ret z
        cp ','
        jr nz,om6
        jr om1
om5:    pop de
        pop hl
        ld a,'Y'
        ld (FLAG),a
        ret

; J: jump to a label.
opj:    call findlab
        ld (NLP),hl
        ret

; U: jump to a label, coming back at E:.
opu:    call findlab
        ex de,hl
        ld hl,(USP)
        ld a,l
        cp USTKE
        jp z,what
        ld bc,(NLP)
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        ld (USP),hl
        ld (NLP),de
        ret

; E: back from U:, or the end of the program.
ope:    ld hl,(USP)
        ld a,l
        cp USTKL
        jr z,oe1
        dec hl
        ld b,(hl)
        dec hl
        ld c,(hl)
        ld (USP),hl
        ld (NLP),bc
        ret
oe1:    ld hl,0FFFFh
        ld (NLP),hl
        ret

; HL = the line with the label at DE (with or without its *).
findlab:
        call skipsp
        cp '*'
        jr nz,fb0
        inc de
fb0:    ld hl,PROG
fb1:    call before
        jp nc,what
        push hl
        push de
        inc hl
        inc hl
fb2:    inc hl
        ld a,(hl)
        cp ' '
        jr z,fb2
        cp '*'
        jr nz,fb5
fb3:    inc hl
        ld a,(de)
        cp ' '+1
        jr c,fb4
        cp (hl)
        jr nz,fb5
        inc de
        jr fb3
fb4:    ld a,(hl)
        cp ' '+1
        jr nc,fb5
        pop de
        pop hl
        ret
fb5:    pop de
        pop hl
        call nextrec
        jr fb1

; C: #X=EXPRESSION or $X=TEXT.
opc:    call skipsp
        cp '$'
        jr z,oc2
        cp '#'
        jr nz,oc1
        inc de
oc1:    call alpha
        jp nc,what
        call nvar
        call equals
        push hl
        call expr
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        ret
oc2:    inc de
        call alpha
        jp nc,what
        call svar
        call equals
        ex de,hl
        jp scopy

equals: call skipsp
        cp '='
        jp nz,what
        inc de
        ret

; G: X,Y plots a point; G: alone clears the screen.
opg:    call skipsp
        or a
        jp z,cls
        call expr
        push hl
        call skipsp
        cp ','
        jp nz,what
        inc de
        call expr
        pop bc              ; BC = x, HL = y
        ld a,h
        or b
        ret nz
        ld a,c
        cp 128
        ret nc
        ld a,l
        cp 62
        ret nc
        ld a,1              ; top left
        bit 0,c
        jr z,g1
        ld a,2              ; top right
g1:     bit 0,l
        jr z,g2
        cp 1
        ld a,8              ; bottom left
        jr z,g2
        ld a,4              ; bottom right
g2:     ld b,a
        srl l
        inc l
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,c
        srl a
        add a,l
        ld l,a
        ld a,h
        add a,VRAM/256
        ld h,a
        ld a,(hl)
        sub 40h
        cp 10h
        jr c,g3
        xor a
g3:     or b
        add a,40h
        ld (hl),a
        ret

part2_end:
        ds 0C00h-$,0FFh
