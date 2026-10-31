; COMP80 FORTH
;
; A small FORTH for the PSI COMP80, in the 2 KB of ROM (0400h-0BFFh) that
; held BURP.  The monitor (0000h-03FFh) is unchanged.  As with BURP, the RS
; key enters it: the monitor's NMI handler jumps to 0800h.
;
; Direct-threaded code.  Registers while FORTH runs:
;   BC = top of data stack       DE = instruction pointer (IP)
;   SP = rest of data stack      IX = return stack pointer
;   IY = NEXT (every primitive ends with JP (IY))       HL, A = scratch
;
; Text is kept in ASCII (20h-5Fh) and converted to the display's 6-bit codes
; on output.  The keyboard folds letters to 01h-1Ah; RAWKEY turns them back.
;
; Keys.  The monitor's NMI handler echoes each key at (DE) and folds codes
; 40h and up to 5 bits, so Backspace (08h) and H come out the same.  RS (the ^
; key) makes it jump to 0800h; if that happens while FORTH waits in RAWKEY
; (the return address on the stack is KEYRET), ENTRY treats it as rubout
; instead of a restart.  FS (Ctrl+\) goes back to the monitor.  Any key while
; a program runs makes the NMI handler reset to the monitor; RS then comes
; back to FORTH with the dictionary kept.
;
; Screen: line 0 shows FORTH (where the monitor shows READY); lines 1-31
; scroll.
;
; Dictionary header: link (2), length + 80h if immediate (1), name, code.
; The user dictionary starts at 0C00h, so TAPE 0C00 <HERE> saves it along
; with the three variables in front of it.

MAGIC:  equ 0C00h           ; MAGICV when the dictionary below is valid
LATEST: equ 0C02h           ; newest header
DP:     equ 0C04h           ; HERE
DICT0:  equ 0C06h           ; first free byte of a new dictionary
MAGICV: equ 0F04Dh

TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
WBUF:   equ 1D50h           ; parsed word, counted (80 bytes)
CURS:   equ 1DA0h           ; output position in screen memory
BASE:   equ 1DA2h
STATE:  equ 1DA4h           ; byte: 0 interpreting, 1 compiling
TOIN:   equ 1DA6h           ; byte: parse offset into TIB
NTIB:   equ 1DA7h           ; byte: characters in TIB
LASTH:  equ 1DA8h           ; newest header made by mkhdr
R0:     equ 1E40h           ; return stack grows down from here
S0:     equ 1F00h           ; data stack grows down from here (monitor uses 1Fxx)

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

        org 0400h

; ---------------------------------------------------------------- inner

next:   ex de,hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        inc hl
        ex de,hl
        jp (hl)

docolon:
        ex de,hl
        call rpush
        pop de
        jp (iy)

dovar:  pop hl
        push bc
        ld b,h
        ld c,l
        jp (iy)

docon:  pop hl
        push bc
        ld c,(hl)
        inc hl
        ld b,(hl)
        jp (iy)

rpush:  dec ix
        ld (ix+0),h
        dec ix
        ld (ix+0),l
        ret

rpop:   ld l,(ix+0)
        ld h,(ix+1)
        inc ix
        inc ix
        ret

lit:    push bc
        ex de,hl
        ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ex de,hl
        jp (iy)

zbranch:
        ld a,b
        or c
        pop bc
        jr z,branch
skip2:  inc de
        inc de
        jp (iy)

branch: ex de,hl
        ld e,(hl)
        inc hl
        ld d,(hl)
        jp (iy)

xdo:    pop hl              ; ( limit index -- )  R: -- limit index
        call rpush
        ld h,b
        ld l,c
        call rpush
        pop bc
        jp (iy)

xloop:  push bc
        ld bc,1
xploop: ld l,(ix+0)         ; ( n -- ) index += n
        ld h,(ix+1)
        add hl,bc
        ld (ix+0),l
        ld (ix+1),h
        push de
        ld e,(ix+2)
        ld d,(ix+3)
        call scmp           ; CY = index < limit
        pop de
        sbc a,a
        xor b               ; bit 7 set: go round again
        pop bc
        jp m,branch
        call rpop
        call rpop
        jr skip2

xdotq:  ex de,hl            ; run time of ."
        push bc
        ld b,(hl)
        inc hl
        call typen
        pop bc
        ex de,hl
        jp (iy)

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

; ---------------------------------------------------------------- words

h_exit: dw 0
        db 4,"EXIT"
exit:   call rpop
        ex de,hl
        jp (iy)

h_dup: dw h_exit
        db 3,"DUP"
        push bc
        jp (iy)

