; COMP80 STORM, a shooting game for the PSI COMP80, in Z80 machine code
;
; Chains of segments weave down the screen in a storm.  The cannon at the
; bottom moves left and right and fires up; a hit on a segment breaks it out
; of its chain, and the segments behind it go off as a chain of their own,
; with the next one as its head.  Grey segments follow, solid ones are heads
; and starred ones drop bombs.  A chain that reaches the bottom creeps along
; it towards the cannon.  Each shot costs energy, which comes back with time.
; Clear the screen for the next wave, a little faster.  Three cannons.
;
;   LOAD at 1000h, RUN 1000.  Keys: Z or , left, X or . right, space or
;   Return fire, Q back to the monitor.  The byte at 1003h is the length of
;   a frame in digit times of the calculator chip (about 0.5 ms each).
;
; Taking keys while it runs
; -------------------------
; As in the memory dump (dump/dump.asm), the stack pointer is kept in ROM, at
; 0364h.  A key's NMI pushes nothing; the monitor's handler finds the ROM word
; at 0362h, 1278h, sees the HALT at 1277h (the HALT of the wait) and returns to
; KEYH with the key in A.  Return goes through PAD_TO_NEXT_LINE, whose walk
; down the ROM words ends at 101Eh with A = 03h; so does a key that comes while
; a digit interrupt is being taken (SP 0362h, word 0360h = 101Eh).  101Dh is a
; HALT and 101Eh jumps to KEYH.  There is no CALL, PUSH or POP: subroutines
; return through JP (IY), and DE is kept pointing at SCRATCH, where the
; handler writes; Return pads the line at DE, which only works at the start of
; a line, so there is no LDIR either.
;
; A key can come in the middle of anything, and KEYH carries on from the
; start of whatever part of the frame was going on (PHASE):
;   0  copy the game S to W and work out the next frame in W
;   3  copy W back to S: W is complete, so copying again is safe
;   1  draw W into a buffer
;   4  copy the buffer to the screen, from the line it got to
;   2  wait for the rest of the frame
; so a frame is never half done.  The wait is spent in HALTs: the chip is
; told to put out a number, and each of its 12 digits is an interrupt
; (IM 2, through the table at 0E00h), so the computer is nearly always
; waiting in a HALT when a key comes.

TRAPSP:  equ 0364h          ; ROM words: 0362h = 1278h, 0360h = 101Eh
SCRATCH: equ 0C00h          ; the NMI handler writes the key here
VRAM:    equ 8000h
BUFLEN:  equ 30*64
BUF:     equ 2000h-BUFLEN    ; lines 2-31 of the screen, drawn here first

; variables outside the game (written by KEYH)
PHASE:   equ 0C40h
MOVEDIR: equ 0C41h          ; 01h right, FFh left
MOVETL:  equ 0C42h          ; frames still to move
FIREQ:   equ 0C43h          ; counts fire keys
ANYKEY:  equ 0C44h          ; counts all keys
TICKS:   equ 0C45h          ; digit times left in this frame
BURST:   equ 0C46h          ; digits still to come from the chip
CHIPON:  equ 0C47h          ; 1 while the chip is putting out a number
PRET:    equ 0C48h          ; return address for PDEC
TMPW:    equ 0C4Ah          ; to 0C5Fh: scratch words
FRAMES:  equ 0C60h          ; frame count, for measuring the speed
BLITP:   equ 0C62h          ; the line of the buffer being copied
VECTAB:  equ 0E00h          ; IM 2: words at 0EE3h (MAME) and 0EFFh

; the game: W is worked on, S is the copy kept between frames
W:       equ 0D00h
S:       equ 0F10h          ; (0EFFh-0F00h is an IM 2 vector)
SIZE:    equ 0F0h
MODE:    equ W+0            ; 0 title, 1 playing, 2 hit, 3 game over
FRAME:   equ W+1
PX:      equ W+2            ; the cannon's column, 1-62
ENERGY:  equ W+3            ; 0-40; a shot costs 10
SCORE:   equ W+4
LIVES:   equ W+6
WAVE:    equ W+7
STEPT:   equ W+8            ; frames to the chains' next step
TIMER:   equ W+9
FIREDN:  equ W+10           ; fire keys dealt with
ANYDN:   equ W+11           ; keys dealt with
SEED:    equ W+12
STEPS:   equ W+14
BULLETS: equ W+16           ; 2 x (column, half line); FFh: none
BOMBS:   equ W+20           ; 8 x (column, half line)
SPARKS:  equ W+36           ; spare, cleared with the segments
SEGS:    equ W+48           ; 32 x 6: column, line, flags, step, run
NSEG:    equ 32
F_LIVE:  equ 1
F_HEAD:  equ 2
F_BOMB:  equ 4
BOTTOM:  equ 27             ; the line the chains creep along
MAXE:    equ 40

