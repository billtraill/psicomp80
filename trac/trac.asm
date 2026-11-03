; COMP80 TRAC
;
; TRAC, Calvin Mooers' Text Reckoning And Compiling language of 1964, in the
; style of TRAC T-64, for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh)
; that held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the
; RS key enters it: the monitor's NMI handler jumps to 0800h.
;
; Everything is a string.  The processor scans the active string a character
; at a time and builds the neutral string:
;   (    protects: everything up to the matching ) goes to the neutral string
;        unscanned, without the outer parentheses
;   CR   is deleted
;   ,    ends an argument
;   #(   starts an active function: its value goes back into the active
;        string to be scanned again
;   ##(  starts a neutral function: its value goes into the neutral string
;   )    ends a function, which is then evaluated
; When the active string is empty the idling procedure #(PS,#(RS)) is
; loaded again: RS reads what is typed, up to the meta character (' to begin
; with), and the result of scanning it is printed.
;
; Primitives (names in capitals; a missing argument is the null string):
;   PS,X         print X                     RS       read up to the meta char
;   RC           read one character          CM,X     meta character = X
;   DS,N,X       define form N as X          SS,N,X1,X2...  mark X1, X2... in
;   CL,N,A1,A2.. N with its segment gaps          N as segment gaps 1, 2...
;                filled by A1, A2...
;   CS,N,Z       the next segment of N, or Z at its end
;   CC,N,Z       the next character of N, or Z at its end
;   IN,N,X,Z     N from its form pointer up to X (the pointer moves past X),
;                or Z if X isn't there
;   CR,N         form pointer back to the start
;   DD,N1,N2...  delete forms              DA       delete all forms
;   AD SU ML DV,A,B,Z  A+B, A-B, A*B, A/B: the numbers at the ends of A and
;                B, with A's prefix in front; DV by 0 gives Z
;   EQ,A,B,T,F   T if A and B are the same, otherwise F
;   GR,A,B,T,F   T if the number in A is greater than the one in B, else F
;   LN,S         the names of the forms, each after S
;   PF,N         print form N, its gaps shown as <1>, <2>...
; Numbers are 16-bit integers.  An unknown function has the null value.
;
; A form is kept from FORMS as: length of the record (2), form pointer (2),
; name, 0, body, 0.  In the body a byte 80h+i is segment gap i.
;
; Keys and screen are as in FORTH: the monitor's NMI handler echoes each key
; at (DE); RS while waiting for a key is rubout; any key while TRAC is busy
; resets to the monitor and RS comes back with the forms kept.  Line 0 shows
; TRAC, lines 1-31 scroll.

MAGIC:  equ 0C00h           ; MAGICV when the forms below are valid
FEND:   equ 0C02h           ; end of the forms
META:   equ 0C04h           ; the meta character
CURS:   equ 0C06h           ; output position in screen memory
NP:     equ 0C08h           ; end of the neutral string
AP:     equ 0C0Ah           ; scan point in the active string
VB:     equ 0C0Ch           ; where a function builds its value
FMARK:  equ 0C0Eh           ; the function's marker in the neutral string
FREC:   equ 0C10h           ; form being worked on
PFXE:   equ 0C12h           ; end of the first argument's prefix
SSI:    equ 0C14h           ; SS: argument number
SSP:    equ 0C16h           ; SS: the string to mark
INS:    equ 0C18h           ; IN: where the value starts
MODE:   equ 0C1Ah           ; F1h active function, F2h neutral
ARGC:   equ 0C1Bh
ARGV:   equ 0C1Ch           ; 16 argument pointers
FORMS:  equ 0C40h
FTOP:   equ 1400h           ; the forms must end below here
NBASE:  equ 1400h           ; the neutral string grows up from here,
AEND:   equ 1C00h           ; the active string down from here
RSBUF:  equ 1C00h           ; what RS reads
RSEND:  equ 1DF0h
S0:     equ 1F00h           ; machine stack (the monitor uses 1Fxx)
MAGICV: equ 07A3Ch
MAXARG: equ 16