h_drop: dw h_dup
        db 4,"DROP"
drop:   pop bc
        jp (iy)

h_swap: dw h_drop
        db 4,"SWAP"
        pop hl
        push bc
rethl:  ld b,h
        ld c,l
        jp (iy)

h_over: dw h_swap
        db 4,"OVER"
        pop hl
        push hl
        push bc
        jr rethl

h_rot: dw h_over
        db 3,"ROT"
        pop hl
        ex (sp),hl
        push bc
        jr rethl

nip:    pop hl
        jp (iy)

h_tor: dw h_rot
        db 2,">R"
        ld h,b
        ld l,c
        call rpush
        pop bc
        jp (iy)

h_rfrom: dw h_tor
        db 2,"R>"
        push bc
        call rpop
        jr rethl

h_i: dw h_rfrom
        db 1,"I"
        push bc
        ld c,(ix+0)
        ld b,(ix+1)
        jp (iy)

h_j: dw h_i
        db 1,"J"
        push bc
        ld c,(ix+4)
        ld b,(ix+5)
        jp (iy)

h_plus: dw h_j
        db 1,"+"
        pop hl
        add hl,bc
        jr rethl

h_minus: dw h_plus
        db 1,"-"
        pop hl
        or a
        sbc hl,bc
        jr rethl

h_star: dw h_minus
        db 1,"*"
        pop hl
        push de
        ld d,b
        ld e,c
        call mul16
        pop de
        jr rethl

h_neg: dw h_star
        db 6,"NEGATE"
negate: ld h,b
        ld l,c
        call neghl
        jr rethl

h_slmod: dw h_neg
        db 4,"/MOD"
slmod:  pop hl              ; ( n1 n2 -- rem quot ), rounds towards zero
        push de
        ld d,b
        ld e,c
        ld a,h
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
        ex de,hl            ; DE = remainder
        ld h,b
        ld l,c
        pop af
        or a
        call m,neghl
        ld b,h
        ld c,l
        ex de,hl
        pop de
        push hl
        jp (iy)

h_div: dw h_slmod
        db 1,"/"
        call docolon
        dw slmod,nip,exit

h_mod: dw h_div
        db 3,"MOD"
        call docolon
        dw slmod,drop,exit

h_inc: dw h_mod
        db 2,"1+"
        inc bc
        jp (iy)

h_dec: dw h_inc
        db 2,"1-"
        dec bc
        jp (iy)

h_and: dw h_dec
        db 3,"AND"
        pop hl
        ld a,c
        and l
        ld c,a
        ld a,b
        and h
        ld b,a
        jp (iy)

h_or: dw h_and
        db 2,"OR"
        pop hl
        ld a,c
        or l
        ld c,a
        ld a,b
        or h
        ld b,a
        jp (iy)

h_xor: dw h_or
        db 3,"XOR"
        pop hl
        ld a,c
        xor l
        ld c,a
        ld a,b
        xor h
        ld b,a
        jp (iy)

h_0eq: dw h_xor
        db 2,"0="
        ld a,b
        or c
flagz:  ld bc,0
        jr nz,fl1
        dec bc
fl1:    jp (iy)

h_0lt: dw h_0eq
        db 2,"0<"
        ld a,b
        rla
flagc:  ld bc,0
        jr nc,fl1
        dec bc
        jp (iy)

h_eq: dw h_0lt
        db 1,"="
        pop hl
        or a
        sbc hl,bc
        jr flagz

h_lt: dw h_eq
        db 1,"<"
        pop hl
        push de
        ld d,b
        ld e,c
lt1:    call scmp
        pop de
        jr flagc

h_gt: dw h_lt
        db 1,">"
        pop hl
        push de
        ex de,hl
        ld h,b
        ld l,c
        jr lt1

h_fetch: dw h_gt
        db 1,"@"
        ld h,b
        ld l,c
        ld c,(hl)
        inc hl
        ld b,(hl)
        jp (iy)

; Parse the next word, delimited by A, from TIB into WBUF (counted).  A space
; delimiter also skips leading spaces.  Returns HL = WBUF, A = length, Z if
; empty.  Keeps BC, DE.
parse:  push bc
        push de
        ld c,a
        ld a,(NTIB)
        ld b,a
        ld a,(TOIN)
        ld l,a
        ld h,TIB/256
        ld de,WBUF+1
        ld a,c
        cp ' '
        jr nz,pa2
pa1:    ld a,l
        cp b
        jr nc,pa3
        ld a,(hl)
        cp c
        jr nz,pa2
        inc l
        jr pa1
