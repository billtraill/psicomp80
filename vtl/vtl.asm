; COMP80 VTL-2
;
; VTL-2, the Very Tiny Language of the 1977 Altair 680, written afresh for
; the PSI COMP80 in the 2 KB of ROM (0400h-0BFFh) that held BURP.  The
; monitor (0000h-03FFh) is unchanged.  As with BURP, the RS key enters it:
; the monitor's NMI handler jumps to 0800h.
;
; Every statement is an assignment, one to a line: V=E.  A space ends it, so
; anything after one is a comment, and a line starting ) is all comment.
; Numbers are 16-bit unsigned, 0-65535, and an expression is worked out from
; left to right with no precedence: + - * / and = < > (> is greater or
; equal), which give 1 or 0, and brackets.  Every printable character is a
; variable; some are special:
;   #   the line number.  #=E goes to line E (the first line from E on), or
;       on to the next line if E is 0; ! is set to the line after.
;   !   so #=! comes back from a subroutine.
;   ?   ?="TEXT" prints and starts a new line (not with a ; after it);
;       ?=E prints a number; A=? reads one, typed as an expression.
;   $   $=E prints the character E (13 is a new line); A=$ waits for a key.
;   &   the end of the program; &=0 clears it.     *   the top of memory.
;   '   a random number; '=E sets the seed.         %   the remainder of the
;       last division.
;   :E) an array in the memory after the program.
;   @   @=E plots point E, Y*128+X, on the 128 x 62 quarter-character points
;       of lines 1-31; adding 8192 clears it instead.
; A line typed with a number goes into the program (a number alone deletes
; it); 0 lists the program, and a line without a number runs at once: #=1
; runs the program.
;
; The program is kept as typed: each line its number (2 bytes, low first),
; its text without the leading spaces, and 0Dh.  Lines are in order from
; 0C04h up to TXTEND (&).  The variables are 64 words at 1C00h, one for each
; character from 20h to 5Fh.  Statements run straight from the text: DE is
; the text pointer throughout.
;
; Keys and screen are handled as in COMP80 FORTH: the monitor's NMI handler
; echoes each key and wakes the HALT in RAWKEY; RS while waiting is a rubout
; and RS at any other time (re)starts VTL-2, keeping the program.  Any key
; while a program runs resets to the monitor; RS comes back with the
; program kept.  Line 0 shows VTL-2; lines 1-31 scroll.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
TXTEND: equ 0C02h           ; end of the program: &
PROG:   equ 0C04h           ; first line
MAGICV: equ 07714h
TOP:    equ 1C00h           ; *: the program and :) end below here
VARS:   equ 1C00h           ; a word for each character 20h-5Fh
VBANG:  equ VARS+2*('!'-20h)
VPCT:   equ VARS+2*('%'-20h)
TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
TIB2:   equ 1E00h           ; a number typed for ? (the same)
CURS:   equ 1DA0h           ; output position in screen memory
CURLN:  equ 1DA2h           ; the line running, 0 for a line typed in
RNDV:   equ 1DA4h           ; random number
S0:     equ 1F00h           ; stack (monitor uses 1Fxx)

        org 0400h

; ---------------------------------------------------------------- expressions
; Each returns its value in HL with DE past it; BC and A change.

ops:    db "+-*/=<>"

expr:   call term
ex1:    ld a,(de)
        push hl
        ld hl,ops
        ld bc,7
        cpir
        pop hl
        ret nz
        inc de
        push af             ; the operator
        push hl
        call term
        pop bc              ; left
        pop af
        push de
        ex de,hl            ; DE = right
        ld h,b
        ld l,c              ; HL = left
        cp '+'
        jr nz,ex2
        add hl,de
        jr ex9
ex2:    cp '*'
        jr nz,ex3
        ld b,d
        ld c,e
        call mul
        jr ex9
ex3:    cp '/'
        jr nz,ex4
        call udiv
        ld (VPCT),hl
        ld h,b
        ld l,c
        jr ex9