; a random byte in A (uses BC, HL)
rnd:    macro
        ld hl,(SEED)
        ld b,h
        ld c,l
        add hl,hl
        add hl,hl
        add hl,bc
        ld bc,3619h
        add hl,bc
        ld (SEED),hl
        ld a,h
        endm

        org 1000h
        jp start
framet: db 22               ; 1003h: digit times a frame

; copy B bytes from HL to IX
copy:   ld a,(hl)
        ld (ix+0),a
        inc hl
        inc ix
        djnz copy
        jp (iy)
; clear B bytes at HL
zero:   ld (hl),0
        inc hl
        djnz zero
        jp (iy)
        ds 101Dh-$
        db 76h              ; HALT: makes 101Eh acceptable to the NMI handler
        jp keyh             ; 101Eh: a key while a digit interrupt was being taken

quit:
quit1:  im 1
        jp 0000h

start:  di
        ld sp,TRAPSP
        im 2
        ld a,VECTAB/256
        ld i,a
        ld hl,irqh
        ld (VECTAB+0E3h),hl
        ld (VECTAB+0FFh),hl
        ld de,SCRATCH
        ld hl,PHASE         ; clear the variables and the game
        ld b,16
        ld iy,st1
        jp zero
st1:    ld hl,S
        ld b,SIZE
        ld iy,st2
        jp zero
st2:    ld hl,BUF           ; and the buffer
        ld bc,BUFLEN
st3:    ld (hl),20h
        inc hl
        dec bc
        ld a,b
        or c
        jr nz,st3
        ld a,r
        ld (S+12),a         ; SEED
        ld (S+13),a

; ---- the next frame ------------------------------------------------------
frame:  xor a
        ld (PHASE),a
        ld hl,S
        ld ix,W
        ld b,SIZE
        ld iy,frame1
        jp copy
frame1:
        ld hl,FRAME
        inc (hl)
        ld a,(MODE)
        cp 1
        jp z,play
        cp 2
        jp z,hit
        ; title or game over: a key starts a game once TIMER is 0
        ld a,(ANYKEY)
        ld b,a
        ld a,(TIMER)
        or a
        jr z,tkey
        dec a
        ld (TIMER),a
        ld a,b
        ld (ANYDN),a
        jp done
tkey:   ld a,(ANYDN)
        cp b
        jp z,done
        ; a new game
        ld a,b
        ld (ANYDN),a
        ld a,(FIREQ)
        ld (FIREDN),a
        ld hl,0
        ld (SCORE),hl
        ld a,3
        ld (LIVES),a
        ld a,1
        ld (WAVE),a
        ld (MODE),a
        ld a,32
        ld (PX),a
        ld iy,done
        jp newwave

; the cannon was hit: wait, then start the wave again or stop
hit:    ld a,(FIREQ)
        ld (FIREDN),a
        ld hl,TIMER
        dec (hl)
        jp nz,done
        ld a,(LIVES)
        or a
        jr nz,again
        ld a,3
        ld (MODE),a
        ld a,40
        ld (TIMER),a
        jp done
again:  ld a,1              ; the wave starts again
        ld (MODE),a
        ld iy,done
        jp newwave

; ---- playing -------------------------------------------------------------
play:   ld a,(MOVETL)       ; still moving?
        or a
        jr z,pfire
        dec a
        ld (MOVETL),a
        ld a,(MOVEDIR)
        ld b,a
        ld a,(PX)
        add a,b
        cp 1
        jr c,pfire
        cp 63
        jr nc,pfire
        ld (PX),a
pfire:  ld a,(FRAME)        ; energy comes back
        and 1
        jr z,pf1
        ld a,(ENERGY)
        cp MAXE
        jr nc,pf1
        inc a
        ld (ENERGY),a
