; COMP80 ZASM
;
; A Z80 assembler and disassembler for the PSI COMP80, in the 2 KB of ROM
; (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh) is unchanged.  As
; with BURP, the RS key enters it: the monitor's NMI handler jumps to 0800h.
;
; Commands (numbers in hex, as in the monitor; only the first letter counts):
;   DIS [addr]           disassemble 24 lines; with no address, carry on
;   ASM [addr]           assemble a line at a time; a blank line ends
;   GO addr              call addr; a RET comes back here
;
; Decoding follows the opcode's fields: x = bits 7-6, y = 5-3, z = 2-0, and
; y = p * 2 + q.  For x = 0 and x = 3 (and ED with x = 1) a table indexed by
; z gives a list of format strings and which field picks one from it.  A
; format string is text with control codes (below 20h) for the operands; its
; last byte has bit 7 set.
;
; The assembler runs the disassembler backwards.  It tries every opcode in
; turn (plain, CB, ED, DD, FD, DD CB, FD CB) in a 4-byte buffer, with the
; disassembler in "template" mode: instead of being printed, each character
; is compared with the line typed in, and the first mismatch gives up that
; opcode.  Where a number would be printed, the typed number is read instead
; and kept with the place it goes, so the first opcode whose text matches is
; the instruction.  Typed numbers must start with a digit (0FF, not FF), as
; the disassembler prints them, so that A, B, C and so on are registers.
; Relative jumps take the address jumped to.
;
; Keys and screen are handled as in COMP80 FORTH (forth/forth.asm).

TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
CURS:   equ 1DA0h           ; output position in screen memory
DPTR:   equ 1DA2h           ; next byte to disassemble
OPTR:   equ 1DA4h           ; template mode: next character to match
PFX:    equ 1DA6h           ; 0, DD or FD
TMPL:   equ 1DA8h           ; nonzero: template mode
OPY:    equ 1DA9h
OPZ:    equ 1DAAh
DVAL:   equ 1DABh           ; index displacement
POSN:   equ 1DACh           ; where the number goes
POSD:   equ 1DAEh           ; where the displacement goes
TSP:    equ 1DB6h           ; stack pointer to give up a try
NEXTA:  equ 1DB8h           ; where DIS carries on
DEST:   equ 1DBAh           ; where ASM puts the next instruction
IPTR:   equ 1DBCh           ; command line parse position
LSTART: equ 1DBEh           ; start of the ASM line on screen
GPTR:   equ 1DC0h           ; assembler: group being tried
GCNT:   equ 1DC2h
CBUF:   equ 1DC8h           ; assembler: the instruction being tried
S0:     equ 1F00h           ; stack (the monitor uses 1Fxx)

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

; control codes in format strings
RY:     equ 1               ; r[y]
RZ:     equ 2               ; r[z]
RPP:    equ 3               ; rp[p]: BC DE HL SP
RP2:    equ 4               ; rp2[p]: BC DE HL AF
CCY:    equ 5               ; cc[y]
CC4:    equ 6               ; cc[y-4]
NB:     equ 7               ; a byte
NW:     equ 8               ; a word
REL:    equ 9               ; relative jump, shown as its target
ALU:    equ 10              ; ADD A, ADC A, SUB ... CP
ROT:    equ 11              ; RLC ... SRL
BITY:   equ 12              ; y as a digit
RSTY:   equ 13              ; y * 8
IMY:    equ 14              ; interrupt mode for y
HLX:    equ 15              ; HL, IX or IY
BLI:    equ 16              ; block instruction
LDS:    equ 17              ; "LD "
E:      equ 80h             ; added to the last byte of a string

        org 0400h

; ---------------------------------------------------------------- decoder

; Disassemble the instruction at DPTR: print it, or in template mode match
; it against the text at OPTR.  DPTR ends after the instruction.
dis:    xor a
        ld (PFX),a
        ld h,a
        ld l,a
        ld (POSD),hl        ; no displacement read yet
ds0:    call getb
        cp 0DDh
        jr z,dsp
        cp 0FDh
        jr nz,ds1
dsp:    ld (PFX),a
        jr ds0
