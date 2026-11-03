; COMP80 BASIC
;
; A Tiny BASIC for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that
; held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS
; key enters it: the monitor's NMI handler jumps to 0800h.
;
; Integer BASIC: 16-bit signed numbers, variables A-Z and an array @(I),
; numbered program lines kept as typed, statements PRINT INPUT LET IF GOTO
; GOSUB RETURN FOR NEXT REM END RUN LIST NEW, and graphics: PLOT and UNPLOT
; on the 128 x 62 quarter-character points of lines 1-31, POINT(X,Y) to test
; one, and CLS.
;
; The program is kept as typed, each line its number (2 bytes, low first),
; its text without the leading spaces, and 0Dh.  Lines are in order from
; 0C04h up to TXTEND, and @() is in the free space after them.  Statements
; are run straight from the text: DE is the text pointer throughout.
;
; FOR and GOSUB keep frames on the Z80 stack, which is otherwise empty
; between statements.  A GOSUB frame is the text pointer, the line and a 0
; on top; a FOR frame is the step, the limit, the text pointer, the line
; and the variable's address on top.  A 0FFFFh at the bottom marks the end.
;
; Keys and screen are handled as in COMP80 FORTH: the monitor's NMI handler
; echoes each key and wakes the HALT in RAWKEY; RS while waiting is a rubout
; and RS at any other time (re)starts BASIC, keeping the program.  Any key
; while a program runs resets to the monitor; RS comes back with the
; program kept.  Line 0 shows BASIC; lines 1-31 scroll.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
TXTEND: equ 0C02h           ; end of the program
PROG:   equ 0C04h           ; first line
MAGICV: equ 0BA5Ch
TOPH:   equ 1Ch             ; the program and @() end below 1C00h
VARS:   equ 1C00h           ; A-Z at 1C02h-1C35h
TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
CURS:   equ 1DA0h           ; output position in screen memory
CURLN:  equ 1DA2h           ; the line running, 0 for a line typed in
RNDV:   equ 1DA4h           ; random number
S0:     equ 1F00h           ; stack (monitor uses 1Fxx)

        org 0400h

; ---------------------------------------------------------------- tables
; Each entry is a name with 80h added to its last letter, then the address
; to go to.  A 0 ends the table; the address after it is used when nothing
; matches.

stab:   db "I",0C6h
        dw sif
        db "NEX",0D4h
        dw snext
        db "GOT",0CFh
        dw sgoto
        db "PRIN",0D4h
        dw sprint
        db "FO",0D2h
        dw sfor
        db "GOSU",0C2h
        dw sgosub
        db "RETUR",0CEh
        dw sret
        db "PLO",0D4h
        dw splot
        db "UNPLO",0D4h
        dw sunplot
        db "INPU",0D4h
        dw sinput
        db "LE",0D4h
        dw slet
        db "RE",0CDh
        dw srem
        db "EN",0C4h
        dw ready
        db "CL",0D3h
        dw scls
        db "RU",0CEh
        dw srun
        db "LIS",0D4h
        dw slist
        db "NE",0D7h
        dw snew
        db 0
        dw slet

ftab:   db "RN",0C4h
        dw frnd
        db "AB",0D3h
        dw fabs
        db "POIN",0D4h
        dw fpoint
        db 0
        dw fvar

tthen:  db "THE",0CEh
tto:    db "T",0CFh
tstep:  db "STE",0D0h
tat:    db "A",0D4h

; ---------------------------------------------------------------- scanning

; A = the next character at DE that isn't a space.
skipsp: ld a,(de)
        cp ' '
        ret nz
        inc de
        jr skipsp

; Z if A ends a statement.
iseos:  cp ':'
        ret z
        cp 0Dh
        ret

; Match the name at HL (80h on its last letter) with the text at DE.  Z and
; DE past it if it is there; NZ and DE as it was if not.  Either way HL ends
; past the name.
mtch:   call skipsp
        push de
mt1:    ld a,(hl)
        and 7Fh
        ex de,hl
        cp (hl)
        ex de,hl
        jr nz,mt3
        inc de
        bit 7,(hl)
        inc hl
        jr z,mt1
        pop af              ; matched (flags come next)
        xor a
        ret
mt3:    bit 7,(hl)
        inc hl
        jr z,mt3
        pop de
        or 1
        ret

; Go to the address in table HL for the name at DE (see the tables).
dispatch:
dp1:    ld a,(hl)
        or a
        jr nz,dp2
        inc hl
        jr dp3