pf1:    ld a,(FIREQ)
        ld b,a
        ld a,(FIREDN)
        cp b
        jr z,pbul
        ld a,b
        ld (FIREDN),a
        ld a,(ENERGY)
        cp 10
        jr c,pbul
        ld hl,BULLETS+1
        ld a,(hl)
        inc a
        jr z,pf2            ; this one is free
        inc hl
        inc hl
        ld a,(hl)
        inc a
        jr nz,pbul          ; both in flight
pf2:    ld a,55
        ld (hl),a
        dec hl
        ld a,(PX)
        ld (hl),a
        ld a,(ENERGY)
        sub 10
        ld (ENERGY),a

; the bullets: look for a hit where each is, move it up two half lines,
; and look again
pbul:   ld ix,BULLETS
        ld b,2
pb1:    ld a,(ix+1)
        cp 0FFh
        jr z,pb4
        ld (TMPW+10),bc
        ld iy,pb2
        jp shot
pb2:    ld a,(ix+1)
        cp 0FFh
        jr z,pb3
        sub 2
        jr nc,pb2a
        ld a,0FFh
pb2a:   ld (ix+1),a
        cp 0FFh
        jr z,pb3
        ld iy,pb3
        jp shot
pb3:    ld bc,(TMPW+10)
pb4:    inc ix
        inc ix
        djnz pb1

; the chains take a step every few frames
        ld hl,STEPT
        dec (hl)
        jp nz,pbomb
        ld a,(WAVE)
        inc a
        srl a
        ld b,a
        ld a,6
        sub b
        cp 2
        jr nc,ps0
        ld a,2
ps0:    ld (STEPT),a
        ld hl,STEPS
        inc (hl)
        ; followers take the place of the segment in front, from the back
        ld ix,SEGS+(NSEG-1)*6
        ld b,NSEG-1
ps1:    ld a,(ix+2)
        and F_LIVE+F_HEAD
        cp F_LIVE
        jr nz,ps2
        ld a,(ix-6)
        ld (ix+0),a
        ld a,(ix-5)
        ld (ix+1),a
ps2:    ld de,-6
        add ix,de
        ld de,SCRATCH
        djnz ps1
        ; then the heads move
        ld ix,SEGS
        ld b,NSEG
ph1:    ld a,(ix+2)
        and F_LIVE+F_HEAD
        cp F_LIVE+F_HEAD
        jp nz,ph9
        ld a,(ix+1)
        cp BOTTOM
        jr c,ph3
        ; along the bottom towards the cannon, every other step
        ld a,(STEPS)
        and 1
        jp z,ph9
        ld a,(PX)
        cp (ix+0)
        jp z,ph9
        ld a,1
        jr nc,ph2
        ld a,0FFh
ph2:    add a,(ix+0)
        ld (ix+0),a
        jp ph9
ph3:    dec (ix+4)          ; the run along a line is over: drop a line
        jr nz,ph5
        inc (ix+1)
        ld (TMPW),bc
        rnd
        ld c,a
        and 7
        add a,2
        ld (ix+4),a
        ld a,c
        and 30h             ; and now and then turn round
        jr nz,ph4
        ld a,(ix+3)
        neg
        ld (ix+3),a
ph4:    ld bc,(TMPW)
        jp ph9
ph5:    ld a,(ix+0)         ; along the line, turning down at the sides
        add a,(ix+3)
        cp 64
        jr c,ph6
        ld a,(ix+3)
        neg
        ld (ix+3),a
        inc (ix+1)
        jp ph9
ph6:    ld (ix+0),a
        jr ph9
        ds 1276h-$
; ---- the HALT of the wait, and a key: A = its code --------------------------
; The NMI handler returns to the ROM word at 0362h, 1278h, just after this
; HALT; with a digit interrupt half taken (SP 0362h) it uses 0360h, 101Eh.
dhalt:  ei
        halt                ; 1277h: makes 1278h acceptable to the NMI handler
keyh:   di                  ; 1278h
        ld sp,TRAPSP
        ld de,SCRATCH
        cp 11h              ; Q
        jp z,quit
        ld c,a
        ld hl,ANYKEY
        inc (hl)
        ld a,c
        cp 1Ah              ; Z
        jr z,kleft
        cp 2Ch              ; ,
        jr z,kleft
        cp 18h              ; X
        jr z,kright
        cp 2Eh              ; .
        jr z,kright
        cp 20h              ; space
        jr z,kfire
        cp 03h              ; Return
        jr nz,kdisp
