; COMP80 LOGO
;
; A small Logo for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that
; held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS
; key enters it: the monitor's NMI handler jumps to 0800h.
;
; Screen: line 0 shows LOGO (where the monitor shows READY).  Lines 1-26 are
; the turtle's field: 128 x 52 quarter-character points.  Lines 27-31 are
; for typing and printing, and scroll on their own.
;
; The turtle.  A quarter character is 3 units wide and 5 tall on the screen,
; so a turtle step is one point across but 0.6 of a point up or down, and a
; square comes out square.  The field is 128 steps across and 86 up.  X and
; Y are kept in points with 8 bits of fraction, with HOME (0,0) in the
; middle; the heading is in degrees, 0 up and clockwise.  FD draws a point
; at every step.
;
; The interpreter works on the text itself.  A line, or a procedure's body,
; is a run of words: numbers, :NAMES (variables), "NAMES (quoted words),
; and the single characters [ ] ( ) + - * / < = >.  A - after a space and
; before a digit starts a negative number instead, so SETXY 0 -40 is two
; numbers, as in other Logos.  A ; ends the line.
; Numbers are 16-bit signed integers.
;
; Procedures (TO ... END) are kept as text: link (2 bytes), then the words
; from the name to the word before END, one space apart, and a 0.
; Variables are a table of name pointer (2) + value (2): MAKE's globals grow
; down from VB, a procedure's inputs are pushed above VB as it is called and
; dropped when it returns.  A name is looked up from the newest entry down,
; so scope is dynamic, as in other Logos.
;
; Keys.  The monitor's NMI handler echoes each key at (DE) and folds codes
; 40h and up to 5 bits.  RS (the ^ key) makes it jump to 0800h; if that
; happens while LOGO waits in RAWKEY, ENTRY treats it as rubout.  FS
; (Ctrl+\) goes back to the monitor.  Any key while a program runs makes the
; NMI handler reset to the monitor; RS then comes back to LOGO with the
; procedures kept.

MAGIC:  equ 0C00h           ; MAGICV when the procedures below are valid
LATEST: equ 0C02h           ; newest procedure
HERE:   equ 0C04h           ; first free byte
GP:     equ 0C06h           ; lowest global variable
PROC0:  equ 0C08h           ; procedures start here
MAGICV: equ 4C47h

VB:     equ 1700h           ; globals below, procedure inputs above
VTOP:   equ 1A00h           ; inputs stop here

TIB:    equ 1A00h           ; input line (80 bytes and a 0)
CURS:   equ 1A60h           ; output position in screen memory
TPV:    equ 1A62h           ; the word being read
BP:     equ 1A64h           ; top of the variable table
FRAME:  equ 1A66h           ; stack of the innermost procedure, or 0
RES:    equ 1A68h           ; OUTPUT's value
XP:     equ 1A6Ah           ; turtle x, points * 256
YP:     equ 1A6Ch           ; turtle y, points * 256
HEAD:   equ 1A6Eh           ; heading, 0-359
DX:     equ 1A70h           ; one step
DY:     equ 1A72h
SEED:   equ 1A74h
PEN:    equ 1A76h           ; byte: 0 up, 1 down, 2 erase
DLY:    equ 1A77h           ; byte: delay at each step
STKLIM: equ 1AC0h           ; deepest the stack may go
S0:     equ 1F00h           ; stack (the monitor uses 1Fxx)

VRAM:   equ 8000h
TXT0:   equ VRAM+27*64      ; first text line
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

        org 0400h

; ---------------------------------------------------------------- words

; Next word from TPV.  HL = its first character, B = its length, A = its
; first character; at the end of the text (a 0 or a ;) B = A = 0 and TPV
; stays put.  Keeps C, DE.
nexttok:
        ld hl,(TPV)
nt1:    ld a,(hl)
        cp ' '
        jr nz,nt2
        inc hl
        jr nt1