ACTF:   equ 0F1h            ; marks in the neutral string
NEUF:   equ 0F2h
ARGSEP: equ 0F3h

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

; Print character A (ASCII 20h-5Fh, or 0Dh for a new line).  Keeps
; everything but AF.
putc:   cp 0Dh
        jr z,crlf
        push hl
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

; ---------------------------------------------------------------- memory

; Store A at DE and step DE, if there is room below the active string.
; Keeps HL, BC.
stb:    push hl
        ld hl,(AP)
        scf
        sbc hl,de
        pop hl
        jr c,full
        ld (de),a
        inc de
        ret

; The same, for the forms.
stf:    push hl
        ld hl,FTOP-1
        or a
        sbc hl,de
        pop hl
        jr c,full
        ld (de),a
        inc de
        ret

full:   ld sp,S0
        call prsi
        db " FULL",0
        jp idle

; Put A on the end of the neutral string.  Keeps HL, BC, DE.
putn:   push de
        ld de,(NP)
        call stb
        ld (NP),de
        pop de
        ret

; Copy the string at HL, without its 0, to DE.  HL ends at the 0.
copys:  ld a,(hl)
        or a
        ret z
        call stb
        inc hl
        jr copys

; Move BC bytes from HL to DE; the two may overlap.
move:   ld a,b
        or c
        ret z
        push hl
        or a
        sbc hl,de
        pop hl
        jr c,mv2
        ldir
        ret
mv2:    add hl,bc
        dec hl
        ex de,hl
        add hl,bc
        dec hl
        ex de,hl
        lddr
        ret

; HL = argument A, or a null string if there aren't that many.  Keeps DE.
arg:    ld hl,ARGC
        cp (hl)
        jr nc,anull
        push de
        add a,a
        ld l,a
        ld h,0
        ld de,ARGV
        add hl,de
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        pop de
        ret
anull:  ld hl,zero
        ret

; ---------------------------------------------------------------- forms

; Find the form named by the string at HL.  Z and HL = its record if there
; is one.
findf:  ex de,hl
        ld hl,FORMS
ff1:    push hl
        ld bc,(FEND)
        or a
        sbc hl,bc
        pop hl
        jr nc,ffno
        push hl
        push de
        inc hl
        inc hl
        inc hl
        inc hl
ff2:    ld a,(de)
        cp (hl)
        jr nz,ff3
        inc hl
        inc de
        or a
        jr nz,ff2
        pop de
        pop hl
        ret
ff3:    pop de
        pop hl
        call next
        jr ff1
ffno:   or 1
        ret

; HL = the record after the one at HL.  Keeps DE.
next:   ld c,(hl)
        inc hl
        ld b,(hl)
        dec hl
        add hl,bc
        ret

; HL = the body of the record at HL.
body:   inc hl
        inc hl
        inc hl
        inc hl
bo1:    ld a,(hl)
        inc hl
        or a
        jr nz,bo1
        ret

; Delete the record at HL.
delf:   ld c,(hl)
        inc hl
        ld b,(hl)
        dec hl
        push hl
        ld hl,(FEND)
        or a
        sbc hl,bc
        ld (FEND),hl
        pop de
        push de
        or a
        sbc hl,de
        ex (sp),hl
        add hl,bc
        pop bc
        jp move

; Find the form named by argument 1.  NZ if there is none; otherwise HL =
; where its form pointer is, DE = its body, and FREC = its record.
fpos:   ld a,1
        call arg
        call findf
        ret nz
        ld (FREC),hl
        inc hl
        inc hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        dec hl
        dec hl
        dec hl
        call body
        ld d,h
        ld e,l
        add hl,bc
        cp a
        ret

; Form pointer of FREC = HL - DE.  Keeps AF.
setp:   push af
        or a
        sbc hl,de
        ex de,hl
        ld hl,(FREC)
        inc hl
        inc hl
        ld (hl),e
        inc hl
        ld (hl),d
        pop af
        ret

; ---------------------------------------------------------------- primitives

ps_:    ld a,1
        call arg
        call puts
        jp retnul