kfire:  ld hl,FIREQ
        inc (hl)
        jr kdisp
kleft:  ld a,0FFh
        jr kmove
kright: ld a,1
kmove:  ld (MOVEDIR),a
        ld a,6              ; move for 6 frames
        ld (MOVETL),a
kdisp:  ld a,(PHASE)
        cp 4
        jr z,blres
        cp 3
        jp z,commit
        cp 1
        jp z,render
        cp 2
        jp z,dloop
        jp frame

blres:  ld hl,(BLITP)
        jp bl0

; ---- a digit from the chip ----------------------------------------------
irqh:   ld sp,TRAPSP
        ld de,SCRATCH
        ld hl,TICKS
        dec (hl)
        ld hl,BURST
        dec (hl)
        jp dloop

ph9:    ld a,(ix+1)
        cp BOTTOM+1
        jr c,ph10
        ld (ix+1),BOTTOM
ph10:   ld de,6
        add ix,de
        ld de,SCRATCH
        dec b
        jp nz,ph1
        ; bombs, and a chain over the cannon
        ld ix,SEGS
        ld b,NSEG
pd1:    ld a,(ix+2)
        bit 0,a
        jr z,pd4
        ld c,a
        ld a,(ix+1)
        cp BOTTOM
        jr nz,pd2
        ld a,(PX)
        cp (ix+0)
        jp z,dead
pd2:    bit 2,c
        jr z,pd4
        ld (TMPW),bc
        rnd
        ld bc,(TMPW)
        and 0Fh
        jr nz,pd4
        ld hl,BOMBS+1       ; a free bomb
        ld c,8
pd3:    ld a,(hl)
        inc a
        jr z,pd3a
        inc hl
        inc hl
        dec c
        jr nz,pd3
        jr pd4
pd3a:   ld a,(ix+1)
        add a,a
        add a,2
        ld (hl),a
        dec hl
        ld a,(ix+0)
        ld (hl),a
pd4:    ld de,6
        add ix,de
        ld de,SCRATCH
        djnz pd1

; bombs fall a half line a frame
pbomb:  ld ix,BOMBS
        ld b,8
pm1:    ld a,(ix+1)
        cp 0FFh
        jr z,pm3
        inc a
        cp 60
        jr c,pm2
        ld a,0FFh
pm2:    ld (ix+1),a
        cp 56
        jr c,pm3
        cp 0FFh
        jr z,pm3
        ld a,(PX)
        sub (ix+0)
        jr nc,pm2a
        neg
pm2a:   cp 2
        jp c,dead
pm3:    inc ix
        inc ix
        djnz pm1
        ; all gone: the next wave
        ld ix,SEGS
        ld b,NSEG
pw1:    bit 0,(ix+2)
        jp nz,done
        ld de,6
        add ix,de
        ld de,SCRATCH
        djnz pw1
        ld hl,(SCORE)
        ld bc,100
        add hl,bc
        ld (SCORE),hl
        ld hl,WAVE
        inc (hl)
        ld iy,done
        jp newwave

; the cannon is hit
dead:   ld a,2
        ld (MODE),a
        ld a,30
        ld (TIMER),a
        ld hl,LIVES
        dec (hl)
        jp done

; ---- the rest of the frame, in HALTs ---------------------------------------
dloop:  ld de,SCRATCH
        ld a,(TICKS)
        dec a
        cp 7Fh
        jp nc,frame         ; no time left
        ld a,(BURST)
        dec a
        cp 7Fh
        jr c,dwait          ; digits still to come
        ld a,(CHIPON)
        or a
        jr z,dstart
dfin:   in a,(3)            ; the number is out: finish it
        and 20h
        jr nz,dfin
        ld a,3Fh
        out (60h),a
        ld a,0BFh
        out (60h),a
        xor a
        ld (CHIPON),a
dstart: in a,(3)            ; and ask for another
        and 20h
        jr nz,dstart
        ld a,16h            ; OUT
        out (60h),a
        ld a,96h
        out (60h),a
        ld a,12
        ld (BURST),a
        ld a,1
        ld (CHIPON),a