dp2:    call mtch
        jr z,dp3
        inc hl
        inc hl
        jr dp1
dp3:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

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

; ( expression ), and the expected-character checks.  Change BC.
parexp: ld a,'('
        call expct
        call expr
close:  ld a,')'
        db 1                ; LD BC,nn: skips the next instruction
comma:  ld a,','
expct:  ld b,a
        call skipsp
        cp b
        jp nz,ersyn
        inc de
        ret

; ---------------------------------------------------------------- expressions
; Each returns its value in HL with DE past it; BC and A change.

; Relations: = < > <= >= <> give 1 if true, 0 if false.
expr:   call aexp
        push hl
        ld c,0              ; 1 <, 2 =, 4 >
ex1:    call skipsp
        ld b,1
        cp '<'
        jr z,ex2
        ld b,2
        cp '='
        jr z,ex2
        ld b,4
        cp '>'
        jr nz,ex3
ex2:    ld a,c
        or b
        ld c,a
        inc de
        jr ex1
ex3:    pop hl
        ld a,c
        or a
        ret z
        push af
        push hl
        call aexp
        pop bc              ; left
        push de
        ex de,hl            ; DE = right
        ld h,b
        ld l,c
        call scmp
        pop de
        ld b,1
        jr c,ex4
        ld b,2
        jr z,ex4
        ld b,4
ex4:    pop af
        and b
        ld hl,0
        ret z
        inc hl
        ret

aexp:   call term
ae1:    call skipsp
        cp '+'
        jr z,ae2
        cp '-'
        ret nz
        inc de
        push hl
        call term
        call neghl
        jr ae3
ae2:    inc de
        push hl
        call term
ae3:    pop bc
        add hl,bc
        jr ae1

term:   call factor
tm1:    call skipsp
        cp '*'
        jr z,tm2
        cp '/'
        ret nz
        inc de
        push hl
        call factor
        ld b,h
        ld c,l
        pop hl
        call sdiv
        jr tm1
tm2:    inc de
        push hl
        call factor
        pop bc
        call mul
        jr tm1

factor: call skipsp
        cp '-'
        jr nz,fa1
        inc de
        call factor
        jr neghl
fa1:    cp '('
        jp z,parexp
        call getnum
        ret c
        ld hl,ftab
        jp dispatch

fvar:   call getvar
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

fabs:   call parexp
abshl:  bit 7,h
        ret z
neghl:  xor a
        sub l
        ld l,a
        sbc a,a
        sub h
        ld h,a
        ret

; RND(N): 1 to N.
frnd:   call parexp
        push de
        push hl
        ld hl,(RNDV)
        ld bc,25173
        call mul
        ld bc,13849
        add hl,bc
        ld (RNDV),hl
        ld a,h              ; the high bits are the random ones
        ld h,l
        ld l,a
        res 7,h
        pop de
        call udiv
        inc hl
        pop de
        ret

; POINT(X,Y): 1 if the point is set.
fpoint: ld a,'('
        call expct
        call getxy
        jr z,fp1
        call pbits
        and c
fp1:    ld hl,0
        jp z,close
        inc hl
        jp close

; HL = address of variable A-Z or @(I).
getvar: call skipsp
        sub '@'
        jr z,gv1
        jp c,ersyn
        cp 27
        jp nc,ersyn
        inc de
        add a,a
        ld l,a
        ld h,VARS/256
        ret
gv1:    inc de
        call parexp
        bit 7,h
        jp nz,erline
        add hl,hl
        ld bc,(TXTEND)
        add hl,bc
        ld a,h
        cp TOPH
        ret c
        jp ermem

; ---------------------------------------------------------------- arithmetic

; CY = HL < DE, signed (Z if equal).  Changes HL, DE, A.
scmp:   ld a,h
        xor 80h
        ld h,a
        ld a,d
        xor 80h
        ld d,a
        sbc hl,de
        ret

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

; HL = HL / BC, signed, rounding towards zero.  Keeps DE.
sdiv:   ld a,b
        or c
        jp z,erdiv
        push de
        ld a,h
        xor b
        push af
        call abshl
        push hl
        ld h,b
        ld l,c
        call abshl
        ex de,hl
        pop hl
        call udiv
        ld h,b
        ld l,c
        pop af
        call m,neghl
        pop de
        ret

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