nt2:    ld b,0
        cp ';'
        jr z,nt8
        or a
        jr z,nt9
        push hl
        cp '-'              ; a - after a space and before a digit
        jr nz,nt3           ; starts a negative number
        dec hl
        ld a,(hl)
        inc hl
        cp ' '
        jr nz,nt3m
        inc hl
        ld a,(hl)
        dec hl
        sub '0'
        cp 10
        jr nc,nt3m
        inc hl
        inc b
        jr nt4
nt3m:   ld a,'-'
nt3:    call isdelim
        jr nz,nt4
        inc hl
        inc b
        jr nt7
nt4:    ld a,(hl)
        call isend
        jr z,nt7
        cp ';'
        jr z,nt7
        inc hl
        inc b
        jr nt4
nt7:    ld (TPV),hl
        pop hl
        ld a,(hl)
        ret
nt8:    xor a
nt9:    ld (TPV),hl
        ret

; A = first character of the next word (0 at the end), without reading it.
; Keeps HL, C, DE.
peek:   push hl
        ld hl,(TPV)
        push hl
        call nexttok
        pop hl
        ld (TPV),hl
        pop hl
        ret

; The word at HL, leaving TPV alone: HL = its start, A = its first
; character, DE = just past it.
ptok:   ld de,(TPV)
        push de
        ld (TPV),hl
        call nexttok
        ld de,(TPV)
        ex (sp),hl
        ld (TPV),hl
        pop hl
        ret

; Z if A ends a word: space, 0 or one of the single-character words.
isend:  cp ' '
        ret z
        or a
        ret z
isdelim:
        push hl
        push bc
        ld hl,delims
        ld b,11
id1:    cp (hl)
        jr z,id9
        inc hl
        djnz id1
id9:    pop bc
        pop hl
        ret
delims: db "[]()+-*/<=>"

; Z if the word at HL (B characters) is the name at DE.  Keeps HL, BC, DE.
namecmp:
        push hl
        push bc
        push de
nc1:    ld a,(de)
        cp (hl)
        jr nz,nc9
        inc hl
        inc de
        djnz nc1
        ld a,(de)
        call isend
nc9:    pop de
        pop bc
        pop hl
        ret

; Look the word at HL (B characters) up in the table at DE: names with bit
; 7 set on the last character, each followed by its address, ending in 0.
; Found: jump there, in place of the caller, which it returns to.  Not
; found: return, keeping HL and B.
lookup: ld a,(de)
        or a
        ret z
        push hl
        ld c,b
lk2:    ld a,(de)
        and 7Fh
        cp (hl)
        jr nz,lk5
        inc hl
        dec c
        ld a,(de)
        inc de
        rla
        jr nc,lk3
        ld a,c
        or a
        jr nz,lk6
        pop hl
        ex de,hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        pop de              ; not back to the caller
        jp (hl)
lk3:    ld a,c
        or a
        jr nz,lk2
lk5:    ld a,(de)
        inc de
        rla
        jr nc,lk5
lk6:    inc de
        inc de
        pop hl
        jr lookup

; The procedure named by the word at HL (B characters): Z and DE = its text.
findproc:
        ld de,(LATEST)
fp1:    ld a,d
        or e
        jr z,fp8
        push de
        inc de
        inc de
        call namecmp
        pop de
        jr z,fp9
        ex de,hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        jr fp1
fp8:    inc a
        ret
fp9:    inc de
        inc de
        ret

; The variable named by the word at HL (B characters): Z and HL = the
; address of its value.
findvar:
        ld de,(BP)
fv1:    push hl
        ld hl,(GP)
        or a
        sbc hl,de
        pop hl
        jr z,fv8
        dec de
        dec de
        dec de
        dec de
        push de
        ex de,hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        call namecmp
        pop de
        jr nz,fv1
        ex de,hl
        inc hl
        inc hl
        ret
fv8:    or 1
        ret

; ---------------------------------------------------------------- running

; Run words up to a ] or the end of the text.
runblk: call nexttok
        ld a,b
        or a
        ret z
        ld a,(hl)
        cp ']'
        ret z
        call command
        jr runblk

command:
        ld de,prims
        call lookup
        call findproc
        jp nz,errw