dwait:  in a,(3)
        and 20h
        jp nz,dhalt
        xor a               ; the chip has finished: count lost
        ld (BURST),a
        jr dloop
; ---- a bullet at (IX): has it hit a segment?  Returns through IY --------
shot:   ld a,(ix+1)
        srl a
        ld c,a              ; its line
        ld hl,SEGS
        ld b,NSEG
sh1:    ld a,(hl)           ; column
        cp (ix+0)
        jr nz,sh2
        inc hl
        ld a,(hl)
        dec hl
        cp c
        jr nz,sh2
        inc hl
        inc hl
        bit 0,(hl)
        dec hl
        dec hl
        jr nz,sh3
sh2:
        ld a,l
        add a,6
        ld l,a
        jr nc,sh2a
        inc h
sh2a:   djnz sh1
        jp (iy)
sh3:    ; hit: HL points at the segment
        ld (ix+1),0FFh      ; the bullet is spent
        ld (TMPW),hl
        inc hl
        inc hl
        ld a,(hl)
        ld (hl),0
        ld b,10
        bit 1,a
        jr z,sh4
        ld b,25
sh4:
        ld a,(SCORE)
        add a,b
        ld (SCORE),a
        jr nc,sh5
        ld a,(SCORE+1)
        inc a
        ld (SCORE+1),a
sh5:
        ld hl,(TMPW)        ; the segment behind leads its own chain
        ld bc,6
        add hl,bc
        ld a,h
        cp (SEGS+NSEG*6)/256
        jr nz,sh9
        ld a,l
        cp (SEGS+NSEG*6) & 0FFh
        jr nc,sh10
sh9:    inc hl
        inc hl
        ld a,(hl)
        and F_LIVE+F_HEAD
        cp F_LIVE
        jr nz,sh10
        set 1,(hl)
        inc hl
        ld (TMPW),hl
        rnd
        ld hl,(TMPW)
        rra
        ld a,1
        jr c,sh9a
        ld a,0FFh
sh9a:   ld (hl),a           ; its way
        inc hl
        ld (hl),1           ; and it drops a line at once
sh10:   jp (iy)

; ---- a new wave: chains along the top lines; returns through IY ---------
newwave: ld (PRET),iy
        ld hl,BULLETS       ; no bullets or bombs
        ld b,10
cs1:    ld (hl),0
        inc hl
        ld (hl),0FFh
        inc hl
        djnz cs1
        ld hl,SPARKS
        ld b,12+NSEG*6
nw0:    ld (hl),0
        inc hl
        djnz nw0
        ld a,MAXE
        ld (ENERGY),a
        ld a,10
        ld (STEPT),a
        ; chains: 1 + (wave-1)/2, at most 3; segments 12 + 4 x wave, at most 30
        ld a,(WAVE)
        dec a
        srl a
        inc a
        cp 4
        jr c,nw1
        ld a,3
nw1:    ld (TMPW),a         ; chains
        ld a,(WAVE)
        add a,a
        add a,a
        add a,12
        cp 31
        jr c,nw2
        ld a,30
nw2:    ld b,a              ; segments / chains
        ld a,(TMPW)
        ld c,a
        ld a,b
        ld b,0
nw3:    inc b
        sub c
        jr nc,nw3
        dec b
        ld a,b
        ld (TMPW+1),a       ; segments in each chain
        ld ix,SEGS
        ld c,0              ; chain number
nw4:    ld a,(TMPW)
        cp c
        jr z,nw9
        ; head column and way: even chains from the left going right
        ld a,(TMPW+1)
        ld b,a
        bit 0,c
        jr nz,nw5
        dec a               ; head at len-1, going right
        ld h,a
        ld l,1
        jr nw6
nw5:    ld a,64
        sub b
        ld h,a
        ld l,0FFh
nw6:    ld a,c
        add a,a             ; line 2 x chain
        ld (TMPW+2),a
        ld a,1              ; the first is the head
        ld (TMPW+3),a
nw7:    ld (ix+0),h
        ld a,(TMPW+2)
        ld (ix+1),a
        ld (ix+3),l
        ld a,(TMPW+3)
        or a
        ld a,F_LIVE+F_HEAD
        jr nz,nw8
        ld a,b
        and 3
        ld a,F_LIVE
        jr nz,nw8
        ld a,F_LIVE+F_BOMB