pa2:    ld a,l
        cp b
        jr nc,pa3
        ld a,(hl)
        inc l
        cp c
        jr z,pa3
        ld (de),a
        inc de
        jr pa2
pa3:    ld a,l
        ld (TOIN),a
        ld a,e
        sub (WBUF+1)&0FFh
        ld (WBUF),a
        ld hl,WBUF
        pop de
        pop bc
        ret

h_words: dw h_fetch
        db 5,"WORDS"
        push bc
        ld hl,(LATEST)
wd1:    ld a,h
        or l
        jr z,wd9
        push hl
        inc hl
        inc hl
        ld a,(hl)
        and 1Fh
        ld b,a
        inc hl
        call typen
        call space
        pop hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jr wd1
wd9:    pop bc
        jp (iy)

        ds 06B4h-$,0FFh
; Life (life/life.asm) uses these two ROM words as return addresses: SP
; points just above them while it runs.  They were here in the BURP ROM.
        dw 127Eh,1013h

h_store: dw h_words
        db 1,"!"
        ld h,b
        ld l,c
        pop bc
        ld (hl),c
        inc hl
        ld (hl),b
        pop bc
        jp (iy)

h_cfetch: dw h_store
        db 2,"C@"
        ld a,(bc)
        ld c,a
        ld b,0
        jp (iy)

h_cstore: dw h_cfetch
        db 2,"C!"
        ld h,b
        ld l,c
        pop bc
        ld (hl),c
        pop bc
        jp (iy)

h_pstore: dw h_cstore
        db 2,"+!"
        ld h,b
        ld l,c
        pop bc
        ld a,(hl)
        add a,c
        ld (hl),a
        inc hl
        ld a,(hl)
        adc a,b
        ld (hl),a
        pop bc
        jp (iy)

h_emit: dw h_pstore
        db 4,"EMIT"
        ld a,c
        call emitc
        pop bc
        jp (iy)

h_key: dw h_emit
        db 3,"KEY"
        push bc
        call rawkey0
        ld c,a
        ld b,0
        jp (iy)

h_cr: dw h_key
        db 2,"CR"
        call crlf
        jp (iy)

h_space: dw h_cr
        db 5,"SPACE"
        call space
        jp (iy)

h_dot: dw h_space
        db 1,"."
        ld h,b
        ld l,c
        call dot
        pop bc
        jp (iy)

h_dots: dw h_dot
        db 2,".S"
        ld hl,S0            ; ( -- )  prints the stack, bottom first
        or a
        sbc hl,sp           ; 2 * depth
        push bc
        push de
        ld b,h
        ld c,l
        ld hl,S0-4
ds1:    ld a,b
        or c
        jr z,ds2
        ld e,(hl)
        inc hl
        ld d,(hl)
        dec hl
        dec hl
        dec hl
        ex de,hl
        call dot
        ex de,hl
        dec bc
        dec bc
        jr ds1
ds2:    pop de
        pop bc
        jp (iy)

h_at: dw h_dots
        db 2,"AT"
        ld h,b              ; ( col row -- )
        ld l,c
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        pop bc
        add hl,bc
        ld a,h
        and 07h
        or VRAM/256
        ld h,a
        ld (CURS),hl
        pop bc
        jp (iy)

h_page: dw h_at
        db 4,"PAGE"
        call cls
        jp (iy)

; Look WBUF up.  Found: NZ, HL = xt, A = length/flags byte.
; Not found: Z.  Keeps BC, DE.
find:   push bc
        push de
        ld hl,(LATEST)
fd1:    ld a,h
        or l
        jr z,fd9
        push hl
        inc hl
        inc hl
        ld a,(hl)
        and 1Fh
        ld b,a
        ld de,WBUF
        ld a,(de)
        cp b
        jr nz,fd3
fd2:    inc hl
        inc de
        ld a,(de)
        cp (hl)
        jr nz,fd3
        djnz fd2
        inc hl
        pop de
        inc de
        inc de
        ld a,(de)
        or a
        jr fd9
fd3:    pop hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        jr fd1
fd9:    pop de
        pop bc
        ret

; WBUF as a number in BASE, optional leading -.  HL = value, CY if not one.
number: push bc
        push de
        ld de,WBUF
        ld a,(de)
        ld b,a
        ld hl,0
        inc de
        ld a,(de)
        cp '-'
        push af             ; Z: negative
        jr nz,nu2
        dec b
        jr z,nu9
nu1:    inc de
nu2:    ld a,(de)
        sub '0'
        cp 10
        jr c,nu3
        sub 7
        cp 10
        jr c,nu9