; RS: read up to the meta character.  Return goes into the string (and the
; processor deletes it unless it is protected); Returns before anything
; else are left out.
rs_:    ld de,RSBUF
rs1:    ld a,1Fh
        call rawkey
        cp 8
        jr z,rs4
        cp 0Dh
        jr nz,rs2
        ld hl,RSBUF
        or a
        sbc hl,de
        jr z,rs1
        ld a,0Dh
rs2:    ld hl,META
        cp (hl)
        jr z,rs9
        ld hl,RSEND
        or a
        sbc hl,de
        jr c,rs1            ; full
        ld (de),a
        inc de
        call putc
        jr rs1
rs4:    ld hl,RSBUF         ; rubout, but not past a Return
        or a
        sbc hl,de
        jr z,rs1
        dec de
        ld a,(de)
        cp 0Dh
        jr z,rs5
        ld hl,(CURS)
        dec hl
        ld (hl),' '
        ld (CURS),hl
        jr rs1
rs5:    inc de
        jr rs1
rs9:    call putc
        call crlf
        ld hl,RSBUF
        ex de,hl
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        ret

rc_:    ld a,1Fh
        call rawkey
        ld hl,(VB)
        ld (hl),a
        ld bc,1
        ret

cm_:    ld a,1
        call arg
        ld a,(hl)
        or a
        jp z,retnul
        ld (META),a
        jp retnul

ds_:    ld a,1
        call arg
        push hl
        call findf
        call z,delf
        pop hl
        ld de,(FEND)
        push de
        inc de
        inc de
        inc de
        inc de
        call cpf            ; name
        ld a,2
        call arg
        call cpf            ; body
        pop hl
        push de
        ex de,hl
        or a
        sbc hl,de
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        xor a
        ld (hl),a
        inc hl
        ld (hl),a
        pop hl
        ld (FEND),hl
        jp retnl2
cpf:    ld a,(hl)           ; copy the string at HL, with its 0, to the forms
        call stf
        inc hl
        or a
        jr nz,cpf
        ret

; SS: replace each appearance of arguments 2, 3... in the form by gap 1, 2...
ss_:    ld a,1
        call arg
        call findf
        jr nz,retnl2
        ld (FREC),hl
        ld a,2
ss1:    ld (SSI),a
        ld hl,ARGC
        cp (hl)
        jr nc,retnl2
        call arg
        ld (SSP),hl
        ld a,(hl)
        or a
        jr z,ss8
        ld hl,(FREC)
        call body
ss2:    ld a,(hl)
        or a
        jr z,ss8
        ld de,(SSP)
        push hl
ss3:    ld a,(de)
        or a
        jr z,ss5
        cp (hl)
        jr nz,ss4
        inc hl
        inc de
        jr ss3
ss4:    pop hl
        inc hl
        jr ss2
ss5:    pop de              ; a match from DE up to HL
        push de
        ld a,(SSI)
        add a,7Fh
        ld (de),a
        inc de
        push hl
        or a
        sbc hl,de
        ld b,h
        ld c,l              ; BC = bytes saved
        pop hl
        push bc
        push de
        push hl
        ld hl,(FEND)
        pop de
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        pop de
        call move
        pop bc
        ld hl,(FEND)
        or a
        sbc hl,bc
        ld (FEND),hl
        ld hl,(FREC)
        ld e,(hl)
        inc hl
        ld d,(hl)
        ex de,hl
        or a
        sbc hl,bc
        ex de,hl
        ld (hl),d
        dec hl
        ld (hl),e
        pop hl
        inc hl
        jr ss2
ss8:    ld a,(SSI)
        inc a
        jr ss1

retnl2: jp retnul

; CL: the form with its gaps filled.
cl_:    ld a,1
        call arg
        call findf
        jr nz,retnl2
        call body
        ld de,(VB)
cl1:    ld a,(hl)
        inc hl
        or a
        jr z,vdon2
        bit 7,a
        jr z,cl2
        push hl
        sub 7Fh
        call arg
        call copys
        pop hl
        jr cl1
cl2:    call stb
        jr cl1