; Call the procedure whose text is at DE.  Each :NAME after its name takes
; a value from the words that follow the call; they are all worked out
; before any is set, then pushed above BP.
callproc:
        ld hl,0
        add hl,sp
        push de
        ld de,STKLIM
        or a
        sbc hl,de
        pop de
        jr c,deep
        ld hl,(BP)
        push hl
        ld hl,0             ; end of the name/value pairs
        push hl
        ex de,hl
        call ptok           ; skip the name
        ex de,hl
cp1:    call ptok
        cp ':'
        jr nz,cp2
        inc hl
        push hl             ; name
        push de             ; rest of the title line
        call expr
        pop de
        ex (sp),hl          ; value under name
        push hl
        ex de,hl
        jr cp1
cp2:    ex de,hl            ; DE = the body
        ld hl,(BP)
cp3:    pop bc
        ld a,b
        or c
        jr z,cp4
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        pop bc
        ld (hl),c
        inc hl
        ld (hl),b
        inc hl
        jr cp3
cp4:    ld (BP),hl
        ld a,h
        cp VTOP/256
        jr nc,deep
        ld hl,(TPV)
        push hl
        ld (TPV),de
        ld hl,(FRAME)
        push hl
        ld (FRAME),sp
        call runblk
pret:   pop hl
        ld (FRAME),hl
        pop hl
        ld (TPV),hl
        pop hl
        ld (BP),hl
        ret

deep:   ld hl,s_deep
        ld b,4
        jp errw
s_deep: db "DEEP"

; Skip to just past the ] that matches a [ already read.
skipblk:
        ld c,1
sb1:    call nexttok
        ld a,b
        or a
        ret z
        ld a,(hl)
        cp '['
        jr nz,sb2
        inc c
sb2:    cp ']'
        jr nz,sb1
        dec c
        jr nz,sb1
        ret

; ---------------------------------------------------------------- sums

; HL = the value of the expression at TPV.  A comparison gives 1 or 0.
expr:   call sum
        call peek
        cp '<'
        jr z,ex1
        cp '='
        jr z,ex1
        cp '>'
        ret nz
ex1:    push hl
        push af
        call nexttok
        call sum
        ex de,hl
        pop af
        pop hl
        cp '='
        jr z,ex3
        cp '<'
        jr z,ex2
        ex de,hl
ex2:    call scmp
        ld hl,0
        ret nc
        inc hl
        ret
ex3:    or a
        sbc hl,de
        ld hl,0
        ret nz
        inc hl
        ret

sum:    call term
su1:    call peek
        cp '+'
        jr z,su2
        cp '-'
        ret nz
        dec b               ; -5 is a new value, not a subtraction
        ret nz
su2:    push hl
        push af
        call nexttok
        call term
        pop af
        pop de
        cp '-'
        call z,neghl
        add hl,de
        jr su1

term:   call factor
te1:    call peek
        cp '*'
        jr z,te2
        cp '/'
        ret nz
te2:    push hl
        push af
        call nexttok
        call factor
        pop af
        pop de
        cp '*'
        jr nz,te3
        call mul16
        jr te1
te3:    ex de,hl
        call sdiv
        jr te1

factor: call nexttok
        ld a,b
        or a
        jp z,err
        ld a,(hl)
        cp '-'
        jr nz,fa0
        dec b
        jr z,fa1            ; - x
        inc hl              ; -5
        call number
        jp neghl
fa0:    cp '('
        jr z,fa2
        cp ':'
        jr z,fa3
        sub '0'
        cp 10
        jr c,number
        ld de,funcs
        call lookup
        call findproc       ; a procedure that OUTPUTs
        jp nz,errw
        call callproc
        ld hl,(RES)
        ret
fa1:    call factor
        jp neghl
fa2:    call expr
        push hl
        call nexttok        ; the )
        pop hl
        ret
fa3:    inc hl
        dec b
        jp z,err
        call findvar
        jp nz,errw
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ret

number: ex de,hl
        ld hl,0