ds1:    cp 0EDh
        jp z,ded
        cp 0CBh
        jr z,dcb
        cp 76h
        ld hl,s_halt
        jp z,fmt
        call split
        dec a
        ld hl,s_ldrr
        jp z,fmt
        dec a
        ld hl,s_alu
        jp z,fmt
        dec a
        ld hl,tab3
        jr z,dtab           ; x = 3
        ld a,(OPZ)          ; x = 0: JR cc is one string for four y
        or a
        jr nz,dx0
        ld a,(OPY)
        cp 4
        ld hl,s_jrcc
        jr nc,fmt
dx0:    ld hl,tab0
dtab:   ld a,(OPZ)          ; HL = 8 descriptors, one for each z
        add a,a
        call idx
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld a,h              ; top 2 bits: which field picks the string
        and 0Fh
        ld b,h
        ld h,a
        ld a,b
        rlca
        rlca
        and 3
        ld b,a
        jr z,dsel           ; 0: the only one
        ld a,(OPY)
        djnz dm2
        and 1               ; 1: q
        jr dsel
dm2:    djnz dm3
        jr dsel             ; 2: y
dm3:    srl a               ; 3: q ? 1 + p : 0
        jr nc,dm4
        inc a
        jr dsel
dm4:    xor a
dsel:   call nth
        jr fmt

dcb:    ld a,(PFX)          ; CB, or DD CB d op: d comes first
        or a
        jr z,dcb1
        ld hl,(DPTR)
        ld (POSD),hl
        call getb
dcb1:   call getb
        call split
        ld hl,g_cb
        jr dsel

ded:    call getb
        call split
        dec a
        ld hl,tabed
        jr z,dtab           ; x = 1
        dec a
        jr nz,dinv
        ld a,(OPY)          ; x = 2: block instructions, y >= 4, z <= 3
        cp 4
        jr c,dinv
        ld a,(OPZ)
        cp 4
        ld hl,s_bli
        jr c,fmt
dinv:   ld hl,s_inv

; Run the format string at HL; in template mode the typed line must end
; with it.
fmt:    call fmts
        ld a,(TMPL)
        or a
        ret z
        call optr
        or a
        ret z
fail:   ld sp,(TSP)         ; give up this try
        or 1
        ret

fmts:   ld a,(hl)
        inc hl
        push af             ; bit 7: the last byte
        and 7Fh
        cp 20h
        jr c,fctl
        call outc
        jr fnext
fctl:   push hl
        add a,a
        ld hl,ctltab-2
        call idx
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        call jphl
        pop hl
fnext:  pop af
        rla
        jr nc,fmts
        ret
jphl:   jp (hl)

ctltab: dw k_ry,k_rz,k_rpp,k_rp2,k_ccy,k_cc4,k_n,k_nn,k_rel
        dw k_alu,k_rot,k_bity,k_rst,k_imy,k_hlx,k_bli,k_lds

; Split opcode A into y (OPY) and z (OPZ); A = x.
split:  ld b,a
        and 7
        ld (OPZ),a
        ld a,b
        rrca
        rrca
        rrca
        and 7
        ld (OPY),a
        ld a,b
        rlca
        rlca
        and 3
        ret

getb:   ld hl,(DPTR)
        ld a,(hl)
        inc hl
        ld (DPTR),hl
        ret

; HL += A
idx:    add a,l
        ld l,a
        ret nc
        inc h
        ret

; Skip A strings of the list at HL.
nth:    or a
        ret z
        ld b,a
nt1:    ld a,(hl)
        inc hl
        rla
        jr nc,nt1
        djnz nt1
        ret

; Print A, or in template mode check it is next in the typed line.
; Keeps everything but AF.
outc:   push af
        ld a,(TMPL)
        or a
        jr nz,oc2
        pop af
        jp putc
oc2:    pop af              ; spaces may follow a space, comma or bracket
        push hl
        ld hl,(OPTR)
        cp (hl)
        jp nz,fail
        inc hl
        cp '0'
        call c,skipsp
        ld (OPTR),hl
        pop hl
        ret
