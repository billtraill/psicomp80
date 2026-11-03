; COMP80 BEFUNGE
;
; Befunge-93 for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that held
; BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS key
; enters it: the monitor's NMI handler jumps to 0800h.
;
; The program is the screen: lines 1-24 are the 64 x 24 playfield, which
; wraps round at its edges, and the instruction pointer runs over the
; characters you can see.  G and P read and write those same characters, so
; a program that changes itself changes on the screen.  Line 0 shows BEFUNGE
; and, after STEP, where the pointer is and the top of the stack; lines 25-31
; are for commands and the program's output, and scroll by themselves.
;
; Commands:
;   Y X TEXT   put TEXT on line Y (0-23) of the playfield from column X
;              (0-63); exactly one space after X, then TEXT as it stands
;   EDIT Y X   type straight onto the playfield from there: Return goes to
;              the next line, RS steps back, Return on a line where nothing
;              has been typed ends
;   RUN        run from the top left corner, going right, with an empty stack
;   STEP       do one instruction, show the pointer and the stack
;   SPEED N    wait N (0-255) between instructions, showing the pointer as a
;              block; 0 runs flat out
;   CLEAR      blank the playfield
;
; The keyboard can't type ^ _ or \, and the screen has no | ` or ~, so:
;   type '  for ^ (up)       = for _ (horizontal if)     ; for \ (swap)
;   I is | (vertical if),  ) is ` (greater than),  ( is ~ (read a character)
;   and G P V are g p v.  ' = and ; are turned into ^ _ and \ as they are
;   typed, in strings too.
;
; Cells hold a byte.  A cell's value is its character's ASCII code: the
; screen codes 00h-1Fh (@ A-Z [ \ ] ^ _) are ASCII 40h-5Fh and 20h-3Fh are
; themselves; the other values, 00h-1Fh and 60h-FFh, show as graphics.
; Numbers on the stack are 16-bit.  Division by 0 gives 0.
;
; Keys and screen are as in FORTH: the monitor's NMI handler echoes each key
; at (DE); RS while waiting for a key is rubout; any key while a program runs
; resets to the monitor, and RS comes back with the playfield kept.

MAGIC:  equ 0C00h           ; MAGICV once set up
IPX:    equ 0C02h           ; pointer column
IPY:    equ 0C03h           ; pointer line
DX:     equ 0C04h           ; direction across: 1, 0 or -1
DY:     equ 0C05h           ; direction down
STRM:   equ 0C06h           ; not 0 in string mode
HALTED: equ 0C07h           ; not 0 once the program has ended
SPEED:  equ 0C08h
SEED:   equ 0C0Ah           ; random number seed
BSP:    equ 0C0Ch           ; Befunge stack pointer
MARKA:  equ 0C0Eh           ; cell showing the pointer, or 0
MARKC:  equ 0C10h           ; what is really in it
EDX:    equ 0C11h           ; EDIT: column, line, first column,
EDY:    equ 0C12h           ;   and whether anything was typed on the line
EDX0:   equ 0C13h
EDN:    equ 0C14h
TCURS:  equ 0C16h           ; the text cursor while editing
STK0:   equ 0C20h           ; Befunge stack, up to 1C00h
STKEH:  equ 1Ch
MAGICV: equ 0BEF9h

TIB:    equ 1D00h           ; input line (80 bytes)
CURS:   equ 1DA0h           ; output position in screen memory
S0:     equ 1F00h           ; machine stack (the monitor uses 1Fxx)

VRAM:   equ 8000h
GRID:   equ 8040h           ; the playfield, lines 1-24
TEXT:   equ 8640h           ; lines 25-31
MARK:   equ 4Fh             ; a solid block shows the pointer
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

; Print character A (ASCII 20h-5Fh), or with PUTRAW screen code A.  Keeps
; everything but AF.
putc:   cp 40h
        jr c,putraw
        and 1Fh
putraw: push hl
        ld hl,(CURS)
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

; CURS = HL, scrolling lines 25-31 up if HL has run off the end.
fixcur: ld a,h
        cp 88h
        jr c,fc9
        push bc
        push de
        ld hl,TEXT+40h
        ld de,TEXT
        ld bc,180h
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
pr1:    ld a,(hl)
        inc hl
        or a
        jr z,pr9
        call putc
        jr pr1
pr9:    ex (sp),hl
        ret

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

; Blank from HL for BC + 1 bytes.
blank:  ld d,h
        ld e,l
        inc de
        ld (hl),' '
        ldir
        ret

clstext: ld hl,TEXT
        ld bc,1BFh
        call blank
        ld hl,TEXT
        ld (CURS),hl
        ret

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

; ---------------------------------------------------------------- the stack

; Push HL.  Keeps HL, DE.
push:   push de
        ex de,hl
        ld hl,(BSP)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (BSP),hl
        ld a,h
        cp STKEH
        jr nc,full
        ex de,hl
        pop de
        ret
full:   ld a,1
        ld (HALTED),a
        call prsi
        db "STACK FULL",0
        jp stopped

; HL = the top of the stack, taken off; 0 if it is empty.  Keeps DE.
pop:    push de
        ld hl,(BSP)
        ld de,STK0
        or a
        sbc hl,de
        jr z,po9
        add hl,de
        dec hl
        ld d,(hl)
        dec hl
        ld e,(hl)
        ld (BSP),hl
        ex de,hl
po9:    pop de
        ret

; DE = the top of the stack, HL = the one below, both taken off.
pop2:   call pop
        ex de,hl
        jr pop

; ---------------------------------------------------------------- playfield

; HL = the cell at column C, line B.  Keeps BC, DE.
cella:  push de
        ld h,0
        ld l,b
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        ld a,l
        or c
        ld l,a
        ld de,GRID
        add hl,de
        pop de
        ret

; ASCII value <-> screen code: 00h-1Fh and 40h-5Fh change places.
swap40: cp 60h
        ret nc
        cp 20h
        jr c,sw1
        cp 40h
        ret c
        sub 40h
        ret
sw1:    add a,40h
        ret

; Screen code for typed key A: ' = ; are ^ _ \.
entc:   cp 27h
        jr nz,en1
        ld a,5Eh
en1:    cp '='
        jr nz,en2
        ld a,5Fh
en2:    cp ';'
        jr nz,swap40
        ld a,5Ch
        jr swap40

; Show the pointer at HL as a block, keeping what is there.
markhl: ld (MARKA),hl
        ld a,(hl)
        ld (MARKC),a
        ld (hl),MARK
        ret

; Put back the cell under the pointer's block, if one is showing.  Keeps HL.
unmark: push hl
        ld hl,(MARKA)
        ld a,h
        or l
        jr z,um9
        ld a,(MARKC)
        ld (hl),a
        ld hl,0
        ld (MARKA),hl
um9:    pop hl
        ret

; ---------------------------------------------------------------- running

; Start again at the top left, going right, with an empty stack.
reset:  xor a
        ld (IPX),a
        ld (IPY),a
        ld (STRM),a
        ld (HALTED),a
        ld hl,1
        ld (DX),hl
        ld hl,STK0
        ld (BSP),hl
        ld hl,(SEED)
        ld a,r
        xor l
        ld l,a
        or h
        jr nz,re1
        inc l
re1:    ld (SEED),hl
        ret

; Do one instruction.  CY once the program has ended.
step1:  call ipcell
        ld a,(SPEED)
        or a
        jr z,st1
        call markhl
        ld a,(SPEED)
        ld b,a
dl1:    push bc
        ld b,0
dl2:    djnz dl2
        pop bc
        djnz dl1
        call unmark
st1:    ld a,(hl)
        call swap40
        ld e,a
        ld a,(STRM)
        or a
        jr z,st3
        ld a,e
        cp '"'
        jr z,st2
        ld l,e
        ld h,0
        call push
        jr move
st2:    xor a
        ld (STRM),a
        jr move
st3:    ld a,e
        cp ' '
        jr z,move           ; a space does nothing, and there are many
        sub '0'
        cp 10
        jr nc,st4
        ld l,a
        ld h,0
        call push
        jr move
st4:    ld a,e
        ld hl,cmds
        ld bc,NCMDS
        cpir
        jr nz,move          ; not an instruction: nothing
        ld hl,NCMDS-1
        or a
        sbc hl,bc
        add hl,hl
        ld de,jtab
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call jphl
; Move the pointer one step, wrapping round.  NC.
move:   ld hl,(DX)
        ld a,(IPX)
        add a,l
        and 63
        ld (IPX),a
        ld a,(IPY)
        add a,h
        cp 24
        jr c,mv1
        inc a
        ld a,0
        jr nz,mv1
        ld a,23
mv1:    ld (IPY),a
        or a
        ret

jphl:   jp (hl)

; HL = the cell under the pointer.
ipcell: ld a,(IPY)
        ld b,a
        ld a,(IPX)
        ld c,a
        jp cella

cmds:   db "+-*/%!",60h,")><^vV?_",7Ch,"I",22h,":",5Ch,"$.,#gGpP&",7Eh,"(@"
NCMDS:  equ $-cmds
jtab:   dw i_add,i_sub,i_mul,i_div,i_mod,i_not,i_gt,i_gt,i_right,i_left
        dw i_up,i_down,i_down,i_rand,i_hif,i_vif,i_vif,i_quote,i_dup,i_swap
        dw pop,i_dot,i_chr,move,i_get,i_get,i_put,i_put,i_inum,i_ichr,i_ichr
        dw i_end

i_add:  call pop2
        add hl,de
        jp push
i_sub:  call pop2
        or a
        sbc hl,de
        jp push
i_mul:  call pop2
        call mul16
        jp push
i_div:  call pop2
        call sdiv
        ld h,b
        ld l,c
        jp push
i_mod:  call pop2
        call sdiv
        jp push
i_not:  call pop
        ld a,h
        or l
i_flag: ld hl,0
        jp nz,push
        inc l
        jp push
i_gt:   call pop2           ; 1 if HL > DE
        ex de,hl
        call scmp
        ccf
        sbc a,a             ; 0 if HL < DE...
        jr i_flag
i_right: ld hl,1
        jr sdir
i_left: ld hl,0FFh
        jr sdir
i_up:   ld hl,0FF00h
        jr sdir
i_down: ld hl,100h
sdir:   ld (DX),hl
        ret
i_rand: call rnd
        ld a,l
        and 3
        jr z,i_right
        dec a
        jr z,i_left
        dec a
        jr z,i_up
        jr i_down
i_hif:  call pop
        ld a,h
        or l
        jr z,i_right
        jr i_left
i_vif:  call pop
        ld a,h
        or l
        jr z,i_down
        jr i_up
i_quote: ld a,1
        ld (STRM),a
        ret
i_dup:  call pop
        call push
        jp push
i_swap: call pop2
        ex de,hl
        call push
        ex de,hl
        jp push
i_dot:  call pop
        call dot
        ld a,' '
        jp putc
i_chr:  call pop
        ld a,l
        cp 10
        jp z,crlf
        call swap40
        jp putraw

; HL = the cell at x, y taken off the stack; CY if off the playfield.
gpos:   call pop2           ; DE = y, HL = x
        ld a,h
        or d
        jr nz,gp9
        ld a,l
        cp 64
        jr nc,gp9
        ld c,a
        ld a,e
        cp 24
        jr nc,gp9
        ld b,a
        call cella
        or a
        ret
gp9:    scf
        ret
i_get:  call gpos
        ld a,0
        jr c,ig1
        ld a,(hl)
        call swap40
ig1:    ld l,a
        ld h,0
        jp push
i_put:  call gpos
        push hl
        push af
        call pop
        ld a,l
        call swap40
        ld e,a
        pop af
        pop hl
        ret c
        ld (hl),e
        ret
i_inum: ld de,TIB
        call accept
        ld hl,TIB
        call skipsp
        ld a,(hl)
        cp '-'
        push af
        jr nz,in1
        inc hl
in1:    call getnum
        ex de,hl
        pop af
        call z,neghl
        jp push
i_ichr: ld a,1Fh
        call rawkey
        cp 0Dh
        jr nz,ic1
        call crlf
        ld a,10
        jr ic2
ic1:    cp 8
        jr z,ic2
        push af
        call putc
        pop af
ic2:    ld l,a
        ld h,0
        jp push
i_end:  ld a,1
        ld (HALTED),a
        pop hl              ; leave STEP1 straight away, with CY
        scf
        ret

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If BEFUNGE was
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

warm:   ld sp,S0
        ld hl,(MAGIC)
        ld de,MAGICV
        or a
        sbc hl,de
        call nz,cold
        call unmark
        ld hl,VRAM
        ld bc,3Fh
        call blank
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " BEFUNGE",0
        call clstext

main:   ld sp,S0
        ld de,TIB
        call accept
        call unmark
        ld hl,TIB
        call skipsp
        ld a,(hl)
        or a
        jr z,main
        sub '0'
        cp 10
        jr c,putl
        ld a,(hl)
        cp 'R'
        jr z,runc
        cp 'C'
        jr z,clearc
        cp 'E'
        jr z,editc
        cp 'S'
        jr nz,what
        inc hl
        ld a,(hl)
        cp 'T'
        jr z,stepc
        cp 'P'
        jr z,speedc
what:   call prsi
        db "?",0
        call crlf
        jr main

; Y X TEXT: put TEXT on the playfield.
putl:   call getyx
        jr c,what
        ld a,(hl)
        or a
        jr z,main
        cp ' '
        jr nz,what
        inc hl
pl1:    ld a,(hl)
        or a
        jr z,main
        inc hl
        push hl
        call entc
        ld e,a
        call cella
        ld (hl),e
        pop hl
        inc c
        ld a,c
        cp 64
        jr c,pl1
        jr main

runc:   call reset
ru1:    call step1
        jr nc,ru1
; The program has stopped: end the line it was printing.
stopped: ld a,(CURS)
        and 3Fh
        call nz,crlf
        jr main

clearc: call cold1
        jr main

speedc: call skipw
        call getnum
        ld a,e
        ld (SPEED),a
        jp main

stepc:  ld a,(HALTED)
        or a
        call nz,reset
        call step1
        call status
        ld a,(HALTED)
        or a
        jp nz,main
        call ipcell
        call markhl
        jp main

; EDIT Y X: type onto the playfield.
editc:  call skipw
        call getyx
        jr c,what
        ld a,c
        ld (EDX),a
        ld (EDX0),a
        ld a,b
        ld (EDY),a
        ld hl,(CURS)
        ld (TCURS),hl
ed0:    xor a
        ld (EDN),a
ed1:    ld a,(EDY)
        ld b,a
        ld a,(EDX)
        ld c,a
        call cella
        ld (CURS),hl
        ld a,1Fh
        call rawkey
        cp 0Dh
        jr z,ed3
        cp 8
        jr z,ed2
        call entc
        ld (hl),a
        ld a,1
        ld (EDN),a
        ld a,c
        inc a
        cp 64
        jr nc,ed1
        ld (EDX),a
        jr ed1
ed2:    ld a,c
        or a
        jr z,ed1
        dec a
        ld (EDX),a
        jr ed1
ed3:    ld a,(EDN)
        or a
        jr z,ed9
        ld a,(EDX0)
        ld (EDX),a
        ld a,(EDY)
        inc a
        ld (EDY),a
        cp 24
        jr c,ed0
ed9:    ld hl,(TCURS)
        ld (CURS),hl
        jp main

; Set up from nothing: an empty playfield.
cold:   ld hl,MAGICV
        ld (MAGIC),hl
        xor a
        ld (SPEED),a
        ld h,a
        ld l,a
        ld (MARKA),hl
        inc l
        ld (SEED),hl
cold1:  ld hl,GRID
        ld bc,5FFh
        call blank
        ld a,1
        ld (HALTED),a
        ret

; After STEP: on line 0, where the pointer is and the top of the stack, or
; END.
status: ld hl,(CURS)
        push hl
        ld hl,VRAM+9
        ld (CURS),hl
        ld a,(HALTED)
        or a
        jr z,sa1
        call prsi
        db "END",0
        jr sa8
sa1:    call prsi
        db "X ",0
        ld a,(IPX)
        call dota
        call prsi
        db " Y ",0
        ld a,(IPY)
        call dota
        call prsi
        db "  STACK",0
        ld hl,(BSP)
        ld b,5
sa2:    push hl
        ld de,STK0
        or a
        sbc hl,de
        pop hl
        jr z,sa8
        dec hl
        ld d,(hl)
        dec hl
        ld e,(hl)
        push hl
        ld a,' '
        call putc
        ex de,hl
        call dot
        pop hl
        djnz sa2
sa8:    ld hl,(CURS)
sa9:    ld a,l
        cp 40h
        jr nc,sa10
        ld (hl),' '
        inc hl
        jr sa9
sa10:   pop hl
        ld (CURS),hl
        ret

dota:   ld l,a
        ld h,0
        jp dot

; ---------------------------------------------------------------- reading

skipsp: ld a,(hl)
        cp ' '
        ret nz
        inc hl
        jr skipsp

; Skip a word of letters.
skipw:  ld a,(hl)
        cp 'A'
        ret c
        inc hl
        jr skipw

; DE = the number at HL, after spaces; CY if there is none.  HL ends past it.
getnum: call skipsp
        ld de,0
        ld a,(hl)
        sub '0'
        cp 10
        ccf
        ret c
gn1:    ld a,(hl)
        sub '0'
        cp 10
        jr nc,gn9
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
        jr gn1
gn9:    or a
        ret

; B = a line (0-23) and C = a column (0-63) read from HL; CY if not.
getyx:  call getnum
        ret c
        ld a,d
        or a
        scf
        ret nz
        ld a,e
        cp 24
        ccf
        ret c
        ld b,a
        call getnum
        ret c
        ld a,d
        or a
        scf
        ret nz
        ld a,e
        cp 64
        ccf
        ld c,a
        ret

; HL = a new random number (xorshift).
rnd:    ld hl,(SEED)
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

; BC = HL / DE and HL = the remainder, signed, rounding towards zero; both
; 0 if DE is 0.
sdiv:   ld a,d
        or e
        jr nz,sd1
        ld h,a
        ld l,a
        ld b,a
        ld c,a
        ret
sd1:    ld a,h
        push af             ; sign of the remainder
        xor d
        push af             ; sign of the quotient
        bit 7,h
        call nz,neghl
        ex de,hl
        bit 7,h
        call nz,neghl
        ex de,hl
        call udiv
        pop af
        or a
        jp p,sd2
        push hl
        ld h,b
        ld l,c
        call neghl
        ld b,h
        ld c,l
        pop hl
sd2:    pop af
        or a
        ret p
        jp neghl

part2_end:
        ds 0C00h-$,0FFh