; ---------------------------------------------------------------- graphics

; X,Y at DE: HL = screen address and C = the bit of the point, NZ; Z if the
; point is off the screen.  X is 0-127, Y 0-61 (lines 1-31).
getxy:  call expr
        push hl
        call comma
        call expr
        pop bc
        ld a,b
        or h
        jr nz,gx9
        ld a,c
        cp 128
        jr nc,gx9
        ld a,l
        cp 62
        jr nc,gx9
        ld b,1              ; top left 1, top right 2,
        srl c               ; bottom right 4, bottom left 8
        jr nc,gx1
        ld b,2
gx1:    srl l
        jr nc,gx2
        ld a,b
        xor 3
        add a,a
        add a,a
        ld b,a
gx2:    inc l
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
        ld a,b
        ld c,a
        or a
        ret
gx9:    xor a
        ret

; A = the points set in the character at HL (0 unless it is 40h-4Fh).
pbits:  ld a,(hl)
        xor 40h
        cp 10h
        ret c
        xor a
        ret

splot:  call getxy
        jp z,nxtst
        call pbits
        or c
        jr pl1
sunplot: call getxy
        jp z,nxtst
        call pbits
        ld b,a
        ld a,c
        cpl
        and b
pl1:    or 40h              ; 40h alone is a checkerboard: blank is 20h
        cp 40h
        jr nz,pl2
        ld a,20h
pl2:    ld (hl),a
        jp nxtst

scls:   call cls
        jp nxtst

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

; Print the text at DE up to a " (DE past it) or the end of the line.
prstr:  ld a,(de)
        cp 0Dh
        ret z
        inc de
        cp 22h
        ret z
        call putc
        jr prstr

; Spaces to the next multiple of 16 columns.
tab:    ld a,' '
        call putc
        ld a,(CURS)
        and 0Fh
        jr nz,tab
        ret

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If BASIC was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) BASIC.

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
        call nz,new0        ; no program in RAM: start an empty one
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " BASIC",0
        call crlf
        call cls

ready:  ld sp,S0
        ld hl,0FFFFh        ; the bottom of the FOR and GOSUB frames
        push hl
        call newl
        call prsi
        db "OK",0
        call crlf
getln:  ld sp,S0-2
        ld hl,0
        ld (CURLN),hl
        call accept
        ld de,TIB
        call getnum
        jp nc,stmt
        push de             ; a numbered line: replace the old one
        push hl
        call findln
        call z,delln
        pop hl
        push hl
        call findln         ; where it goes
        pop bc
        pop de
        call skipsp
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
        jr getln

; ---------------------------------------------------------------- statements

; Run the statement at DE.
stmt:   call skipsp
        call iseos
        jr z,nxtst
        push de             ; V = ...: straight to LET
        inc de
        call skipsp
        pop de
        cp '='
        jr z,slet
        ld hl,stab
        jp dispatch

; After a statement: a : and the next one, or the next line.
nxtst:  call skipsp
        cp ':'
        jr nz,ns1
        inc de
        jr stmt
ns1:    cp 0Dh
        jp nz,ersyn
        ld hl,(CURLN)
        ld a,h
        or l
        jp z,ready
        call nxtln
goline: ld bc,(TXTEND)      ; run the line at HL, if it isn't the end
        or a
        sbc hl,bc
        add hl,bc
        jp nc,ready
gorun:  ld (CURLN),hl
        inc hl
        inc hl
        ex de,hl
        jr stmt

slet:   call assign
        jr nxtst

; V = expression; BC = the variable's address.
assign: call getvar
        push hl
        ld a,'='
        call expct
        call expr
        pop bc
        ld a,l
        ld (bc),a
        inc bc
        ld a,h
        ld (bc),a
        dec bc
        ret

sprint: call skipsp
        call iseos
        jr z,pr9
pr1:    cp 22h
        jr nz,pr2
        inc de
        call prstr
        jr pr4
pr2:    ld hl,tat
        call mtch
        jr nz,pr3
        call expr           ; AT X,Y: column 0-63, line 1-31
        push hl
        call comma
        call expr
        ld h,l
        ld l,0
        srl h
        rr l
        srl h
        rr l
        pop bc
        add hl,bc
        set 7,h
        ld (CURS),hl
        jr pr4
pr3:    call expr
        call prnum
pr4:    call skipsp
        cp ';'
        jr z,pr5
        cp ','
        jr nz,pr9
        call tab
