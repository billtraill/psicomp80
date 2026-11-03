; COMP80 MOUSE
;
; Mouse, Peter Grogono's little stack language (BYTE, July 1979), for the PSI
; COMP80, in the 2 KB of ROM (0400h-0BFFh) that held BURP.  The monitor
; (0000h-03FFh) is unchanged.  As with BURP, the RS key enters it: the
; monitor's NMI handler jumps to 0800h.  It is new, written from scratch.
;
; A line starting with a digit is a program line: its number orders it and
; a number on its own deletes it.  LIST, RUN and NEW work on the program;
; any other line runs at once (start it with a space if it begins with a
; number).  The program's lines run as one stream of text, the line numbers
; left out, and it ends at $ or $$; macro definitions follow.
;
;   0-9    push a number               A-Z  push a variable's address
;   :      store (value addr :)        .    fetch (addr .)
;   + - * /  arithmetic, % remainder   < = >  compare, giving 1 or 0
;   !      print a number              !'   print a character
;   !.     plot point x y (x < 0 clears the screen)
;   ?      read a number               ?'   read a character
;   ?.     random number from 1 to the number on the stack
;   "TEXT" print TEXT, ! in it a new line
;   'C     push the character C        [ .. ]  do it if the number is > 0
;   ( .. )  loop                       &    leave the loop if the number is <= 0
;   #A,P1,P2;  call macro A           $A .. @  define macro A
;   %1 .. %9   a macro's parameters    $ or $$  end of the program
;
; ^ (the RS key), \ and _ can't be typed on the COMP80, so the loop's
; ^ is & here and remainder (\) is % (when not followed by a digit).  ~
; can't be typed either, so there are no comments.
;
; Memory is 768 16-bit words.  A letter is address 0-25 plus OFFSET, which
; goes up by 26 for each macro call, so each call has its own variables;
; the words above those used by the calls make arrays.
;
; Frames on the control stack (IY), 8 bytes each: type ('L' loop, 'M'
; macro, 'P' parameter), 0, position to go back to, the macro call's
; position (M), OFFSET to go back to.  IX is the data stack.
;
; Keys and screen are as in FORTH: the monitor's NMI handler echoes each key
; at (DE); RS while waiting for a key is rubout; any key while a program runs
; resets to the monitor and RS comes back with the program kept.  Line 0
; shows MOUSE, lines 1-31 scroll.

MAGIC:  equ 0C00h           ; MAGICV when the program below is valid
PEND:   equ 0C02h           ; end of the program
SEED:   equ 0C04h           ; random number seed
PROG:   equ 0C06h           ; first program line: number (2), length (1), text, 0
PTOP:   equ 1400h           ; the program must end below here
MAGICV: equ 0A0C5h

MEM:    equ 1400h           ; 768 words
MEMW:   equ 768
DSTK:   equ 1A00h           ; data stack, 64 words (page aligned)
ESTK0:  equ 1A80h           ; a frame of type 0 below the control stack
ESTK:   equ 1A88h           ; control stack frames
ESTKE:  equ 1D00h
TIB:    equ 1D10h           ; input line (80 bytes)
ANS:    equ 1D60h           ; line read by ? (32 bytes)
CURS:   equ 1DA0h           ; output position in screen memory
POS:    equ 1DA2h           ; next character of the program to run
OFFSET: equ 1DA4h           ; variables of the macro call running
DEFS:   equ 1DB0h           ; where each macro's text starts, 26 words
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
        jp z,e_div
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
        jp nc,e_full
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

; ---------------------------------------------------------------- the program text
; Positions run through the program's lines as one stream: the 0 at the end
; of a line reads as a space, and the next line's number and length are
; skipped.  Past the last line (or the end of a line typed to run at once)
; the character is 0.

; A = the next character, HL = the position after it.
peekch: ld hl,(POS)
        ld a,(hl)
        inc hl
        or a
        ret nz
        call before         ; past the end of the program?
        jr nc,pk9
        inc hl
        inc hl
        inc hl
        ld a,' '
        ret
pk9:    dec hl
        xor a
        ret

; A = the next character, and move past it.
getch:  call peekch
        ld (POS),hl
        ret

; A = the next character, skipping over a string or 'C whole (A is then "
; or ').  0 at the end.
scanch: call getch
        cp 27h
        jr z,getch1
        cp '"'
        ret nz