nu3:    ld c,a
        ld a,(BASE)
        dec a
        cp c
        jr c,nu9            ; not below BASE
        push de
        inc a
        ld e,a
        ld d,0
        call mul16
        ld e,c
        add hl,de
        pop de
        djnz nu1
        pop af
        call z,neghl
        or a
        jr nu10
nu9:    pop af
        scf
nu10:   pop de
        pop bc
        ret

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If FORTH was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) FORTH.

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
        ld iy,next
        ld hl,(MAGIC)
        ld de,MAGICV
        or a
        sbc hl,de
        jr z,wm1
        ld hl,newdict       ; no dictionary in RAM: start an empty one
        ld de,MAGIC
        ld bc,6
        ldir
wm1:    ld hl,10
        ld (BASE),hl
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " FORTH",0
        call crlf
        call cls

quit:   ld ix,R0
        xor a
        ld (STATE),a
qloop:  call accept
        xor a
        ld (TOIN),a
interp: push bc             ; TOS out of the way while parsing
        ld a,' '
        call parse
        jr z,eol
        call find
        jr z,inum
        rla                 ; immediate?
        jr c,iexec
        ld a,(STATE)
        or a
        jr z,iexec
        call comma
        pop bc
        jr interp
iexec:  pop bc              ; run the word; its NEXT takes IRESC
        ld de,iresc
        jp (hl)
iresc:  dw interp
inum:   call number
        jr c,ierr
        ld a,(STATE)
        or a
        jr z,ipush
        push hl
        ld hl,lit
        call comma
        pop hl
        call comma
        pop bc
        jr interp
ipush:  ld b,h              ; old TOS stays pushed
        ld c,l
        jr interp
eol:    pop bc
        ld hl,S0
        or a
        sbc hl,sp
        jr c,uflow
        call prsi
        db " OK",0
        call crlf
        jr qloop
uflow:  call prsi
        db " EMPTY",0
        jr abort

; Unknown word (in WBUF): print it with " ?" and start again.
ierr:   ld hl,WBUF
        ld b,(hl)
        inc hl
        call typen
        call prsi
        db " ?",0
abort:  ld sp,S0
        ld a,(STATE)
        or a
        jr z,ab1
        ld hl,(LASTH)       ; drop the half-made definition
        ld (DP),hl
        ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ld (LATEST),hl
ab1:    call crlf
        jp quit

newdict: dw MAGICV,lastrom,DICT0

; ---------------------------------------------------------------- terminal