vdon2:  jp vdone

; CS: the next segment.
cs_:    call fpos
        jr nz,retnl2
        ld a,(hl)
        or a
        jp z,arg2r
        push de
        ld de,(VB)
cs1:    ld a,(hl)
        or a
        jr z,cs9
        inc hl
        bit 7,a
        jr nz,cs9
        call stb
        jr cs1
cs9:    ex (sp),hl          ; HL = body, stack = pointer
        ex de,hl            ; DE = body, HL = end of the value
        ex (sp),hl          ; HL = pointer
        call setp
        pop de
        jr vdon2

; CC: the next character.
cc_:    call fpos
        jr nz,retnl2
cc1:    ld a,(hl)
        or a
        jp z,arg2r
        inc hl
        bit 7,a
        jr nz,cc1
        call setp
        ld hl,(VB)
        ld (hl),a
        ld bc,1
        ret

; IN: up to the first X after the pointer.
in_:    call fpos
        jr nz,retnl2
        ld (INS),hl
        push de
in1:    ld a,(hl)
        or a
        jr z,in8
        push hl
        ld a,2
        call arg
        ex de,hl
        pop hl
        push hl
in2:    ld a,(de)
        or a
        jr z,in5
        cp (hl)
        jr nz,in3
        inc hl
        inc de
        jr in2
in3:    pop hl
        inc hl
        jr in1
in5:    pop bc              ; X is at BC; HL is past it
        pop de
        call setp
        ld hl,(INS)
        ld de,(VB)
in6:    push hl
        or a
        sbc hl,bc
        pop hl
        jr z,vdon2
        ld a,(hl)
        inc hl
        bit 7,a
        call z,stb
        jr in6
in8:    pop de
        jp arg3r

cr_:    call fpos
        jp nz,retnl2
        ld d,h
        ld e,l
        call setp
        jp retnl2

dd_:    ld a,1
dd1:    push af
        ld hl,ARGC
        cp (hl)
        jr nc,dd9
        call arg
        call findf
        call z,delf
        pop af
        inc a
        jr dd1
dd9:    pop af
        jp retnl2

da_:    ld hl,FORMS
        ld (FEND),hl
        jp retnl2

eq_:    ld a,1
        call arg
        ex de,hl
        ld a,2
        call arg
eq1:    ld a,(de)
        cp (hl)
        jp nz,arg4r
        inc hl
        inc de
        or a
        jr nz,eq1
        jp arg3r

gr_:    ld a,1
        call arg
        call getnum
        push hl
        ld a,2
        call arg
        call getnum
        pop de
        call scmp           ; B < A?
        jp c,arg3r
        jp arg4r

; LN: each name after S.
ln_:    ld de,(VB)
        ld hl,FORMS
ln1:    push hl
        ld bc,(FEND)
        or a
        sbc hl,bc
        pop hl
        jp nc,vdon2
        push hl
        ld a,1
        call arg
        call copys
        pop hl
        push hl
        inc hl
        inc hl
        inc hl
        inc hl
        call copys
        pop hl
        call next
        jr ln1


part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If TRAC was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) TRAC.

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
        jr z,wa2
        ld (MAGIC),de
        ld a,27h            ; '
        ld (META),a
        call da_
wa2:    ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " TRAC",0
        call crlf
        ld hl,VRAM+40h
        ld (CURS),hl
        call CLS64

; ---------------------------------------------------------------- processor

; Load the idling procedure #(PS,#(RS)) with an empty neutral string.
idle:   ld sp,S0
        ld a,(CURS)
        and 3Fh
        call nz,crlf
        ld hl,NBASE
        ld (NP),hl
        ld hl,idles
        ld de,AEND-ILEN
        ld (AP),de
        ld bc,ILEN
        ldir

scan:   ld hl,(AP)
        ld de,AEND
        or a
        sbc hl,de
        jr z,idle
        add hl,de
        ld a,(hl)
        inc hl
        ld (AP),hl
        cp '('
        jr z,prot
        cp 0Dh
        jr z,scan
        cp ')'
        jr z,endf
        cp ','
        jr nz,sc2
        ld a,ARGSEP
        jr sput