sc1:    call getch
        or a
        jp z,e_end
        cp '"'
        jr nz,sc1
        ret
getch1: call getch
        ld a,27h
        ret

; Skip to the character B that closes the one just read, C opening another;
; strings and 'C are skipped whole.
skipto: ld e,1
sk1:    call scanch
        or a
        jp z,e_end
        cp c
        jr nz,sk4
        inc e
        jr sk1
sk4:    cp b
        jr nz,sk1
        dec e
        jr nz,sk1
        ret

; Find each $A in the program and keep where its text starts in DEFS.
defscan:
        ld hl,DEFS
        ld b,52
ds0:    ld (hl),0
        inc hl
        djnz ds0
        call start
        ret z
ds1:    call scanch
        or a
        ret z
        cp '$'
        jr nz,ds1
        call peekch
        sub 'A'
        cp 26
        jr nc,ds1
        ld (POS),hl
        ex de,hl
        call defa
        ld (hl),e
        inc hl
        ld (hl),d
        jr ds1

; ---------------------------------------------------------------- stacks

; Push HL on the data stack.
dpush:  ld (ix+0),l
        ld (ix+1),h
        inc ix
        inc ix
        push hl
        push ix
        pop hl
        ld a,l
        cp 80h
        pop hl
        ret c
        jr e_stk

; HL = the number popped from the data stack.
dpop:   push ix
        pop hl
        ld a,l
        or a
        jr z,e_stk
        dec ix
        dec ix
        ld l,(ix+0)
        ld h,(ix+1)
        ret

; HL = the second number, DE = the top one.
pop2:   call dpop
        ex de,hl
        jr dpop

; Push a frame of type A, going back to BC, with DE the macro call.
pushf:  ld (iy+0),a
        ld (iy+2),c
        ld (iy+3),b
        ld (iy+4),e
        ld (iy+5),d
        ld hl,(OFFSET)
        ld (iy+6),l
        ld (iy+7),h
        ld de,8
        add iy,de
        push iy
        pop hl
        ld de,ESTKE
        or a
        sbc hl,de
        ret c
        call err
        db "NESTED",0

; Pop the top frame and go back to where it says.
popf:   ld de,-8
        add iy,de
        ld l,(iy+2)
        ld h,(iy+3)
        ld (POS),hl
        ld l,(iy+6)
        ld h,(iy+7)
        ld (OFFSET),hl
        ret

; HL = the address of word HL of memory.
addr:   push de
        ld de,MEMW
        push hl
        or a
        sbc hl,de
        pop hl
        pop de
        jr nc,e_addr
        add hl,hl
        ld a,h
        add a,MEM/256
        ld h,a
        ret

; ---------------------------------------------------------------- errors

e_stk:  call err
        db "STACK",0
e_addr: call err
        db "ADDRESS",0
e_div:  call err
        db "DIVIDE",0
e_end:  call err
        db "MISSING",0
e_full: call err
        db "FULL",0

; Print the message after the CALL, a ? and the line it was in, and stop.
err:    call crlf0
        pop hl
        call puts
        ld a,'?'
        call putc
        ld de,(POS)
        ld hl,PROG
er1:    call before
        jr nc,er9
        ld b,h
        ld c,l
        call nextrec
        push hl
        or a
        sbc hl,de
        pop hl
        jr z,er1
        jr c,er1
        call prsi
        db " IN ",0
        ld a,(bc)
        ld l,a
        inc bc
        ld a,(bc)
        ld h,a
        call udot
er9:    call crlf
        ld ix,DSTK
        jp main

; A new line unless at the start of one.
crlf0:  ld a,(CURS)
        and 3Fh
        ret z
        jp crlf

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If MOUSE was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) MOUSE.
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
        ld ix,DSTK
        ld hl,(MAGIC)
        ld de,MAGICV
        or a
        sbc hl,de
        call nz,new
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " MOUSE",0
        call crlf
        call cls
main:   ld sp,S0
        ld iy,ESTK
        xor a
        ld (ESTK0),a
        ld de,TIB
        call accept
        ld de,TIB
        call isdig
        jp c,edit
        call skipsp
        ld hl,s_list
        call kw
        jr z,list
        ld hl,s_run
        call kw
        jr z,runc
        ld hl,s_new
        call kw
        jr z,newc
        push de
        call defscan
        pop hl
        ld (POS),hl
        jr go0