optr:   ld hl,(OPTR)        ; HL = OPTR, past spaces
        jp skipsp

; ---------------------------------------------------------------- operands

k_ry:   ld a,(OPY)
        jr preg
k_rz:   ld a,(OPZ)
preg:   cp 6
        jr z,pmem
        ld hl,regs
        call idx
        ld a,(hl)
        jr outc
pmem:   ld a,'('            ; (HL) or (IX+d)
        call outc
        call k_hlx
        ld a,(PFX)
        or a
        call nz,o_d
        ld a,')'
        jr outc

k_hlx:  ld a,(PFX)          ; 0, DD or FD: 0, 2 or 6
        rrca
        rrca
        rrca
        and 6
        ld hl,hltab
        jr pair

k_rpp:  ld hl,rptab
        jr rp1
k_rp2:  ld hl,rp2tab
rp1:    ld a,(OPY)
        and 6
        cp 4
        jr z,k_hlx
pair:   call idx
        ld a,(hl)
        call outc
        inc hl
        ld a,(hl)
        cp ' '
        ret z
outc1:  jr outc

k_ccy:  ld a,(OPY)
        jr pcc
k_cc4:  ld a,(OPY)
        and 3
pcc:    add a,a
        ld hl,cctab
        jr pair

k_alu:  ld hl,alus
        jr pstr
k_rot:  ld hl,rots
pstr:   ld a,(OPY)
        call nth
        jp fmts

k_bity: ld a,(OPY)
        add a,'0'
        jr outc1

k_rst:  ld a,(OPY)
        add a,a
        add a,a
        add a,a
        jp hx2

k_imy:  ld a,(OPY)
        and 3
        ld hl,imtab
        call idx
        ld a,(hl)
        jr outc1

k_lds:  ld hl,s_lds
        jp fmts

; LDI CPI INI OUTI, LDD ..., LDIR ..., LDDR ... OTDR
k_bli:  ld a,(OPZ)
        add a,a
        ld hl,blitab
        call idx
        ld a,(hl)
        call outc
        inc hl
        ld a,(OPZ)
        cp 3
        jr nz,bl1
        ld a,(OPY)
        cp 6
        ld a,'U'
        call c,outc
bl1:    ld a,(hl)
        call outc
        ld a,(OPY)
        and 1
        ld a,'I'
        jr z,bl2
        ld a,'D'
bl2:    call outc
        ld a,(OPY)
        cp 6
        ret c
        ld a,'R'
        jp outc1

; Numbers.  In template mode the typed number is put straight into the
; instruction, at the place the disassembler read it from (POSN).
k_n:    call mark
        call getb
        ld l,a
        ld a,(TMPL)
        or a
        jr z,show2
        call tparse
        ld a,l
tput1:  ld hl,(POSN)
        ld (hl),a
        ret
k_nn:   call mark
        call getb
        push af
        call getb
        ld h,a
        pop af
        ld l,a
        ld a,(TMPL)
        or a
        jr z,show4
        call tparse
        ex de,hl
        ld hl,(POSN)
        ld (hl),e
        inc hl
        ld (hl),d
        ret
k_rel:  call mark           ; shown as the address jumped to
        call getb
        ld e,a
        rla
        sbc a,a
        ld d,a
        ld hl,(DPTR)
        add hl,de
        ld a,(TMPL)
        or a
        jr z,show4
        call tparse
        ld de,(DEST)
        inc de
        inc de
        or a
        sbc hl,de
        ld a,l
        rla
        sbc a,a
        cp h
        jp nz,fail          ; too far
        ld a,l
        jr tput1

show2:  ld h,l              ; a 0 in front if it starts with A-F
        call lead
        ld a,l
        jp hx2
show4:  call lead
        jp hex4
lead:   ld a,h
        cp 0A0h
        ret c
        ld a,'0'
        jp outc

; Read the typed number, which must start with a digit, into HL.
tparse: ld de,(OPTR)
        ld a,(de)
        sub '0'
        cp 10
        jp nc,fail
        call hexrd
        ld (OPTR),de
        ret

mark:   ld hl,(DPTR)
        ld (POSN),hl
        ret