sc2:    cp '#'
        jr nz,sput
        ld a,(hl)
        ld b,ACTF
        cp '('
        jr z,sc3
        cp '#'
        jr nz,sc4
        inc hl
        ld a,(hl)
        cp '('
        jr nz,sc4
        inc b
sc3:    inc hl
        ld (AP),hl
        ld a,b
        jr sput
sc4:    ld a,'#'
sput:   call putn
        jr scan

; ( : copy up to the matching ) unscanned.
prot:   ld b,1
pr1:    push hl
        ld de,AEND
        or a
        sbc hl,de
        pop hl
        jr z,idle           ; no ): give up
        ld a,(hl)
        inc hl
        cp '('
        jr nz,pr2
        inc b
pr2:    cp ')'
        jr nz,pr3
        dec b
        jr z,pr9
pr3:    call putn
        jr pr1
pr9:    ld (AP),hl
        jr scan

; ) : find the function's mark, split its arguments, and evaluate it.
endf:   ld hl,(NP)
ef1:    ld de,NBASE
        or a
        sbc hl,de
        jr z,scan           ; no function: drop the )
        add hl,de
        dec hl
        ld a,(hl)
        cp ACTF
        jr z,ef2
        cp NEUF
        jr nz,ef1
ef2:    ld (MODE),a
        ld (FMARK),hl
        xor a
        call putn
        ld de,(NP)
        ld (VB),de
        ld de,ARGV
        ld b,0
ef3:    inc hl
        ex de,hl
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ex de,hl
        inc b
ef4:    ld a,(hl)
        or a
        jr z,ef5
        cp ARGSEP
        jr z,ef6
        inc hl
        jr ef4
ef6:    ld (hl),0
        ld a,b
        cp MAXARG
        jr c,ef3
ef5:    ld a,b
        ld (ARGC),a
        ld hl,(ARGV)        ; the function's name
        ld b,(hl)
        inc hl
        ld c,(hl)
        inc hl
        ld a,(hl)
        ld hl,finish
        push hl
        or a
        jr nz,retnul        ; not two letters
        ld hl,ptab
ef7:    ld a,(hl)
        or a
        jr z,retnul         ; not a primitive
        inc hl
        cp b
        jr nz,ef8
        ld a,(hl)
        cp c
        jr nz,ef8
        inc hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jp (hl)
ef8:    inc hl
        inc hl
        inc hl
        jr ef7

; The function's value is HL, BC long: put it in place of the function.
finish: ld de,(FMARK)
        ld (NP),de
        ld a,(MODE)
        cp NEUF
        jr nz,fi2
        push hl
        ld h,d
        ld l,e
        add hl,bc
        ld (NP),hl
        pop hl
        call move
        jp scan
fi2:    push hl             ; active: in front of the rest of the active string
        ld hl,(AP)
        or a
        sbc hl,bc
        jr c,fi3
        push hl
        sbc hl,de
        pop de
        jr c,fi3
        ld (AP),de
        pop hl
        call move
        jp scan
fi3:    jp full

; Values.  VDONE: the value built from VB up to DE.  RETNUL: the null
; string.  RLEN: the string at HL.  ARGR: argument A.
vdone:  ld hl,(VB)
        ex de,hl
        or a
        sbc hl,de
        ld b,h
        ld c,l
        ex de,hl
        ret
retnul: ld bc,0
        ret
arg3r:  ld a,3
        jr argr
arg2r:  ld a,2
        jr argr
arg4r:  ld a,4
argr:   call arg
rlen:   push hl
        ld bc,0
rl1:    ld a,(hl)
        or a
        jr z,rl2
        inc hl
        inc bc
        jr rl1
rl2:    pop hl
        ret

; PF: print the form, with its gaps.
pf_:    ld a,1
        call arg
        call findf
        jr nz,retnl3
        call body
pf1:    ld a,(hl)
        inc hl
        or a
        jr z,retnl3
        bit 7,a
        jr z,pf2
        sub 50h
        push af
        ld a,'<'
        call putc
        pop af
        call putc
        ld a,'>'