ex4:    ld b,a              ; - = < >: all subtract
        or a
        sbc hl,de           ; Z if equal, CY if left < right
        ld a,b
        cp '-'
        jr z,ex9
        add hl,de           ; CP took the flags: subtract again
        or a
        sbc hl,de
        ld hl,0             ; false, unless...
        jr z,ex6
        jr c,ex5
        cp '>'              ; left > right
        jr z,ex7
        jr ex9
ex5:    cp '<'              ; left < right
        jr z,ex7
        jr ex9
ex6:    cp '<'              ; equal: = and > are true
        jr z,ex9
ex7:    inc hl
ex9:    pop de
        jr ex1

; One value: a number, a variable, ( expression ) or :E).
term:   ld a,(de)
        cp 21h
        jr c,tm0            ; space or end: 0, and leave DE there
        inc de
        cp '('
        jr z,tm1
        cp ':'
        jr z,tm2
        cp '0'
        jr c,tm3
        cp '9'+1
        jr c,tm4
tm3:    cp '?'
        jr z,tminp
        cp '$'
        jr z,tmkey
        cp '#'
        jr z,tmline
        cp '&'
        jr z,tmend
        cp '*'
        jr z,tmtop
        cp 27h
        jr z,tmrnd
        call varadr
        jr ld16
tm0:    ld hl,0
        ret
tm1:    call expr
        jr close
tm2:    call expr
        call close
        call arradr
ld16:   ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret
tm4:    dec de
        jp getnum

tminp:  push de             ; ?: a line typed in, worked out
        ld de,TIB2
        push de
        call accin
        pop de
        call expr
        pop de
        ret

tmkey:  ld a,1Fh            ; $: a key
        call rawkey
        ld l,a
        ld h,0
        ret

tmline: ld hl,(CURLN)       ; #: the line number, 0 for a line typed in
        ld a,h
        or l
        ret z
        jr ld16

tmend:  ld hl,(TXTEND)
        ret

tmtop:  ld hl,TOP
        ret

tmrnd:  push de             ; ': the next random number
        ld hl,(RNDV)
        ld bc,25173
        call mul
        ld bc,13849
        add hl,bc
        ld (RNDV),hl
        ld a,r
        xor l
        ld l,h
        ld h,a
        pop de
        ret

; Skip a ) if there is one.
close:  ld a,(de)
        cp ')'
        ret nz
        inc de
        ret

; HL = address of the variable for character A.
varadr: sub 20h
        add a,a
        ld l,a
        ld h,VARS/256
        ret

; HL = address of :HL), in the memory after the program.
arradr: add hl,hl
        ld bc,(TXTEND)
        add hl,bc
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

; ---------------------------------------------------------------- arithmetic

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

; Print HL, unsigned.  Keeps DE.
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

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If VTL-2 was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) VTL-2.

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
        db " VTL-2",0
        call crlf
        ld hl,VRAM+40h
        ld (CURS),hl
        call CLS64

ready:  ld sp,S0
        call newl
        call prsi
        db "OK",0
        call crlf
getln:  ld sp,S0
        ld hl,0
        ld (CURLN),hl
        call accept
        ld de,TIB
        call skipsp
        sub '0'
        cp 10
        jp nc,stmt          ; no number: run it now
        call getnum
        ld a,h
        or l
        jr z,slist          ; 0: list the program
        call skipsp         ; a numbered line: replace the old one
        push de
        push hl
        call findln
        call z,delln
        pop hl
        push hl
        call findln         ; where it goes
        pop bc
        pop de
        ld a,(de)
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
        cp TOP/256
        jp nc,erfull
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

; A = the next character at DE that isn't a space.
skipsp: ld a,(de)
        cp ' '
        ret nz
        inc de
        jr skipsp

slist:  ld hl,PROG
ls1:    ld bc,(TXTEND)
        or a
        sbc hl,bc
        add hl,bc
        jp nc,ready
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
        ld a,r
        ld (RNDV),a
        ret

; ---------------------------------------------------------------- statements

; Run the statement at DE: V=E, :E)=E or a ) comment.
stmt:   ld a,(de)
        cp ')'
        jp z,nxtln2
        cp 0Dh
        jp z,nxtln2
        cp ':'
        jr nz,st1
        inc de
        call expr
        call close
        call arradr
        jr st2