; The d of (IX+d), shown +05 or -03.
o_d:    ld hl,(POSD)        ; already read for DD CB
        ld a,h
        or l
        jr nz,od0
        ld hl,(DPTR)
        ld (POSD),hl
        inc hl
        ld (DPTR),hl
        dec hl
od0:    ld a,(hl)
        ld b,a
        ld a,(TMPL)
        or a
        jr nz,tdisp
        ld a,b
        ld c,'+'
        or a
        jp p,od2
        neg
        ld c,'-'
od2:    push af
        ld a,c
        call outc
        pop af
        jr hx2
tdisp:  ld de,(OPTR)        ; template: + or - and a number, or nothing for 0
        ld a,(de)
        ld hl,0
        cp '+'
        jr z,td1
        cp '-'
        jr nz,td2
td1:    push af
        inc de
        call hexrd
        ld (OPTR),de
        pop af
        cp '-'
        ld a,l
        jr nz,td2
        neg
        ld l,a
td2:    ld a,l
        ld hl,(POSD)
        ld (hl),a
        ret

; Read hex digits at DE into HL.  B = how many.  DE ends after them.
hexrd:  ld hl,0
        ld b,l
hr1:    ld a,(de)
        call hexdig
        ret c
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        or l
        ld l,a
        inc de
        inc b
        jr hr1

; A = value of hex digit A, NC; or CY if it isn't one.
hexdig: sub '0'
        cp 10
        ccf
        ret nc
        sub 'A'-'0'
        cp 6
        ccf
        ret c
        add a,10
        ret

hex4:   ld a,h              ; HL in hex
        call hx2
        ld a,l
hx2:    push af             ; A in hex
        rrca
        rrca
        rrca
        rrca
        call hx1
        pop af
hx1:    and 0Fh
        add a,90h
        daa
        adc a,40h
        daa
        jp outc

; ---------------------------------------------------------------- tables

; descriptors: string list + 4000h * which field picks one
; (0 the first, 1 q, 2 y, 3 q ? 1 + p : 0)
tab0:   dw g0z0+8000h,g0z1+4000h,g0z2+8000h,g0z3+4000h
        dw g0z4,g0z5,g0z6,g0z7+8000h
tab3:   dw g3z0,g3z1+0C000h,g3z2,g3z3+8000h
        dw g3z4,g3z5+0C000h,g3z6,g3z7
tabed:  dw gedz0,gedz1,gedz2+4000h,gedz3+4000h
        dw gedz4,gedz5+4000h,gedz6,gedz7+8000h

regs:   db "BCDEHL?A"
hltab:  db "HLIX  IY"
rptab:  db "BCDEHLSP"
rp2tab: db "BCDEHLAF"
cctab:  db "NZZ NCC POPEP M "
imtab:  db "0012"
blitab: db "LDCPINOT"

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

skipsp: ld a,(hl)
        cp ' '
        ret nz
        inc hl
        jr skipsp

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If ZASM was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) ZASM.

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
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " ZASM",E+' '
        call cls
        xor a
        ld (TMPL),a
        ld hl,1000h
        ld (NEXTA),hl
        ld (DEST),hl

; Read a command and run it.
cmd:    ld sp,S0
        ld a,'>'
        call putc
        call accept
        call crlf
        ld hl,TIB
        call skipsp
        or a
        jr z,cmd
        ld c,a
cm1:    inc hl              ; past the rest of the word
        ld a,(hl)
        cp '!'
        jr nc,cm1
        ld (IPTR),hl
        ld a,c
        cp 'D'
        jr z,k_dis
        cp 'A'
        jp z,k_asm
        cp 'G'
        jr z,k_go
bad:    call prsi
        db E+'?'
        call crlf
        jr cmd

; Skip spaces at IPTR and read a hex number: HL, CY if there wasn't one.
gethex: ld hl,(IPTR)
        call skipsp
        ex de,hl
        call hexrd
        ld (IPTR),de
        ld a,b
        cp 1
        ret

k_go:   call gethex
        jr c,bad
        call jphl
        jr cmd