runc:   ld ix,DSTK
        ld hl,MEM
        ld de,MEM+1
        ld bc,MEMW*2-1
        ld (hl),0
        ldir
        call defscan
        call start
        jr z,main
go0:    ld hl,0
        ld (OFFSET),hl
        jr exec

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

; HL = DEFS + 2A.
defa:   add a,a
        ld hl,DEFS
        add a,l
        ld l,a
        ret

; POS = the start of the program; Z if there is none.
start:  ld hl,(PEND)
        ld de,PROG
        or a
        sbc hl,de
        ret z
        ld hl,PROG+3
        ld (POS),hl
        ret

; ---------------------------------------------------------------- running

; The end of the program, or of the line typed.
done:   call crlf0
        jp main

; Run the program from POS, a character at a time.
exec:   ld hl,exec
        push hl
        call getch
        or a
        jr z,done
        cp ' '
        ret z
        ld c,a
        sub '0'
        cp 10
        jr c,num
        ld a,c
        sub 'A'
        cp 26
        jr c,var
        ld hl,optab
ex1:    ld a,(hl)
        inc hl
        or a
        jr z,ex2
        cp c
        jr z,ex3
        inc hl
        inc hl
        jr ex1
ex2:    call err                ; not a Mouse character
        db "WHAT",0
ex3:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)

; A number: its digits.
num:    ld l,a
        ld h,0
nu1:    push hl
        call peekch
        sub '0'
        cp 10
        jr nc,nu2
        ld (POS),hl
        pop hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        add hl,hl
        ld e,a
        ld d,0
        add hl,de
        jr nu1
nu2:    pop hl
        jp dpush

; A variable: its address in this macro call's set.
var:    ld hl,(OFFSET)
        ld e,a
        ld d,0
        add hl,de
        jp dpush

optab:  db '+'
        dw op_add
        db '-'
        dw op_sub
        db '*'
        dw op_mul
        db '/'
        dw op_div
        db '%'
        dw op_pct
        db '<'
        dw op_lt
        db '='
        dw op_eq
        db '>'
        dw op_gt
        db ':'
        dw op_store
        db '.'
        dw op_fetch
        db '!'
        dw op_print
        db '?'
        dw op_read
        db '"'
        dw op_str
        db 27h
        dw op_char
        db '['
        dw op_if
        db ']'
        dw op_nop
        db '('
        dw op_loop
        db ')'
        dw op_again
        db '&'
        dw op_leave
        db '#'
        dw op_call
        db '@'
        dw op_ret
        db ','
        dw op_endp
        db ';'
        dw op_endp
        db '$'
        dw done
        db 0

op_add: call pop2
        add hl,de
        jp dpush
op_sub: call pop2
        or a
        sbc hl,de
        jp dpush
op_mul: call pop2
        call mul16
        jp dpush
op_div: call pop2
        ld b,h
        ld c,l
        ex de,hl
        call sdiv
        jp dpush

; % followed by a digit is a parameter; on its own, the remainder.
op_pct: call peekch
        sub '1'
        cp 9
        jp c,param
        call pop2
        push hl
        push de
        ld b,h
        ld c,l
        ex de,hl
        call sdiv           ; HL = a / b
        pop de
        call mul16          ; HL = (a / b) * b
        ex de,hl
        pop hl
        or a
        sbc hl,de
        jp dpush

op_lt:  call pop2
        call scmp
        jr flag
op_gt:  call pop2
        ex de,hl
        call scmp
        jr flag
op_eq:  call pop2
        or a
        sbc hl,de
        scf
        jr z,flag
        or a
flag:   ld hl,0
        rl l
        jp dpush

op_store:
        call dpop
        call addr
        push hl
        call dpop
        ex de,hl
        pop hl
        ld (hl),e
        inc hl
        ld (hl),d
op_nop: ret
op_fetch:
        call dpop
        call addr
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp dpush

; ! prints a number, !' a character, !. plots a point.
op_print:
        call peekch
        cp 27h
        jr z,pr1
        cp '.'
        jp z,plot
        call dpop
        jp dot
pr1:    ld (POS),hl
        call dpop
        ld a,l
        jp putc