; Wait for a key.  A = glyph to show at the cursor meanwhile.  Returns A =
; ASCII key, 0Dh for Return, 08h for rubout.  Leaves the screen as it was
; (the NMI handler's echo is undone).  Keeps HL, DE.
rawkey0:
        ld hl,(CURS)        ; no cursor glyph: show what is there
        ld a,(hl)
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

; Read a line into TIB, echoing it; NTIB = length.  Changes DE.
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
ac9:    ld a,e
        ld (NTIB),a
        jp space            ; Return shows as a space

; Print character A.  ASCII 40h-7Fh go to the display's 5-bit codes;
; 80h-0FFh print graphics character A-80h.  Keeps everything but AF.
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
ps1:    ld a,(hl)
        inc hl
        or a
        jr z,ps2
        call putc
        jr ps1
ps2:    ex (sp),hl
        ret

; Print B characters from HL.  HL ends past them.
typen:  inc b
ty1:    dec b
        ret z
        ld a,(hl)
        inc hl
        call putc
        jr ty1

; Print HL (signed) in BASE, then a space.  Keeps BC, DE.
dot:    bit 7,h
        jr z,udot
        ld a,'-'
        call putc
        call neghl
udot:   push bc
        push de
        ld de,(BASE)
        call udr
        pop de
        pop bc
space:  ld a,' '
        jp putc
udr:    call udiv           ; BC = HL / BASE, HL = last digit
        push hl
        ld h,b
        ld l,c
        ld a,h
        or l
        call nz,udr
        pop hl
        ld a,l
        add a,'0'
        cp '9'+1
        jp c,putc
        add a,7
        jp putc

; ---------------------------------------------------------------- parsing

; ---------------------------------------------------------------- compiling

comma:  push de             ; compile HL.  Keeps BC, DE.
        ex de,hl
        ld hl,(DP)
        ld (hl),e
        inc hl
        ld (hl),d
        inc hl
        ld (DP),hl
        pop de
        ret

ccomma: ld hl,(DP)          ; compile byte A
        ld (hl),a
        inc hl
        ld (DP),hl
        ret

; Compile the counted string at HL.
scomma: push bc
        push de
        ld a,(hl)
        inc a
        ld c,a
        ld b,0
        ld de,(DP)
        ldir
        ld (DP),de
        pop de
        pop bc
        ret

; Parse a name and lay down its header at HERE (LASTH = it).
mkhdr:  ld a,' '
        call parse
        jp z,ierr
        cp 32
        jr c,mh1
        ld (hl),31
mh1:    ld hl,(DP)
        ld (LASTH),hl
        ld hl,(LATEST)
        call comma
        ld hl,WBUF
        jr scomma

; Header plus CALL HL, made visible at once (:, VARIABLE, CONSTANT).
mkword: push hl
        call mkhdr
        ld hl,(LASTH)
        ld (LATEST),hl
        ld a,0CDh
        call ccomma
        pop hl
        jr comma

resolve: ld hl,(DP)         ; store HERE at (BC)
        ld a,l
        ld (bc),a
        inc bc
        ld a,h
        ld (bc),a
        ret

; ---------------------------------------------------------------- words

h_here: dw h_page
        db 4,"HERE"
        push bc
        ld bc,(DP)
        jp (iy)

h_comma: dw h_here
        db 1,","
tcomma: ld h,b
        ld l,c
        call comma
        pop bc
        jp (iy)

h_allot: dw h_comma
        db 5,"ALLOT"
        ld hl,(DP)
        add hl,bc
        ld (DP),hl
        pop bc
        jp (iy)

h_base: dw h_allot
        db 4,"BASE"
        push bc
        ld bc,BASE
        jp (iy)

h_hex: dw h_base
        db 3,"HEX"
        ld a,16
        ld (BASE),a
        jp (iy)

h_decim: dw h_hex
        db 7,"DECIMAL"
        ld a,10
        ld (BASE),a
        jp (iy)

h_colon: dw h_decim
        db 1,":"
        ld hl,docolon       ; visible at once, so a word can call itself
        call mkword
        ld a,1
        ld (STATE),a
        jp (iy)

h_semi: dw h_colon
        db 81h,";"
        ld hl,exit
        call comma
        xor a
        ld (STATE),a
        jp (iy)

h_var: dw h_semi
        db 8,"VARIABLE"
        ld hl,dovar
        call mkword
        call comma          ; any value will do
        jp (iy)

h_const: dw h_var
        db 8,"CONSTANT"
        ld hl,docon
        call mkword
        jp tcomma

h_if: dw h_const
        db 82h,"IF"
        ld hl,zbranch
        call comma
        push bc
        ld bc,(DP)
        call comma          ; filled in by THEN
        jp (iy)

h_else: dw h_if
        db 84h,"ELSE"
        ld hl,branch
        call comma
        ld hl,(DP)
        push hl
        call comma
        call resolve
        pop bc
        jp (iy)

h_then: dw h_else
        db 84h,"THEN"
then:   call resolve
        pop bc
        jp (iy)

h_begin: dw h_then
        db 85h,"BEGIN"
begin:  push bc
        ld bc,(DP)
        jp (iy)

h_until: dw h_begin
        db 85h,"UNTIL"
        ld hl,zbranch
back:   call comma
        jp tcomma

h_again: dw h_until
        db 85h,"AGAIN"
        ld hl,branch
        jr back

h_while: dw h_again
        db 85h,"WHILE"
        ld hl,zbranch
        call comma
        ld hl,(DP)
        push hl             ; ( dest -- orig dest )
        call comma
        jp (iy)

h_repet: dw h_while
        db 86h,"REPEAT"
        ld hl,branch
        call comma
        ld h,b
        ld l,c
        call comma
        pop bc
        jr then

h_do: dw h_repet
        db 82h,"DO"
        ld hl,xdo
        call comma
        jr begin

h_loop: dw h_do
        db 84h,"LOOP"
        ld hl,xloop
        jr back

h_ploop: dw h_loop
        db 85h,"+LOOP"
        ld hl,xploop
        jr back

h_dotq: dw h_ploop
        db 82h,".",'"'
        ld a,'"'
        call parse
        ld a,(STATE)
        or a
        jr z,dq1
        push hl
        ld hl,xdotq
        call comma
        pop hl
        call scomma
        jp (iy)
dq1:    push bc             ; interpreting: just print it
        ld b,(hl)
        inc hl
        call typen
        pop bc
        jp (iy)

h_paren: dw h_dotq
        db 81h,"("
        ld a,')'
        call parse
        jp (iy)

h_cold: dw h_paren
        db 4,"COLD"
        ld hl,0             ; forget every word typed in
        ld (MAGIC),hl
        jp warm

lastrom:
h_bye: dw h_cold
        db 3,"BYE"
        rst 0

part2_end:
        ds 0C00h-$,0FFh