; DIS [addr]
k_dis:  call gethex
        jr nc,kd1
        ld hl,(NEXTA)
kd1:    ld b,24
kd3:    push bc
        ld (DPTR),hl
        call disln
        ld hl,(DPTR)
        pop bc
        djnz kd3
        ld (NEXTA),hl
        jr cmd

; Show the instruction at DPTR, and a new line: the address and bytes, and
; from column 17 the text.
disln:  ld de,(CURS)        ; blank the line
        push de
        rst 20h
        call PAD64
        pop hl
        push hl
        ld de,17
        add hl,de
        ld (CURS),hl
        ld hl,(DPTR)
        push hl
        call dis
        pop hl
        pop de
        ld bc,(CURS)
        push bc
        ld (CURS),de
        call hex4
dl1:    call space
        ld a,(DPTR)
        cp l
        jr z,dl2
        ld a,(hl)
        inc hl
        call hx2
        jr dl1
dl2:    pop hl
        ld (CURS),hl
        jp crlf

; ASM: each line shows the address; what is typed is put there and shown
; again as DIS shows it.  A line that isn't an instruction gets a ?.
k_asm:  call gethex
        jr nc,ka0
        ld hl,(DEST)
ka0:    ld (DEST),hl
        ld (NEXTA),hl       ; DIS afterwards lists what was typed
ka1:    ld hl,(CURS)
        ld (LSTART),hl
        ld hl,(DEST)
        call hex4
        call space
        call accept
        ld hl,TIB
        call skipsp
        ld (IPTR),hl
        or a
        jr z,ka9
        call asm1
        jr nz,ka8
        ld hl,(LSTART)
        ld (CURS),hl
        ld hl,(DEST)
        ld (DPTR),hl
        call disln
        ld hl,(DPTR)
        ld (DEST),hl
        jr ka1
ka8:    call prsi
        db " ",E+'?'
        call crlf
        jr ka1
ka9:    call crlf
        jp cmd

; Assemble the line in TIB at DEST.  Z if it went.
asm1:
as0:    ld hl,groups
        ld (GPTR),hl
        ld a,7
        ld (GCNT),a
ag1:    ld hl,(GPTR)
        ld c,(hl)           ; where the opcode goes
        inc hl
        ld a,(hl)
        ld (CBUF),a
        inc hl
        ld a,(hl)
        ld (CBUF+1),a
        inc hl
        ld (GPTR),hl
        xor a
        ld (CBUF+2),a
        ld (CBUF+3),a
        ld hl,CBUF
        ld a,c
        call idx
        ld c,0
ag2:    ld (hl),c
        push hl
        push bc
        ld hl,CBUF
        ld (DPTR),hl
        ld hl,(IPTR)
        ld (OPTR),hl
        ld a,1
        ld (TMPL),a
        call try
        pop bc
        pop hl
        jr z,found
        inc c
        jr nz,ag2
        ld hl,GCNT
        dec (hl)
        jr nz,ag1
        call found0
        inc a               ; NZ: nothing matched
        ret

try:    ld (TSP),sp
        call dis
        xor a
        ret

; It matched: copy it to DEST.
found:
pcopy:  call ilen
        ld b,h
        ld c,l
        ld hl,CBUF
        ld de,(DEST)
        ldir
found0: xor a
        ld (TMPL),a
        ret

ilen:   ld hl,(DPTR)        ; HL = length of the instruction in CBUF
        ld de,CBUF
        or a
        sbc hl,de
        ret

; where the opcode goes, and the bytes before it
groups: db 0,0,0
        db 1,0CBh,0
        db 1,0EDh,0
        db 1,0DDh,0
        db 1,0FDh,0
        db 3,0DDh,0CBh
        db 3,0FDh,0CBh

; ---------------------------------------------------------------- terminal

; Wait for a key.  A = glyph to show at the cursor meanwhile.  Returns A =
; ASCII key, 1Fh for Return, 0FFh for rubout.  Leaves the screen as it was
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
        cp 1Fh
        ret z
        cp 20h
        ret nc
        add a,40h
        ret