nu1:    ld a,(de)
        sub '0'
        cp 10
        jp nc,err
        push de
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl
        ld e,a
        ld d,0
        add hl,de
        pop de
        inc de
        djnz nu1
        ret

; RANDOM n: 0 to n-1.
random: call factor
        push hl
        ld hl,(SEED)
        ld de,25173
        call mul16
        ld de,13849
        add hl,de
        ld (SEED),hl
        pop de
        ld a,d
        or e
        jp z,err
        ld a,l
        ld l,h
        ld h,a
        res 7,h
        jp udiv

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

; HL = HL / DE, signed, rounding towards zero.
sdiv:   ld a,d
        or e
        jp z,err
        ld a,h
        xor d
        push af
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
        jp neghl

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

; ---------------------------------------------------------------- the turtle

fd:     call expr
        jr move
bk:     call expr
        call neghl

; Move HL steps, drawing a point at each if the pen is down.
move:   push hl
        ld hl,(HEAD)
        call sin
        ld (DX),hl
        ld hl,(HEAD)
        ld de,90
        add hl,de
        call sin            ; the cosine, times 0.6
        bit 7,h
        push af
        call nz,neghl
        ld de,154
        call mul16
        ld l,h
        ld h,0
        pop af
        call nz,neghl
        ld (DY),hl
        pop bc
        bit 7,b
        jr z,mv2
        ld h,b
        ld l,c
        call neghl
        ld b,h
        ld c,l
        ld hl,(DX)
        call neghl
        ld (DX),hl
        ld hl,(DY)
        call neghl
        ld (DY),hl
mv2:    ld a,b
        or c
        ret z
        push bc
        ld hl,(XP)
        ld de,(DX)
        add hl,de
        ld (XP),hl
        ld hl,(YP)
        ld de,(DY)
        add hl,de
        ld (YP),hl
        call plot
        ld a,(DLY)
        or a
        jr z,mv4
mv3:    ex (sp),hl
        ex (sp),hl
        dec a
        jr nz,mv3
mv4:    pop bc
        dec bc
        jr mv2

; HL = 256 * sine of HL degrees (0-449), signed, to within about 1%.
sin:    ld de,360
        or a
        sbc hl,de
        jr nc,sn0
        add hl,de
sn0:    ld de,180
        or a
        sbc hl,de
        push af             ; CY: 0-179, positive
        jr nc,sn1
        add hl,de
sn1:    ex de,hl            ; Bhaskara: sin x = 4t / (40500 - t), t = x(180-x)
        ld hl,180
        or a
        sbc hl,de
        call mul16
        push hl
        ex de,hl
        ld hl,40500+128
        or a
        sbc hl,de
        ld e,h
        ld d,0
        pop hl
        add hl,hl
        add hl,hl
        call udiv
        ld h,b
        ld l,c
        pop af
        ret c
        jp neghl

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If LOGO was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) LOGO.

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
        call nz,erall
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " LOGO",0
        call crlf
        call CLS64
        ld hl,TXT0
        ld (CURS),hl
        ld hl,1
        ld (SEED),hl
        xor a
        ld (DLY),a
        call pendown
        call home

quit:   ld sp,S0
        ld hl,0
        ld (FRAME),hl
        ld hl,VB
        ld (BP),hl
qloop:  ld a,'?'
        call putc
        call accept
        ld hl,TIB
        ld (TPV),hl
        call runblk
        jr qloop

; Unknown word (HL, B characters): print it with " ?" and start again.
err:    ld b,0
errw:   call typen
        call prsi
        db " ?",0
        call crlf
        jr quit

; ERALL: forget every procedure and variable.
erall:  ld hl,newmem
        ld de,MAGIC
        ld bc,8
        ldir
        ret
newmem: dw MAGICV,0,PROC0,VB

; ---------------------------------------------------------------- commands