; ? reads a number, ?' a character; ?. is a random number.
op_read:
        call peekch
        cp 27h
        jr z,rd1
        cp '.'
        jr z,rd2
        ld de,ANS
        call accept
        ld de,ANS
        call signum
        jp dpush
rd1:    ld (POS),hl
        ld a,1Fh
        call rawkey
        ld l,a
        ld h,0
        cp 0Dh
        call nz,putc
        jp dpush
rd2:    ld (POS),hl
        call dpop
        call rnd
        jp dpush

; "TEXT": print it, ! a new line.
op_str: call getch
        or a
        jp z,e_end
        cp '"'
        ret z
        cp '!'
        jr z,os1
        call putc
        jr op_str
os1:    call crlf
        jr op_str

op_char:
        call getch
        ld l,a
        ld h,0
        jp dpush

; [ : skip to ] unless the number is above 0.
op_if:  call dpop
        call pos_hl
        ret nz
        ld bc,5D5Bh         ; ] closes, [ opens
        jp skipto

; Z if HL <= 0.
pos_hl: bit 7,h
        jr nz,ph1
        ld a,h
        or l
        ret
ph1:    xor a
        ret

op_loop:
        ld bc,(POS)
        ld a,'L'
        jp pushf
op_again:
        ld a,(iy-8)
        cp 'L'
        jp nz,e_end
        ld l,(iy-6)
        ld h,(iy-5)
        ld (POS),hl
        ret
op_leave:
        call dpop
        call pos_hl
        ret nz
        ld bc,2928h         ; ) closes, ( opens
        call skipto
        ld de,-8
        add iy,de
        ret

; #A,P1,P2; : call macro A.
op_call:
        call getch
        sub 'A'
        cp 26
        jr nc,oc9
        call defa
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld a,d
        or e
        jr z,oc9
        push de             ; the macro's text
        ld de,(POS)         ; the call's parameters
        push de
        ld bc,3B23h         ; ; closes, # opens
        call skipto
        pop de
        ld bc,(POS)
        ld a,'M'
        call pushf
        ld hl,(OFFSET)
        ld de,26
        add hl,de
        ld (OFFSET),hl
        pop hl
        ld (POS),hl
        ret
oc9:    call err
        db "MACRO",0

; @ : back from a macro, leaving any loops in it.
op_ret: ld a,(iy-8)
        or a
        jp z,done
        push af
        call popf
        pop af
        cp 'M'
        jr nz,op_ret
        ret

; , or ; : the end of a parameter.
op_endp:
        ld a,(iy-8)
        cp 'P'
        ret nz
        jp popf

; %N: run parameter N of the macro call this one is in, in the caller's
; variables.  Parameters being run count against the calls they are in.
param:  ld (POS),hl
        inc a
        ld c,a              ; C = N
        push iy
        pop hl
        ld b,0              ; parameters to step over
pa1:    ld de,-8
        add hl,de
        ld a,(hl)
        or a
        jp z,e_end
        cp 'P'
        jr nz,pa2
        inc b
        jr pa1
pa2:    cp 'M'
        jr nz,pa1
        ld a,b
        or a
        jr z,pa3
        dec b
        jr pa1
pa3:    push hl             ; the macro frame
        ld de,4
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ld hl,(POS)
        push hl             ; back to here
        ex de,hl
        ld (POS),hl
        ld b,0              ; nesting of calls inside
pa4:    call scanch
        or a
        jp z,e_end
        cp '#'
        jr nz,pa7
        inc b
        jr pa4
pa7:    cp ';'
        jr nz,pa8
        dec b
        jp p,pa4
        jp e_end            ; no such parameter
pa8:    cp ','
        jr nz,pa4
        ld a,b
        or a
        jr nz,pa4
        dec c
        jr nz,pa4
        pop bc              ; back to here
        ld a,'P'
        call pushf          ; with this call's OFFSET
        pop hl
        ld de,6
        add hl,de
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (OFFSET),hl      ; the caller's variables
        ret

; !. : plot point x y on the 128 x 62 quarter-block screen below the title
; line; x below 0 clears the screen.
plot:   ld (POS),hl
        call pop2           ; HL = x, DE = y
        bit 7,h
        jp nz,cls
        ld b,h
        ld c,l
        ex de,hl            ; BC = x, HL = y
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