; Read a line into TIB, echoing it, and end it with 0.
accept: ld de,TIB
ac1:    ld a,1Fh            ; cursor: _
        call rawkey
        cp 1Fh
        jr z,ac9
        cp 0FFh
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
        ret

space:  ld a,' '

; Print character A.  ASCII 40h-7Fh go to the display's 5-bit codes.
; Keeps everything but AF.
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

; Print the string after the CALL; its last byte has bit 7 set.
prsi:   ex (sp),hl
ps1:    ld a,(hl)
        inc hl
        push af
        and 7Fh
        call putc
        pop af
        rla
        jr nc,ps1
        ex (sp),hl
        ret

; ---------------------------------------------------------------- strings

alus:   db "ADD A",E+',',"ADC A",E+',',"SUB",E+' ',"SBC A",E+','
        db "AND",E+' ',"XOR",E+' ',"OR",E+' ',"CP",E+' '
rots:   db "RLC",E+' ',"RRC",E+' ',"RL",E+' ',"RR",E+' '
        db "SLA",E+' ',"SRA",E+' ',"SLL",E+' ',"SRL",E+' '
s_lds:  db "LD",E+' '

g0z0:   db "NO",E+'P',"EX AF,AF",E+27h,"DJNZ ",E+REL,"JR ",E+REL
s_jrcc: db "JR ",CC4,",",E+REL
g0z1:   db LDS,RPP,",",E+NW,"ADD ",HLX,",",E+RPP
g0z2:   db LDS,"(BC),",E+'A',LDS,"A,(BC",E+')'
        db LDS,"(DE),",E+'A',LDS,"A,(DE",E+')'
        db LDS,"(",NW,"),",E+HLX,LDS,HLX,",(",NW,E+')'
        db LDS,"(",NW,"),",E+'A',LDS,"A,(",NW,E+')'
g0z3:   db "INC ",E+RPP,"DEC ",E+RPP
g0z4:   db "INC ",E+RY
g0z5:   db "DEC ",E+RY
g0z6:   db LDS,RY,",",E+NB
g0z7:   db "RLC",E+'A',"RRC",E+'A',"RL",E+'A',"RR",E+'A'
        db "DA",E+'A',"CP",E+'L',"SC",E+'F',"CC",E+'F'
s_halt: db "HAL",E+'T'
s_ldrr: db LDS,RY,",",E+RZ
s_alu:  db ALU,E+RZ
g3z0:   db "RET ",E+CCY
g3z1:   db "POP ",E+RP2,"RE",E+'T',"EX",E+'X',"JP (",HLX,E+')'
        db LDS,"SP,",E+HLX
g3z2:   db "JP ",CCY,",",E+NW
g3z3:   db "JP ",E+NW
s_inv:  db E+'?'
        db "OUT (",NB,"),",E+'A',"IN A,(",NB,E+')'
        db "EX (SP),",E+HLX,"EX DE,H",E+'L',"D",E+'I',"E",E+'I'
g3z4:   db "CALL ",CCY,",",E+NW
g3z5:   db "PUSH ",E+RP2,"CALL ",E+NW
g3z6:   db ALU,E+NB
g3z7:   db "RST ",E+RSTY
g_cb:   db ROT,E+RZ,"BIT ",BITY,",",E+RZ,"RES ",BITY,",",E+RZ
        db "SET ",BITY,",",E+RZ
gedz0:  db "IN ",RY,",(C",E+')'
gedz1:  db "OUT (C),",E+RY
gedz2:  db "SBC HL,",E+RPP,"ADC HL,",E+RPP
gedz3:  db LDS,"(",NW,"),",E+RPP,LDS,RPP,",(",NW,E+')'
gedz4:  db "NE",E+'G'
gedz5:  db "RET",E+'N',"RET",E+'I'
gedz6:  db "IM ",E+IMY
gedz7:  db LDS,"I,",E+'A',LDS,"R,",E+'A',LDS,"A,",E+'I',LDS,"A,",E+'R'
        db "RR",E+'D',"RL",E+'D',"NO",E+'P',"NO",E+'P'
s_bli:  db E+BLI

rom_end:
        ds 0C00h-$,0FFh