prims:  db "F",0C4h
        dw fd
        db "B",0CBh
        dw bk
        db "R",0D4h
        dw rt
        db "L",0D4h
        dw lt
        db "P",0D5h
        dw penup
        db "P",0C4h
        dw pendown
        db "P",0C5h
        dw penerase
        db "HOM",0C5h
        dw home
        db "C",0D3h
        dw clear
        db "SET",0C8h
        dw seth
        db "SETX",0D9h
        dw setxy
        db "REPEA",0D4h
        dw repeat
        db "I",0C6h
        dw ifcmd
        db "STO",0D0h
        dw stop
        db "OUTPU",0D4h
        dw output
        db "PRIN",0D4h
        dw print
        db "MAK",0C5h
        dw make
        db "T",0CFh
        dw tocmd
        db "SLO",0D7h
        dw slow
        db "WAI",0D4h
        dw wait
        db "ERAL",0CCh
        dw erall
        db 0

funcs:  db "RANDO",0CDh
        dw random
        db 0

lt:     call expr
        call neghl
        jr turn
rt:     call expr
turn:   ld de,(HEAD)
        add hl,de
seth1:  ld de,360
tu1:    bit 7,h
        jr z,tu2
        add hl,de
        jr tu1
tu2:    or a
        sbc hl,de
        jr nc,tu2
        add hl,de
        ld (HEAD),hl
        ret
seth:   call expr
        jr seth1

penup:     xor a
        jr setpen
pendown:     ld a,1
        jr setpen
penerase:     ld a,2
setpen:    ld (PEN),a
        ret

clear:     ld hl,VRAM+40h
        ld de,VRAM+41h
        ld bc,26*64-1
        ld (hl),20h
        ldir
home:   ld hl,80h           ; half a point: the middle of one
        ld (XP),hl
        ld (YP),hl
        ld l,h
        ld (HEAD),hl
        ret

; SETXY x y: move there without drawing.
setxy:  call expr
        push hl
        call expr
        ld de,154
        call mul16
        ld de,80h
        add hl,de
        ld (YP),hl
        pop hl
        ld h,l
        ld l,80h
        ld (XP),hl
        ret