st1:    inc de
        ld c,a
        ld a,(de)
        cp '='
        jr nz,erwhat
        ld a,c
        cp '?'
        jr z,sprint
        cp '#'
        jr z,sgoto
        cp '$'
        jp z,schar
        cp '&'
        jp z,send
        cp '@'
        jp z,splot
        cp 27h
        jp z,sseed
        call varadr
st2:    push hl
        ld a,(de)
        cp '='
        jr nz,erwhat
        inc de
        call expr
        pop bc
        ld a,l
        ld (bc),a
        inc bc
        ld a,h
        ld (bc),a

; After a statement: the next line, or OK after a line typed in.
nxtln2: ld hl,(CURLN)
        ld a,h
        or l
        jp z,ready
        call nxtln
goline: ld bc,(TXTEND)      ; run the line at HL, if it isn't the end
        or a
        sbc hl,bc
        add hl,bc
        jp nc,ready
        ld (CURLN),hl
        inc hl
        inc hl
        ex de,hl
        jr stmt

erwhat: call error
        db "WHAT?",0
erfull: call error
        db "FULL",0

; #=E: on to line E, or the next line if E is 0.
sgoto:  call expr1
        ld a,h
        or l
        jp z,nxtln2
        push hl
        call tmline         ; ! = this line + 1
        inc hl
        ld (VBANG),hl
        pop hl
        call findln
        jr goline

; ?="TEXT" (and a new line unless ; follows) or ?=E.
sprint: inc de
        ld a,(de)
        cp 22h
        jr nz,sp2
        inc de
sp1:    ld a,(de)
        cp 0Dh
        jr z,sp3
        inc de
        cp 22h
        jr z,sp3
        call putc
        jr sp1
sp3:    ld a,(de)
        cp ';'
        call nz,crlf
        jp nxtln2
sp2:    call expr
        call prnum
        jp nxtln2

; $=E: print character E.
schar:  call expr1
        ld a,l
        cp 0Dh
        jr nz,sc1
        call crlf
        jp nxtln2
sc1:    call putc
        jp nxtln2

; &=E: the end of the program; a value outside it clears it.
send:   call expr1
        ex de,hl
        ld hl,(TXTEND)
        or a
        sbc hl,de
        jr c,se1
        ld hl,PROG-1
        or a
        sbc hl,de
        jr nc,se1
        ld (TXTEND),de
        jp nxtln2
se1:    call new0
        jp nxtln2

; '=E: the random seed.
sseed:  call expr1
        ld (RNDV),hl
        jp nxtln2

; The expression after the = at DE.
expr1:  inc de
        jp expr

; @=E: plot point E, Y*128+X; with 8192 added, clear it.
splot:  call expr1
        push de
        ld a,l
        and 7Fh
        ld c,a              ; X
        add hl,hl
        ld a,h
        and 3Fh
        ld l,a              ; Y
        cp 62
        jr nc,pl9
        ld a,h
        and 40h             ; the 8192
        push af
        ld b,1              ; top left 1, top right 2,
        srl c               ; bottom right 4, bottom left 8
        jr nc,pl1
        ld b,2
pl1:    srl l
        jr nc,pl2
        ld a,b
        xor 3
        add a,a
        add a,a
        ld b,a
pl2:    ld h,0
        inc l
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
        ld a,(hl)           ; the points set already
        xor 40h
        cp 10h
        jr c,pl3
        xor a
pl3:    or b
        ld c,a
        pop af
        jr z,pl4
        ld a,c
        xor b
        ld c,a
pl4:    ld a,c
        or 40h              ; 40h alone is a checkerboard: blank is 20h
        cp 40h
        jr nz,pl5
        ld a,20h
pl5:    ld (hl),a
pl9:    pop de
        jp nxtln2

; ---------------------------------------------------------------- errors

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

; Read a line into TIB (or the page at DE, from accin), echoing it, ending
; with 0Dh.  Changes DE.
accept: ld de,TIB
accin:
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