pf2:    call putc
        jr pf1

retnl3: jp retnul

; ---------------------------------------------------------------- arithmetic

; Arithmetic: the numbers at the ends of arguments 1 and 2, the answer with
; argument 1's prefix in front.
ad_:    call ar2
        add hl,de
        jr arout
su_:    call ar2
        or a
        sbc hl,de
        jr arout
ml_:    call ar2
        call mul16
        jr arout
dv_:    call ar2
        ld a,d
        or e
        jp z,arg3r
        ld a,h
        xor d
        push af             ; sign of the answer
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
        call m,neghl
arout:  push hl
        ld de,(VB)
        ld a,1
        call arg
ao1:    push hl
        ld bc,(PFXE)
        or a
        sbc hl,bc
        pop hl
        jr nc,ao2
        ld a,(hl)
        call stb
        inc hl
        jr ao1
ao2:    pop hl
        bit 7,h
        jr z,ao3
        ld a,'-'
        call stb
        call neghl
ao3:    call nout
        jp vdone

; Write HL (unsigned) in decimal at DE.
nout:   push de
        ld b,16
        xor a
no1:    add hl,hl           ; HL = HL / 10, A = the remainder
        rla
        cp 10
        jr c,no2
        sub 10
        inc l
no2:    djnz no1
        pop de
        push af
        ld a,h
        or l
        call nz,nout
        pop af
        add a,'0'
        jp stb

; HL = the number at the end of argument 1, DE = the one in argument 2,
; PFXE = where argument 1's number starts.
ar2:    ld a,2
        call arg
        call getnum
        push hl
        ld a,1
        call arg
        call getnum
        ld (PFXE),de
        pop de
        ret

; HL = the number at the end of the string at HL: its last digits, with a -
; just in front making it negative.  DE = where the number starts.
getnum: push hl
gn1:    ld a,(hl)
        or a
        jr z,gn2
        inc hl
        jr gn1
gn2:    pop de
gn3:    push hl
        or a
        sbc hl,de
        pop hl
        jr z,gn4
        dec hl
        ld a,(hl)
        sub '0'
        cp 10
        jr c,gn3
        inc hl
gn4:    ld b,0
        push hl
        or a
        sbc hl,de
        pop hl
        jr z,gn5
        dec hl
        ld a,(hl)
        cp '-'
        jr z,gn6
        inc hl
gn5:    push hl
        jr gn7
gn6:    push hl
        inc hl
        inc b
gn7:    ex de,hl
        ld hl,0
gn8:    ld a,(de)
        sub '0'
        cp 10
        jr nc,gn9
        push de
        add hl,hl
        ld d,h
        ld e,l
        add hl,hl
        add hl,hl
        add hl,de
        ld e,a
        ld d,0
        add hl,de
        pop de
        inc de
        jr gn8
gn9:    ld a,b
        or a
        call nz,neghl
        pop de
        ret

; CY = HL < DE, signed.
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

; HL = HL * DE.
mul16:  ld b,h
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

; ---------------------------------------------------------------- tables

idles:  db "#(PS,#(RS))"
ILEN:   equ $-idles

ptab:   db "PS"
        dw ps_
        db "RS"
        dw rs_
        db "RC"
        dw rc_
        db "CM"
        dw cm_
        db "DS"
        dw ds_
        db "SS"
        dw ss_
        db "CL"
        dw cl_
        db "CS"
        dw cs_
        db "CC"
        dw cc_
        db "IN"
        dw in_
        db "CR"
        dw cr_
        db "DD"
        dw dd_
        db "DA"
        dw da_
        db "AD"
        dw ad_
        db "SU"
        dw su_
        db "ML"
        dw ml_
        db "DV"
        dw dv_
        db "EQ"
        dw eq_
        db "GR"
        dw gr_
        db "LN"
        dw ln_
        db "PF"
        dw pf_
zero:   db 0                ; also the null string

part2_end:
        ds 0C00h-$,0FFh