; REPEAT n [ ... ]
repeat: call expr
        push hl
        call nexttok        ; the [
        pop bc
        ld hl,(TPV)
rp1:    ld (TPV),hl
        ld a,b
        or c
        jp z,skipblk
        bit 7,b
        jp nz,skipblk
        push hl
        push bc
        call runblk
        pop bc
        pop hl
        dec bc
        jr rp1

; IF test [ ... ], or IF test [ ... ] [ ... ]
ifcmd:     call expr
        ld a,h
        or l
        push af
        call nexttok        ; the [
        pop af
        jr z,if2
        call runblk
        call peek
        cp '['
        ret nz
        call nexttok
        jp skipblk
if2:    call skipblk
        call peek
        cp '['
        ret nz
        call nexttok
        jp runblk

; OUTPUT x: leave the procedure with x as its value.
output: call expr
        ld (RES),hl
stop:   ld hl,(FRAME)
        ld a,h
        or l
        ret z
        ld sp,hl
        jp pret

; PRINT x, PRINT "WORD or PRINT [ ANY WORDS ]
print:  call peek
        cp '['
        jr z,pr2
        cp '"'
        jr z,pr1
        call expr
        call dot
        jp crlf
pr1:    call nexttok
        inc hl
        dec b
        call typen
        jp crlf
pr2:    call nexttok
        ld hl,(TPV)
pr3:    ld a,(hl)
        cp ' '
        jr nz,pr4
        inc hl
        jr pr3
pr4:    ld a,(hl)
        or a
        jr z,pr9
        inc hl
        cp ']'
        jr z,pr9
        call putc
        jr pr4
pr9:    ld (TPV),hl
        jp crlf

; MAKE "NAME x: set the newest variable called NAME, or make a global one.
make:   call nexttok
        ld a,(hl)
        cp '"'
        jp nz,errw
        inc hl
        dec b
        jp z,err
        push hl
        push bc
        call expr
        ex de,hl
        pop bc
        pop hl
        push de
        call findvar
        jr z,mk9
        ld de,(HERE)        ; a new global: keep its name with the procedures
        push de
mk1:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz mk1
        ld a,' '
        ld (de),a
        inc de
        ld (HERE),de
        pop de
        ld hl,(GP)
        dec hl
        dec hl
        dec hl
        dec hl
        ld (GP),hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
mk9:    pop de
        ld (hl),e
        inc hl
        ld (hl),d
        ret

; TO NAME :INPUT ... END: keep the words up to END, over as many lines as
; it takes.
tocmd:     ld de,(HERE)
        inc de
        inc de
to1:    call nexttok
        ld a,b
        or a
        jr z,to5
        push de
        ld de,s_end
        call namecmp
        pop de
        jr z,to6
to2:    ld a,(hl)
        ld (de),a
        inc hl
        inc de
        djnz to2
        ld a,' '
        ld (de),a
        inc de
        jr to1
to5:    push de
        ld a,'>'
        call putc
        call accept
        ld hl,TIB
        ld (TPV),hl
        pop de
        jr to1
to6:    xor a
        ld (de),a
        inc de
        ld hl,(HERE)
        ld bc,(LATEST)
        ld (hl),c
        inc hl
        ld (hl),b
        dec hl
        ld (LATEST),hl
        ld (HERE),de
        ret
s_end:  db "END",0

; WAIT n: n sixtieths of a second.
wait:   call expr
wa1:    ld a,h
        or l
        ret z
        ld bc,2560
wa2:    dec bc
        ld a,b
        or c
        jr nz,wa2
        dec hl
        jr wa1

; SLOW n: a pause at every step, 0 (none) to 255.
slow:   call expr
        ld a,l
        ld (DLY),a
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

; Read a line into TIB, echoing it, and end it with a 0.  Changes DE.
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
ac9:    xor a
        ld (de),a

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

; Print character A, in ASCII.  Keeps everything but AF.
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

; CURS = HL, scrolling lines 27-31 up if HL has run off the end.
fixcur: ld a,h
        cp 88h
        jr c,fc9
        push bc
        push de
        ld hl,TXT0+40h
        ld de,TXT0
        ld bc,4*64
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
ps1:    ld a,(hl)
        inc hl
        or a
        jr z,ps2
        call putc
        jr ps1
ps2:    ex (sp),hl
        ret

; Print B characters from HL.
typen:  inc b
ty1:    dec b
        ret z
        ld a,(hl)
        inc hl
        call putc
        jr ty1

; Print HL, signed.
dot:    bit 7,h
        jr z,udot
        ld a,'-'
        call putc
        call neghl
udot:   ld de,10
        call udiv
        push hl
        ld h,b
        ld l,c
        ld a,h
        or l
        call nz,udot
        pop hl
        ld a,l
        add a,'0'
        jp putc

; Draw (or rub out) the point under the turtle, if it is on the field.
plot:   ld a,(PEN)
        or a
        ret z
        ld a,(XP+1)
        add a,64
        cp 128
        ret nc
        ld c,a              ; across, 0-127
        ld a,(YP+1)
        neg
        add a,25
        cp 52
        ret nc
        ld b,a              ; down, 0-51
        srl a
        ld l,a
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
        ld de,VRAM+40h
        add hl,de
        ld a,b
        and 1
        add a,a
        ld e,a
        ld a,c
        and 1
        or e
        ld e,a
        ld d,0
        push hl
        ld hl,qbits
        add hl,de
        ld e,(hl)
        pop hl
        ld a,(hl)
        ld d,a
        and 0F0h
        cp 40h
        ld a,d
        jr z,pl3
        ld a,40h            ; not a graphics character: start empty
pl3:    ld d,a
        ld a,(PEN)
        dec a
        ld a,d
        jr nz,pl4
        or e
        jr pl5
pl4:    ld a,e
        cpl
        and d
pl5:    cp 40h
        jr nz,pl6
        ld a,20h
pl6:    ld (hl),a
        ret
qbits:  db 1,2,8,4          ; top left, top right, bottom left, bottom right

rom_end:
        ds 0C00h-$,0FFh