nw8:    ld (ix+2),a
        ld (ix+4),3
        xor a
        ld (TMPW+3),a
        ld a,h              ; the next one behind
        sub l
        ld h,a
        ld de,6
        add ix,de
        ld de,SCRATCH
        djnz nw7
        inc c
        jr nw4
nw9:    ld iy,(PRET)
        jp (iy)

; ---- the frame is worked out: keep it --------------------------------------
done:   ld a,3
        ld (PHASE),a
commit: ld hl,W
        ld ix,S
        ld b,SIZE
        ld iy,commit1
        jp copy
commit1: ld a,1
        ld (PHASE),a

; ---- draw W -----------------------------------------------------------------
render: ld de,SCRATCH
        ld hl,VRAM          ; clear the two top lines; the buffer was
        ld b,128            ; cleared as it was copied to the screen
rt1:    ld (hl),20h
        inc hl
        djnz rt1
        ld hl,toptext
        ld ix,VRAM
        ld iy,r1
        jp pstr
r1:     ld hl,(SCORE)
        ld ix,VRAM+6
        ld iy,r2
        jp pdec
r2:     ld a,(WAVE)
        ld ix,VRAM+18
        ld iy,r3
        jp p2dig
r3:     ld a,(LIVES)
        add a,30h
        ld (VRAM+28),a
        ld hl,entext        ; the energy bar
        ld ix,VRAM+64
        ld iy,r4
        jp pstr
r4:     ld a,(ENERGY)
        srl a
        jr z,r5
        ld b,a
        ld hl,VRAM+64+8
r4a:    ld (hl),4Ch
        inc hl
        djnz r4a
r5:     ld a,(MODE)
        or a
        jp z,rtitle
        cp 3
        jp z,rover
        ; segments
        ld ix,SEGS
        ld b,NSEG
rs1:    ld a,(ix+2)
        bit 0,a
        jr z,rs3
        ld c,4Fh            ; solid: a head
        bit 1,a
        jr nz,rs2a
        ld c,2Ah            ; *: drops bombs
        bit 2,a
        jr nz,rs2a
        ld c,40h            ; grey: following
rs2a:   ld a,(ix+1)
        ld l,(ix+0)
        ld iy,rs2b
        jp cell
rs2b:   ld (hl),c
rs3:    ld de,6
        add ix,de
        ld de,SCRATCH
        djnz rs1
        ; bullets: a quarter on the left of their character
        ld ix,BULLETS
        ld b,2
rb1:    ld a,(ix+1)
        cp 0FFh
        jr z,rb2
        ld c,01h
        bit 0,a
        jr z,rb1a
        ld c,08h
rb1a:   srl a
        ld l,(ix+0)
        ld iy,rb1b
        jp cell
rb1b:   ld iy,rb2
        jp quarter
rb2:    inc ix
        inc ix
        djnz rb1
        ; bombs: a quarter on the right
        ld ix,BOMBS
        ld b,8
rm1:    ld a,(ix+1)
        cp 0FFh
        jr z,rm2
        ld c,02h
        bit 0,a
        jr z,rm1a
        ld c,04h
rm1a:   srl a
        ld l,(ix+0)
        ld iy,rm1b
        jp cell
rm1b:   ld iy,rm2
        jp quarter
rm2:    inc ix
        inc ix
        djnz rm1
        ; the cannon, or its wreck
        ld a,(PX)
        ld l,a
        ld a,28
        ld iy,rc1
        jp cell
rc1:    ld a,(MODE)
        cp 2
        jr nz,rc2
        ld a,(FRAME)
        and 2
        jr z,rc3
        ld (hl),2Ah
        dec hl
        ld (hl),2Ah
        inc hl
        inc hl
        ld (hl),2Ah
        jr rc3
rc2:    ld (hl),4Ch         ; the barrel
        ld bc,63
        add hl,bc
        ld (hl),4Eh         ; the base
        inc hl
        ld (hl),4Fh
        inc hl
        ld (hl),4Dh
rc3:    jp blit

rtitle: ld hl,titletext
        ld iy,blit
        jp ptext
rover:  ld hl,overtext
        ld iy,ro1
        jp ptext
