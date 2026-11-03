; COMP80 QUEST
;
; An adventure engine with its own little language, for the PSI COMP80, in
; the 2 KB of ROM (0400h-0BFFh) that held BURP.  The monitor (0000h-03FFh)
; is unchanged.  As with BURP, the RS key enters it: the monitor's NMI
; handler jumps to 0800h.
;
; A world is typed in a line at a time, each line starting with one of
;   ROOM name description           the first ROOM is where the game starts
;   EXIT room direction room [IF flag]   a way out, usable while flag is set
;   OBJ name room description       something that can be carried
;   FIX name room description       something that can't
;   ON verb [noun] [IF condition AND condition ...] THEN action; action ...
; Conditions: HAVE obj, AT room, HERE obj (carried or in this room), a
; flag's name (set by SET), and NOT in front of any of them.  Actions: SAY
; text, SET flag, MOVE obj room (ME: carried; a word that is no room: out of
; the game), GO room, SCORE n, WIN, DIE and LOOK.
; Commands: PLAY, LIST, UNDO (forgets the last line), NEW.
;
; Words are matched by their first 4 letters.  A one-letter direction or
; verb in the world matches any word starting with that letter, so N matches
; NORTH.  In play, a command is a verb and a noun.  The rules for the verb
; come first: the first whose conditions hold runs, instead of anything
; else.  Then the built-in verbs: LOOK (L), INVENTORY (I), TAKE (GET), DROP,
; SCORE, QUIT, then the exits from the room; GO is left out (GO N is N).
;
; The world is kept as it was typed: each line its text and 0Dh, from 0C04h
; up to TXTEND.  PLAY makes a table of the objects (each the line it is on,
; and where it is now: a pointer to a room's name, or 0 when carried), and
; SET adds to a table of flags (pointers to their names), so the text itself
; is never changed.  Rooms, exits and rules are read from the text.
;
; Keys and screen are handled as in COMP80 FORTH: the monitor's NMI handler
; echoes each key and wakes the HALT in RAWKEY; RS while waiting is a rubout
; and RS at any other time (re)starts QUEST, keeping the world.  Line 0
; shows QUEST; lines 1-31 scroll.

VRAM:   equ 8000h
CLS64:  equ 0393h           ; monitor: spaces from 8040h to the end of the screen
PAD64:  equ 03C4h           ; monitor: spaces at (DE) up to the next line

MAGIC:  equ 0C00h           ; MAGICV when the world below is valid
TXTEND: equ 0C02h           ; end of the world's text
TEXT:   equ 0C04h           ; first line
MAGICV: equ 0A55Bh
TOP:    equ 1C00h           ; the text ends below here
OBJT:   equ 1C00h           ; 32 objects: line, where (4 bytes each)
FLAGT:  equ 1C80h           ; 32 flags: name (2 bytes each)
TIB:    equ 1D00h           ; input line (80 bytes; page aligned)
CURS:   equ 1DA0h           ; output position in screen memory
NOBJ:   equ 1DA2h           ; number of objects
NFLAG:  equ 1DA3h           ;   flags
STATE:  equ 1DA5h           ; 0 playing, 1 won, 2 died
SCORE:  equ 1DAAh
ROOMP:  equ 1DACh           ; the room the player is in: its name
VERB:   equ 1DAEh           ; the words typed
NOUN:   equ 1DB0h
LP:     equ 1DB2h           ; the rule being tried
S0:     equ 1F00h           ; stack (monitor uses 1Fxx)

        org 0400h

; ---------------------------------------------------------------- words

; Z if A ends a word: space, Return, ; . or ,
endw:   cp ' '
        ret z
        cp 0Dh
        ret z
        cp ';'
        ret z
        cp '.'
        ret z
        cp ','
        ret

; Z if the words at HL and DE are the same in their first 4 letters.
; Keeps everything but AF.
wordeq: push hl
        push de
        push bc
        ld b,4
we1:    ld a,(de)
        call endw
        jr nz,we2
        xor a
        jr we3
we2:    inc de
we3:    ld c,a
        ld a,(hl)
        call endw
        jr nz,we4
        xor a
        jr we5
we4:    inc hl
we5:    cp c
        jr nz,we9
        or a
        jr z,we9            ; both ended
        djnz we1
        xor a
we9:    pop bc
        pop de
        pop hl
        ret

; The same, but a one-letter word at DE matches any word at HL starting with
; that letter.
wordmt: inc de
        ld a,(de)
        dec de
        call endw
        jr nz,wordeq
        ld a,(de)
        cp (hl)
        ret

; HL = the next word after the one at HL.  Keeps all but AF, HL.
skipw:  ld a,(hl)
        call endw
        jr z,sksp
        inc hl
        jr skipw
sksp:   ld a,(hl)
        cp ' '
        jr z,sk1
        cp '.'
        jr z,sk1
        cp ','
        ret nz
sk1:    inc hl
        jr sksp

; Look up the word at HL in the list at DE (words, each followed by one
; space, then 0).  Z and A = its place in the list if found.  Keeps HL, BC.
kwd:    push bc
        ld c,0
kw1:    ld a,(de)
        or a
        jr z,kw8
        call wordeq
        jr z,kw9
kw2:    ld a,(de)
        inc de
        cp ' '
        jr nz,kw2
        inc c
        jr kw1
kw8:    inc a               ; NZ
        pop bc
        ret
kw9:    ld a,c
        cp a
        pop bc
        ret

; C if HL is before the end of the text.
atend:  push de
        ld de,(TXTEND)
        or a
        sbc hl,de
        add hl,de
        pop de
        ret

; HL = the line after the one HL is in.
nextln: ld a,(hl)
        inc hl
        cp 0Dh
        jr nz,nextln
        ret

; Store HL at DE, DE += 2.
stw:    ld a,l
        ld (de),a
        inc de
        ld a,h
        ld (de),a
        inc de
        ret

; Jump to entry A of the table of addresses at DE, keeping HL.
jtab:   ex de,hl
        add a,a
        add a,l
        ld l,a
        jr nc,jt1
        inc h
jt1:    ld a,(hl)
        inc hl
        ld h,(hl)
        ld l,a
        ex de,hl
        push de
        ret

; ---------------------------------------------------------------- the world

; IX = the object named by the word at HL; Z if there is one.  Keeps HL, DE.
findobj:
        push de
        push bc
        ld ix,OBJT
        ld a,(NOBJ)
        or a
        jr z,fo8
        ld b,a
fo1:    push hl
        ld l,(ix+0)
        ld h,(ix+1)
        call skipw
        ex de,hl            ; DE = its name
        pop hl
        call wordeq
        jr z,fo9
        ld de,4
        add ix,de
        djnz fo1
fo8:    or 1
fo9:    pop bc
        pop de
        ret

; Z if the object at IX is carried.
carried:
        ld a,(ix+2)
        or (ix+3)
        ret

; Z if the object at IX (not carried) is in this room.  Keeps HL, DE.
inroom: push hl
        push de
        ld l,(ix+2)
        ld h,(ix+3)
        ld de,(ROOMP)
        call wordeq
        pop de
        pop hl
        ret

; Z if the object at IX is carried or in this room.
ishere: call carried
        ret z
        jr inroom

; Z if the flag named at HL is set, and DE = its place.  Keeps HL, BC.
findflag:
        push bc
        ld a,(NFLAG)
        ld b,a
        inc b
        ld de,FLAGT
ff1:    dec b
        jr z,ff8
        push de
        ld a,(de)
        ld c,a
        inc de
        ld a,(de)
        ld d,a
        ld e,c
        call wordeq
        pop de
        jr z,ff9
        inc de
        inc de
        jr ff1
ff8:    or 1
ff9:    pop bc
        ret

; ---------------------------------------------------------------- printing

; Print the text at HL up to Return or ;, starting a new line rather than
; breaking a word.  Keeps BC, DE, IX.
prtext: ld a,(hl)
        cp 0Dh
        ret z
        cp ';'
        ret z
        inc hl
        cp ' '
        jr nz,pt4
        ld a,(CURS)         ; a space: none at the start of a line
        and 3Fh
        jr z,prtext
        push hl             ; is there room for the next word?
        push bc
        ld b,0
pt1:    ld a,(hl)
        cp ' '
        jr z,pt2
        cp 0Dh
        jr z,pt2
        cp ';'
        jr z,pt2
        inc b
        inc hl
        jr pt1
pt2:    ld a,(CURS)
        and 3Fh
        add a,b
        pop bc
        pop hl
        cp 64
        jr c,pt3
        call crlf
        jr prtext
pt3:    ld a,' '
pt4:    call putc
        jr prtext

; Print the description of the object at IX on a line of its own.
objdesc:
        ld l,(ix+0)
        ld h,(ix+1)
        call skipw
        call skipw
        call skipw
        call prtext
        jp crlf

; ---------------------------------------------------------------- the room

look:   call newl
        ld hl,TEXT
lk1:    call atend
        jr nc,lk3
        ld a,(hl)
        cp 'R'              ; ROOM is the only line starting with R
        jr nz,lk2
        push hl
        call skipw
        ld de,(ROOMP)
        call wordeq
        jr nz,lk15
        call skipw
        call prtext
        call crlf
        pop hl
        jr lk3
lk15:   pop hl
lk2:    call nextln
        jr lk1
lk3:    ld a,(NOBJ)         ; what is here
        or a
        jr z,lk5
        ld b,a
        ld ix,OBJT
lk4:    call carried
        jr z,lk45
        call inroom
        jr nz,lk45
        call prsi
        db "YOU SEE ",0
        call objdesc
lk45:   ld de,4
        add ix,de
        djnz lk4
lk5:    ld hl,TEXT          ; the ways out
        xor a
        push af             ; none yet
lx1:    call atend
        jr nc,lx9
        call exitln
        jr nz,lx8
        pop af
        or a
        jr nz,lx2
        call prsi
        db "EXITS:",0
lx2:    ld a,1
        push af
        ld a,' '
        call putc
        ex de,hl
        call prword
        ex de,hl
lx8:    call nextln
        jr lx1
lx9:    pop af
        or a
        ret z
        jp crlf

; Z and HL = where it goes, if an exit from this room has the direction
; typed as the verb.
findexit:
        ld hl,TEXT
fe1:    call atend
        jr nc,fe8
        call exitln
        jr nz,fe7
        push hl
        ld hl,(VERB)
        call wordmt
        pop hl
        jr nz,fe7
        ld h,b
        ld l,c
        ret
fe7:    call nextln
        jr fe1
fe8:    or 1
        ret

; ---------------------------------------------------------------- rules

; Run the first rule for the words at (VERB) and (NOUN) whose conditions
; hold.  Z if there was one.
rules:  ld hl,TEXT
ru1:    call atend
        jr nc,ru9
        ld (LP),hl
        ld a,(hl)
        cp 'O'
        jr nz,ru8
        inc hl
        ld a,(hl)
        dec hl
        cp 'N'
        jr nz,ru8           ; not an ON line
        call skipw
        ex de,hl
        ld hl,(VERB)
        call wordmt
        ex de,hl
        jr nz,ru8
        call skipw
        ld de,w_if
        call wordeq
        jr z,ru3
        ld de,w_then
        call wordeq
        jr z,ru5
        ex de,hl            ; a noun
        ld hl,(NOUN)
        call wordeq
        ex de,hl
        jr nz,ru8
        call skipw
        ld de,w_if
        call wordeq
        jr nz,ru5
ru3:    call skipw          ; a condition
        call cond
        jr nz,ru8
        ld de,w_and
        call wordeq
        jr z,ru3
ru5:    ld de,w_then
        call wordeq
        jr nz,ru8
        call skipw
        call actions
        xor a
        ret
ru8:    ld hl,(LP)
        call nextln
        jr ru1
ru9:    or 1
        ret

; The condition at HL: Z if it holds; HL past it.
cond:   ld de,w_not
        call wordeq
        jr nz,cd1
        call skipw
        call cond
        jr z,cd0
        xor a
        ret
cd0:    or 1
        ret
cd1:    ld de,condtab       ; HAVE AT HERE
        call kwd
        jr nz,cdflag
        ld c,a
        call skipw
        dec c
        jr z,cdat
        call findobj
        jr nz,cd8
        inc c
        jr z,cdhave
        call ishere
        jr cd8
cdhave: call carried
        jr cd8
cdat:   ld de,(ROOMP)
        call wordeq
        jr cd8
cdflag: call findflag
cd8:    push af
        call skipw
        pop af
        ret

; Run the actions at HL, separated by ;
actions:
        ld a,(hl)
        cp 0Dh
        ret z
        ld de,acttab
        call kwd
        push af
        call skipw
        pop af
        jr nz,an8
        push hl
        ld de,acttbl
        call jtab
        pop hl
an8:    ld a,(hl)           ; on to the next
        cp 0Dh
        ret z
        inc hl
        cp ';'
        jr nz,an8
        call sksp
        jr actions

acttbl: dw asay,aset,amove,ago,ascore,awin,adie,look

asay:   call prtext
        jp crlf

aset:   call findflag
        ret z
        ld a,(NFLAG)
        cp 32
        ret nc
        call stw
        ld hl,NFLAG
        inc (hl)
        ret

amove:  call findobj
        ret nz
        call skipw
        ld de,w_me
        call wordeq
        jr nz,am2
        ld hl,0
am2:    ld (ix+2),l
        ld (ix+3),h
        ret

ago:    ld (ROOMP),hl
        jp look

awin:   ld a,1
        jr ad1
adie:   ld a,2
ad1:    ld (STATE),a
        ret

; ---------------------------------------------------------------- words

deftab: db "ROOM EXIT OBJ FIX ON PLAY LIST UNDO NEW ",0
verbtab:
        db "QUIT LOOK L INVENTORY I TAKE GET DROP SCORE ",0
condtab:
        db "HAVE AT HERE ",0
acttab: db "SAY SET MOVE GO SCORE WIN DIE LOOK ",0
w_if:   db "IF "
w_then: db "THEN "
w_and:  db "AND "
w_not:  db "NOT "
w_go:   db "GO "
w_me:   db "ME "

part1_end:
        ds 0800h-$,0FFh

; ---------------------------------------------------------------- entry
; 0800h: the monitor's NMI handler jumps here for RS.  If QUEST was waiting
; for a key, the NMI's return address (KEYRET) is on top of the stack: give
; RAWKEY a rubout (0FFh).  Otherwise start (or restart) QUEST.

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
        call nz,new0        ; no world in RAM: start an empty one
        ld hl,VRAM
        ld (CURS),hl
        call prsi
        db " QUEST",0
        ld hl,VRAM+40h
        ld (CURS),hl
        call CLS64

ready:  ld sp,S0
        call newl
        call msgl
        db "OK",0
getln:  ld sp,S0
        call accept
        ld hl,TIB
        call sksp
        ld a,(hl)
        cp 0Dh
        jr z,getln
        ld de,deftab
        call kwd
        jr nz,erwhat
        cp 5
        jr c,store
        jr z,play
        cp 7
        jr c,list
        jp z,undo
        call new0
        jr ready

erwhat: call msgl
        db "WHAT?",0
        jr getln

; A line of the world: add it to the text.
store:  ld de,(TXTEND)
st1:    ld a,d
        cp TOP/256
        jr nc,erfull
        ld a,(hl)
        ld (de),a
        inc hl
        inc de
        cp 0Dh
        jr nz,st1
        ld (TXTEND),de
        jr getln
erfull: call msgl
        db "FULL",0
        jr getln

list:   ld hl,TEXT
ls1:    call atend
        jr nc,ready
ls2:    ld a,(hl)
        inc hl
        cp 0Dh
        jr z,ls3
        call putc
        jr ls2
ls3:    call crlf
        jr ls1

new0:   ld hl,MAGICV
        ld (MAGIC),hl
        ld hl,TEXT
        ld (TXTEND),hl
        ret

; ---------------------------------------------------------------- play

play:   xor a               ; no objects or flags; playing
        ld (NOBJ),a
        ld (NFLAG),a
        ld (STATE),a
        ld h,a
        ld l,a
        ld (SCORE),hl
        ld (ROOMP),hl
        ld hl,TEXT
pa1:    call atend
        jr nc,pa5
        push hl
        ld de,deftab
        call kwd
        ld c,a
        call skipw          ; the first word after the keyword
        ld a,c
        or a
        jr nz,pa2
        ld de,(ROOMP)       ; ROOM: the first is the start
        ld a,d
        or e
        jr nz,pa4
        ld (ROOMP),hl
        jr pa4
pa2:    cp 2
        jr c,pa4            ; EXIT
        cp 4
        jr nc,pa4           ; ON
        ld a,(NOBJ)         ; OBJ or FIX
        cp 32
        jr nc,pa4
        add a,a
        add a,a
        ld e,a
        ld d,0
        ld ix,OBJT
        add ix,de
        pop de
        push de
        ld (ix+0),e         ; its line
        ld (ix+1),d
        call skipw
        ld (ix+2),l         ; where it starts
        ld (ix+3),h
        ld hl,NOBJ
        inc (hl)
pa4:    pop hl
        call nextln
        jr pa1
pa5:    call look

; Each turn: a command, then the TURN rules.
turn:   ld sp,S0
        call newl
        ld a,'>'
        call putc
        call accept
        ld hl,TIB
        call sksp
        ld a,(hl)
        cp 0Dh
        jr z,turn
        ld (VERB),hl
        call skipw
        ld (NOUN),hl
        ld hl,(VERB)        ; GO N is N
        ld de,w_go
        call wordeq
        jr nz,tu1
        ld hl,(NOUN)
        ld (VERB),hl
        call skipw
        ld (NOUN),hl
tu1:    xor a
        call rules
        jr z,after
        ld hl,(VERB)
        ld de,verbtab
        call kwd
        jr nz,tu2
        ld de,verbtbl
        call jtab
        jr after
tu2:    call findexit
        jr nz,tu3
        ld (ROOMP),hl
        call look
        jr after
tu3:    ld hl,(VERB)
        inc hl
        ld a,(hl)
        call endw
        jr nz,tu4
        call msgl
        db "NO WAY.",0
        jr after
tu4:    call msgl
        db "WHAT?",0

after:  ld a,(STATE)
        or a
        jp z,turn
gend:   dec a
        jr nz,gdied
        call msgl
        db "YOU WIN!",0
        jr gsc
gdied:  call msgl
        db "YOU ARE DEAD.",0
gsc:    call bscore
        jp ready

verbtbl:
        dw ready,look,look,binv,binv,btake,btake,bdrop,bscore

bscore: call prsi
        db "SCORE ",0
        ld hl,(SCORE)
        call prnum
        jp crlf

binv:   call msgl
        db "YOU HAVE:",0
        ld a,(NOBJ)
        or a
        ret z
        ld b,a
        ld ix,OBJT
bi1:    call carried
        call z,objdesc
        ld de,4
        add ix,de
        djnz bi1
        ret

btake:  call bfind
        ret nz
        call ishere
        jr nz,bnot
        ld l,(ix+0)
        ld h,(ix+1)
        ld a,(hl)
        cp 'F'
        jr nz,bt2
        call msgl
        db "TOO HEAVY.",0
        ret
bt2:    ld hl,0
        jr bok

bdrop:  call bfind
        ret nz
        call carried
        jr nz,bnot
        ld hl,(ROOMP)
bok:    ld (ix+2),l
        ld (ix+3),h
        call msgl
        db "OK.",0
        ret

; IX = the object named by the noun; NZ (and a message) if there is none.
bfind:  ld hl,(NOUN)
        call findobj
        ret z
bnot:   call msgl
        db "NOT HERE.",0
        or 1
        ret

; ---------------------------------------------------------------- strings

; New line unless at the start of one.
newl:   ld a,(CURS)
        and 3Fh
        ret z
        jp crlf

; Print the string after the CALL, up to a 0 byte (msgl: and a new line).
; Keep everything but AF.
msgl:   ex (sp),hl
        call prs
        ex (sp),hl
        jp crlf
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

; Read a line into TIB, echoing it, ending with 0Dh.
accept: ld de,TIB
ac1:    ld a,1Fh            ; cursor: _
        call rawkey
        cp 0Dh
        jr z,ac9
        cp 8
        jr z,ac3
        ld (de),a
        ld a,e
        cp 150
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

; Print HL.  Keeps BC, DE.
prnum:  push bc
        push de
        ld b,0
        ld de,-100
        call pd
        ld de,-10
        call pd
        ld a,l
        add a,'0'
        call putc
        pop de
        pop bc
        ret
pd:     ld a,'0'-1
pd1:    inc a
        add hl,de
        jr c,pd1
        sbc hl,de
        cp '0'
        jr nz,pd2
        inc b
        dec b
        ret z               ; no digit yet
pd2:    ld b,1
        jp putc

; For the line at HL: Z if it is an EXIT from this room that can be used
; (its flag is set, if it has IF flag), with DE = its direction and BC =
; where it goes.  Keeps HL.
exitln: ld a,(hl)
        cp 'E'              ; EXIT is the only line starting with E
        ret nz
        push hl
        call skipw          ; from
        ld de,(ROOMP)
        call wordeq
        jr nz,el9
        call skipw          ; which way
        ld d,h
        ld e,l
        call skipw          ; to
        ld b,h
        ld c,l
        call skipw
        push de
        ld de,w_if
        call wordeq
        pop de
        jr nz,el8
        call skipw
        push de
        call findflag
        pop de
        jr el9
el8:    xor a
el9:    pop hl
        ret

; Print the word at HL.
prword: ld a,(hl)
        call endw
        ret z
        call putc
        inc hl
        jr prword

; SCORE n: add n to the score.
ascore: ld de,0
as1:    ld a,(hl)
        sub '0'
        cp 10
        jr nc,as2
        inc hl
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
        jr as1
as2:    ld hl,(SCORE)
        add hl,de
        ld (SCORE),hl
        ret

; UNDO: forget the last line of the world.
undo:   ld hl,(TXTEND)
        ld de,TEXT
        or a
        sbc hl,de
        jr z,ud3
        add hl,de
        dec hl
ud1:    dec hl
        or a
        sbc hl,de
        add hl,de
        jr c,ud2
        ld a,(hl)
        cp 0Dh
        jr nz,ud1
ud2:    inc hl
        ld (TXTEND),hl
ud3:    jp ready

part2_end:
        ds 0C00h-$,0FFh