pr5:    inc de
        call skipsp
        call iseos
        jr nz,pr1
        jp nxtst
pr9:    call crlf
        jp nxtst

sinput: call skipsp
        cp 22h
        jr nz,in2
        inc de
        call prstr
        call skipsp
        cp ';'
        jr z,in1
        cp ','
        jr nz,in2
in1:    inc de
in2:    call getvar
        push hl
        push de
        ld a,'?'
        call putc
        call accept
        ld de,TIB
        call expr
        ld b,h
        ld c,l
        pop de
        pop hl
        ld (hl),c
        inc hl
        ld (hl),b
        call skipsp
        cp ','
        jp nz,nxtst
        inc de
        jr in2

sif:    call expr
        ld a,h
        or l
        jr z,srem
        ld hl,tthen
        call mtch
        call getnum
        jp nc,stmt
        jr goto1

srem:   ld a,(de)
        cp 0Dh
        jp z,nxtst
        inc de
        jr srem

sgosub: call chksp
        call expr
        push de
        ld bc,(CURLN)
        push bc
        ld bc,0
        push bc
        jr goto1

sgoto:  call expr
goto1:  call findln
        jp nz,erline
        jp gorun

sret:   pop bc
        ld a,b
        or c
        jr z,rt1
        inc bc
        ld a,b
        or c
        jp z,erret
        pop bc
        pop bc
        pop bc
        pop bc
        jr sret
rt1:    pop hl
        ld (CURLN),hl
        pop de
        jp nxtst

sfor:   call chksp
        call assign
        pop hl              ; already in a FOR of this variable? drop it
        push hl
        or a
        sbc hl,bc
        jr nz,fo1
        pop hl
        pop hl
        pop hl
        pop hl
        pop hl
fo1:    push bc
        ld hl,tto
        call mtch
        jp nz,ersyn
        call expr           ; limit
        push hl
        ld hl,tstep
        call mtch
        ld hl,1
        call z,expr         ; step
        pop bc
        ex (sp),hl          ; HL = variable
        push bc
        push de
        ld bc,(CURLN)
        push bc
        push hl
        jp nxtst

snext:  call getvar
nx1:    pop bc
        ld a,b
        or c
        jp z,ernext
        inc bc
        ld a,b
        or c
        jp z,ernext
        dec bc
        ld a,c
        cp l
        jr nz,nx2
        ld a,b
        cp h
        jr z,nx3
nx2:    pop af              ; a loop left by an inner NEXT
        pop af
        pop af
        pop af
        jr nx1
nx3:    push bc
        push de
        ld ix,0
        add ix,sp           ; +4 line, +6 text, +8 limit, +10 step
        ld c,(ix+10)
        ld b,(ix+11)
        push hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        add hl,bc
        ex de,hl            ; DE = new value
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
        ld l,(ix+8)
        ld h,(ix+9)
        ld a,b
        rla
        jr nc,nx4
        ex de,hl
nx4:    call scmp           ; CY: past the limit
        pop de
        jr c,nx5
        ld l,(ix+4)
        ld h,(ix+5)
        ld (CURLN),hl
        ld e,(ix+6)
        ld d,(ix+7)
        jp nxtst
nx5:    pop af
        pop af
        pop af
        pop af
        pop af
        jp nxtst

; Room for another frame?
chksp:  ld hl,-1E00h
        add hl,sp
        ret c
        jp ermem

srun:   ld a,r
        ld (RNDV),a
        ld hl,VARS
        ld b,54
ru1:    ld (hl),0
        inc hl
        djnz ru1
        ld sp,S0-2
        ld hl,PROG
        jp goline

slist:  call getnum
        call findln
ls1:    ld bc,(TXTEND)
        or a
        sbc hl,bc
        add hl,bc
        jp nc,nxtst
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

snew:   call new0
        jp ready

new0:   ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,PROG
        ld (TXTEND),hl
        ret

; ---------------------------------------------------------------- errors

ersyn:  call error
        db "SYNTAX?",0
erline: call error
        db "LINE?",0
erdiv:  call error
        db "DIVIDE?",0
ermem:  call error
        db "MEMORY?",0
erret:  call error
        db "RETURN?",0
ernext: call error
        db "NEXT?",0

error:  call newl
        pop hl
        call prs
        ld hl,(CURLN)
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

; Read a line into TIB, echoing it, ending with 0Dh.  Changes DE.
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