ro1:    ld hl,(SCORE)
        ld ix,BUF+12*64+29
        ld iy,ro2
        jp pdec
ro2:    ld a,(TIMER)
        or a
        jr nz,blit
        ld hl,againtext
        ld iy,blit
        jp ptext

; copy the buffer to the screen a line at a time, clearing it for the next
; frame; a key carries on from the line it got to (PHASE 4)
blit:   ld a,4
        ld (PHASE),a
        ld hl,BUF
bl0:    ld (BLITP),hl
        ld c,l              ; BC = HL + VRAM+128-BUF (6800h)
        ld a,h
        add a,68h
        ld b,a
bl1:    ld a,(hl)
        ld (bc),a
        ld (hl),20h
        inc hl
        inc bc
        ld a,(hl)
        ld (bc),a
        ld (hl),20h
        inc hl
        inc bc
        ld a,(hl)
        ld (bc),a
        ld (hl),20h
        inc hl
        inc bc
        ld a,(hl)
        ld (bc),a
        ld (hl),20h
        inc hl
        inc bc
        ld a,l
        and 3Fh
        jr nz,bl1
        ld a,h
        cp 20h
        jr nz,bl0
        ld hl,(FRAMES)
        inc hl
        ld (FRAMES),hl
        ld a,(framet)
        ld (TICKS),a
        ld a,2
        ld (PHASE),a
        jp dloop

; ---- helpers: all return through IY.  No LDIR: DE must stay at SCRATCH,
; as Return pads the line at DE, and that only works at the start of a line
; HL = the buffer address of column L, line A
cell:   ld (TMPW+8),bc      ; callers keep things in B and C
        ld c,l
        ld l,a
        ld h,0
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl
        add hl,hl           ; line x 64
        ld b,0
        add hl,bc
        ld bc,BUF
        add hl,bc
        ld bc,(TMPW+8)
        jp (iy)
; set quarter C in the character at HL
quarter: ld a,(hl)
        cp 20h
        jr nz,q1
        ld a,40h
q1:     or c
        ld (hl),a
        jp (iy)
; print the text at HL (ending with 0) at IX
pstr:   ld a,(hl)
        or a
        jr z,ps9
        and 3Fh
        ld (ix+0),a
        inc hl
        inc ix
        jr pstr
ps9:    inc hl              ; past the 0
        jp (iy)
; print a list of texts at HL: buffer offset (2 bytes) then the text; 0 ends
ptext:  ld (PRET),iy
pt1:    ld c,(hl)
        inc hl
        ld b,(hl)
        inc hl
        ld a,b
        or c
        jr z,pt9
        ld (TMPW),hl
        ld hl,BUF
        add hl,bc
        ld (TMPW+2),hl
        ld ix,(TMPW+2)
        ld hl,(TMPW)
        ld iy,pt1
        jp pstr
pt9:    ld iy,(PRET)
        jp (iy)
; print HL as five digits at IX
pdec:   ld (PRET),iy
        ld iy,divtab
pd9:    ld c,(iy+0)
        ld b,(iy+1)
        ld a,b
        or c
        jr z,pd12
        ld a,2Fh
pd10:   inc a
        or a
        sbc hl,bc
        jr nc,pd10
        add hl,bc
        ld (ix+0),a
        inc ix
        inc iy
        inc iy
        jr pd9
pd12:   ld iy,(PRET)
        jp (iy)
divtab: dw 10000,1000,100,10,1,0
; print A (0-99) as two digits at IX
p2dig:  ld b,2Fh
p2a:    inc b
        sub 10
        jr nc,p2a
        add a,3Ah
        ld (ix+0),b
        ld (ix+1),a
        jp (iy)

toptext: db "SCORE 00000  WAVE 00  LIVES 0",0
entext:  db " ENERGY",0
titletext:
        dw 6*64+26
        db "COMP80 STORM",0
        dw 12*64+20
        db "Z , LEFT    X . RIGHT",0
        dw 14*64+16
        db "SPACE OR RETURN FIRE   Q QUIT",0
        dw 18*64+26
        db "PRESS A KEY",0
        dw 0
overtext:
        dw 10*64+27
        db "GAME OVER",0
        dw 12*64+23
        db "SCORE",0
        dw 0
againtext:
        dw 15*64+26
        db "PRESS A KEY",0
        dw 0

stormend:
