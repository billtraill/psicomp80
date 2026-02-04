; PSI COMP80 Monitor (first 1KB of ROM) - annotated disassembly
; ORG 0000h (monitor mapped at 0x0000 at reset)
;
; Keyboard notes:
;   IN A,($01) reads the latched key byte (active-low), then CPL inverts it.
;   CP A,1Eh / JP Z,0800h implements the RS key (ASCII 0x1E, Record Separator) to enter BURP.
;
; ------------------------------------------------------------
; Key/Control-code conventions observed in this monitor ROM
;
; The keyboard hardware delivers an active-low keycode on port $01.
; The monitor inverts it (CPL) and then normalises certain values:
;   - 0x0D (CR/ENTER) is remapped to 0x1F (US) as the monitor’s
;     internal end-of-line marker.
;   - For codes >= 0x40, the monitor ANDs with 0x1F, effectively
;     folding uppercase letters to 1..26 (A=1, B=2, ... Z=26).
;     This means command keywords like ALPH/LIST/etc are NOT stored
;     as ASCII strings in ROM; they’re matched using these 5-bit codes.
;
; Control characters used as special keys:
;   0x1C  FS  (File Separator)  - acts as an escape back to command state
;         (Monitor docs mention: in ALT mode, type FS to return to commands).
;   0x1D  GS  (Group Separator) - used as a delimiter/terminator in some input loops.
;   0x1E  RS  (Record Separator)- ‘RS’ key to enter BURP (JP 0800h).
;   0x1F  US  (Unit Separator)  - used internally as ‘end of line’ (remapped from CR).
; ------------------------------------------------------------

        ORG     0000H




; ---------------------------------------------------------------------------
; Monitor command dispatch (as observed in ROM)
; The monitor reads a normalised command selector in A from CALL $0355 and
; compares it against a small set of command IDs, then jumps to handlers.
; These IDs are *not* ASCII; they are compact key/command codes produced by
; the monitor's command scanner.
;
; Mappings below are inferred from the handler behaviour and monitor_cmds.md:
;   $FC : RUN  XXXX     (parse address -> JP (HL))        (fileciteturn0file0L14-L14)
;   $13 : ALT           (alter memory; loops until FS/RESET)
;   $0F : COR           (scan/replace AA->BB across range)
;   $FE : FIND          (search for consecutive bytes XX YY)
;   $08 : LIST          (list memory to screen)
;   $04 : PRINT         (list memory on second output device)
;   $F1 : TAPE          (write block to tape/serial on port $20)
;   $F2 : READ          (read tape into memory via port $00)
;   $07 : ALPH          (VDU alphanumeric test pattern)
;   $FD : PROM          (program $1C00-$1CFF via ports)  (fileciteturn0file0L12-L12)
; ---------------------------------------------------------------------------
CMD_RUN_CODE   EQU $FC
CMD_LOAD_CODE  EQU $F8
CMD_MOV_CODE   EQU $09
CMD_FILL_CODE  EQU $06
CMD_PROM_CODE  EQU $FD
CMD_ALT_CODE   EQU $13
CMD_COR_CODE   EQU $0F
CMD_FIND_CODE  EQU $FE
CMD_LIST_CODE  EQU $08
CMD_PRINT_CODE EQU $04
CMD_TAPE_CODE  EQU $F1
CMD_READ_CODE  EQU $F2
CMD_ALPH_CODE  EQU $07
; === v5: relabelled command dispatch + monitor commands ===
MON_START:
0000  31 DF 1F     LD SP,$1FDF
0003  11 00 80     LD DE,$8000
0006  CD CE 03     CALL $03CE              ; Print inline string (see STR_PRINT_HL_AT_RETADDR)

; Inline data consumed by CALL $03CE (03CE uses EX (SP),HL to treat the return address as a string pointer,
; prints bytes until terminator $1D (GS), then returns to the byte *after* the terminator).
READY_PROMPT_STR:
0009              DB  $20,$12,$05,$01,$04,$19,$1D  ; " READY" using 5-bit letter codes (R=12h,E=05h,A=01h,D=04h,Y=19h), terminated by GS ($1D)

0010  CD C4 03     CALL $03C4  ; pad after READY prompt (advance cursor to start of next 64-col line)
0013  3E 80        LD A,$80
0015  D3 00        OUT ($00),A
; --- Main key dispatch (cold-start / command-loop entry)
; CALL $0355 returns a keycode in A (already normalised elsewhere).
; The monitor compares A against a small set of non-ASCII command keycodes
; and branches to the relevant handler.


; ---------------------------------------------------------------------------
; COMMAND_LOOP: wait for a command selector, dispatch to handlers
; ---------------------------------------------------------------------------
0017  CD 55 03     CALL $0355         ; READ_COMMAND_ID -> A
; A == $FC : special command key (non-ASCII)
; A == $FC : RUN XXXX (jump to address)

001A  FE FC        CP A,CMD_RUN_CODE   ; RUN XXXX
001C  20 0D        JR NZ,$002B
001E  18 22        JR $0042
0020  F5           PUSH AF
0021  3E 20        LD A,$20
0023  12           LD (DE),A
0024  13           INC DE
0025  F1           POP AF
0026  C9           RET
0027  FF           RST 38H
0028  C3 AA 01     JP $01AA
; A == $06 : FILL XXXX (fill from XXXX to next xx00 with FF)
;


; ---------------------------------------------------------------------------
; CMD_FILL: implements FILL XXXX (fill from XXXX to next xx00 with FF)
; ---------------------------------------------------------------------------
002B  FE 06        CP A,CMD_FILL_CODE  ; FILL XXXX (fill to page with FF)
002D  20 1A        JR NZ,$0049
002F  CD DE 03     CALL $03DE ; FILL: read start address XXXX -> HL
0032  36 FF        LD (HL),$FF
0034  2C           INC L
0035  20 FB        JR NZ,$0032
0037  C7           RST 00H
0038  F5           PUSH AF
0039  DB 03        IN A,($03)
003B  E6 0F        AND A,$0F
003D  77           LD (HL),A
003E  23           INC HL
003F  F1           POP AF
0040  FB           EI
0041  C9           RET
0042  CD 93 03     CALL $0393     ; clear screen/work area before showing READY / accepting command
0045  CD DE 03     CALL $03DE ; RUN: read target address XXXX -> HL (then JP (HL))
0048  E9           JP (HL)
; A == $09 : MOV XXXXYYYYZZZZ (block move)
;


; ---------------------------------------------------------------------------
; CMD_MOV: implements MOV XXXX YYYY ZZZZ (LDIR block move)
; ---------------------------------------------------------------------------
0049  FE 09        CP A,CMD_MOV_CODE   ; MOV XXXX YYYY ZZZZ (block move)
004B  20 48        JR NZ,$0095
004D  CD DE 03     CALL $03DE ; MOV: read source address XXXX -> HL
0050  E5           PUSH HL
0051  E7           RST 20H
0052  CD DE 03     CALL $03DE ; MOV: read destination address YYYY -> HL
0055  C1           POP BC
0056  C5           PUSH BC
0057  A7           AND A
0058  ED 42        SBC HL,BC
005A  E5           PUSH HL
005B  C1           POP BC
005C  E7           RST 20H
005D  CD DE 03     CALL $03DE ; MOV: read length/limit ZZZZ -> HL (see handler logic)
0060  D1           POP DE
0061  EB           EX DE,HL
0062  ED B0        LDIR
0064  C7           RST 00H
0065  FF           RST 38H
; ---------------------------------------------------------------------------
; NMI (keyboard 'data ready') handler at 0066h
;
; Key idea: the COMP-80 generates an NMI on any keyboard event. The monitor *expects*
; this NMI to occur only while it is deliberately waiting in a HALT instruction.
;
; On NMI entry, the Z80 pushes the return address (PC) to the stack. This handler
; swaps that return address into HL (EX (SP),HL), backs up one byte, and checks the
; opcode that was interrupted. If it wasn't HALT (0x76), it treats this as an
; unexpected key interrupt and resets back to 0000h.
; ---------------------------------------------------------------------------
NMI_KBD_ISR:
0066  E3           EX (SP),HL           ; HL := return address (PC) from NMI entry
0067  2B           DEC HL               ; point at opcode that was interrupted
0068  7E           LD A,(HL)            ; fetch interrupted opcode
0069  FE 76        CP A,$76             ; was it HALT?
006B  20 93        JR NZ,$0000          ; no: unexpected NMI -> reset monitor
006D  23           INC HL               ; yes: restore return address
006E  E3           EX (SP),HL           ; put return address back on stack


KBD_READ_PORT01:
006F  DB 01        IN A,($01)         ; read raw keycode from keyboard latch (port $01)
0071  2F           CPL                ; invert active-low keycode
0072  FE 0D        CP A,$0D           ; CR/ENTER from keyboard?
0074  20 02        JR NZ,$0078
0076  3E 1F        LD A,$1F           ; remap CR -> US (0x1F) as end-of-line marker
0078  FE 40        CP A,$40
007A  38 02        JR C,$007E
007C  E6 1F        AND A,$1F          ; fold 0x40+ range to 5-bit (letters: A=1..Z=26)
007E  FE 1C        CP A,$1C           ; FS (0x1C) - escape/return to command state
0080  28 E2        JR Z,$0064
0082  FE 1E        CP A,$1E

BURP_ENTRY_JP:
0084  CA 00 08     JP Z,$0800         ; jump into BURP (0x0800)
0087  FE 1F        CP A,$1F
0089  20 05        JR NZ,$0090
008B  CD C4 03     CALL $03C4  ; end-of-line handling: advance cursor to next 64-col line
008E  ED 45        RETN
0090  12           LD (DE),A
0091  13           INC DE
0092  ED 45        RETN
0094  FF           RST 38H
; A == $F8 : special command key (non-ASCII).
; Enters the large block-handling routine that reads/writes the $8000 display RAM region.
; A == $F8 : LOAD XXXX (hex loader; '[' enters ASCII mode, ']' exits, '@' ends + lists)


; ---------------------------------------------------------------------------
; CMD_LOAD: implements LOAD XXXX (hex loader with '['..']' ASCII mode)
; '[' key normalises to 0x1B, ']' normalises to 0x1D (GS) (see KBD_READ_PORT01).
; ---------------------------------------------------------------------------
0095  FE F8        CP A,CMD_LOAD_CODE  ; LOAD XXXX (hex/ASCII loader)
0097  20 5A        JR NZ,$00F3
0099  CD 93 03     CALL $0393     ; clear screen/work area before processing new command sequence
009C  CD DE 03     CALL $03DE ; LOAD: read load start address XXXX -> HL
009F  11 40 80     LD DE,$8040
00A2  E5           PUSH HL
00A3  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
00A6  CD 83 03     CALL $0383
00A9  76           HALT
00AA  FE 00        CP A,$00
00AC  28 22        JR Z,$00D0
00AE  FE 1B        CP A,$1B
00B0  20 11        JR NZ,$00C3
00B2  CD C4 03     CALL $03C4  ; align cursor to start of next line before continuing output
00B5  CD D5 00     CALL $00D5
00B8  77           LD (HL),A
00B9  23           INC HL
00BA  FE 1D        CP A,$1D           ; GS (0x1D) terminator/delimiter in this input loop
00BC  20 F7        JR NZ,$00B5
00BE  CD C4 03     CALL $03C4  ; align cursor to start of next line (clear/rest position)
00C1  18 E0        JR $00A3
00C3  CD F7 03     CALL $03F7
00C6  CD EA 03     CALL $03EA
00C9  77           LD (HL),A
00CA  23           INC HL
00CB  CD 72 03     CALL $0372     ; LIST/PRINT formatting: advance column (spaces/grouping); if end-of-line start next line + print address
00CE  18 D9        JR $00A9
00D0  E1           POP HL
00D1  CD 20 03     CALL $0320
00D4  C7           RST 00H
00D5  76           HALT
00D6  FE 1B        CP A,$1B
00D8  C0           DB $C0
00D9  1B           DEC DE
00DA  76           HALT
00DB  1B           DEC DE
00DC  FE 1D        CP A,$1D
00DE  28 F5        JR Z,$00D5
00E0  FE 2F        CP A,$2F
00E2  28 08        JR Z,$00EC
00E4  C6 40        ADD A,$40
00E6  12           LD (DE),A
00E7  13           INC DE
00E8  77           LD (HL),A
00E9  23           INC HL
00EA  13           INC DE
00EB  23           INC HL
00EC  2B           DEC HL
00ED  1B           DEC DE
00EE  3E 1F        LD A,$1F
00F0  12           LD (DE),A
00F1  18 E7        JR $00DA
; A == $FD : special command key (non-ASCII).
; This routine streams bytes from $1C00..$1CFF to output port $40/$80 (EPROM programmer interface).
; Strong candidate for PROM / TAPE / external device command.


; ---------------------------------------------------------------------------
; CMD_PROM: implements PROM (program 0x1C00-0x1CFF via EPROM programmer ports)
; ---------------------------------------------------------------------------
00F3  FE FD        CP A,CMD_PROM_CODE  ; PROM (EPROM programmer)
00F5  20 25        JR NZ,$011C
00F7  1E 80        LD E,$80
00F9  21 00 1C     LD HL,$1C00
00FC  16 00        LD D,$00
00FE  06 08        LD B,$08
0100  7E           LD A,(HL)
0101  D3 40        OUT ($40),A
0103  07           RLCA
0104  10 FB        DJNZ $0101
0106  06 08        LD B,$08
0108  7A           LD A,D
0109  D3 40        OUT ($40),A
010B  07           RLCA
010C  10 FB        DJNZ $0109
010E  D3 80        OUT ($80),A
0110  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0113  0F           DB $0F        ; delay count for INLINE_DELAY_1B
0114  23           INC HL
0115  14           INC D
0116  20 E6        JR NZ,$00FE
0118  1D           DEC E
0119  20 DE        JR NZ,$00F9
011B  C7           RST 00H
; A == $13 : ALT XXXXYY (alter memory; repeats until FS/RESET)
;

011C  FE 13        CP A,CMD_ALT_CODE   ; ALT XXXXYY (alter memory; repeats until FS/RESET)
011E  20 1A        JR NZ,$013A
0120  CD DE 03     CALL $03DE ; ALT: read address XXXX -> HL
0123  E7           RST 20H
0124  CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
0127  77           LD (HL),A
0128  CD 1D 03     CALL $031D
012B  CD 45 03     CALL $0345
012E  18 F0        JR $0120
0130  FF           RST 38H
0131  FF           RST 38H
0132  FF           RST 38H
0133  FF           RST 38H
0134  FF           RST 38H
0135  FF           RST 38H
0136  FF           RST 38H
0137  FF           RST 38H
0138  FF           RST 38H
0139  FF           RST 38H
; A == $07 : ALPH (VDU alphanumeric test pattern on screen)
;

013A  FE 07        CP A,CMD_ALPH_CODE  ; ALPH (VDU alphanumeric test pattern)
013C  20 0B        JR NZ,$0149
013E  21 00 80     LD HL,$8000
0141  75           LD (HL),L
0142  23           INC HL
0143  7C           LD A,H
0144  FE 88        CP A,$88
0146  20 F9        JR NZ,$0141
0148  C7           RST 00H
; A == $04 : control keycode (EOT). Treated as a command trigger.
; Likely a text-command path (hex parsing, listing, etc) begins shortly after.

0149  FE 04        CP A,CMD_PRINT_CODE ; PRINT XXXX (list from XXXX on second output device)
014B  20 1E        JR NZ,$016B
014D  CD DE 03     CALL $03DE ; PRINT: read start address XXXX -> HL
0150  CD 7F 02     CALL $027F
0153  7E           LD A,(HL)
0154  CD 8E 02     CALL $028E
0157  23           INC HL
0158  CD EC 02     CALL $02EC
015B  7D           LD A,L
015C  E6 03        AND A,$03
015E  CC           DB $CC
015F  EC           DB $EC
0160  02           DB $02
0161  CC           DB $CC
0162  EC           DB $EC
0163  02           DB $02
0164  7D           LD A,L
0165  E6 0F        AND A,$0F
0167  28 E7        JR Z,$0150
0169  18 E8        JR $0153
; A == $0F : COR XXXXYYYYAABB (scan range and replace AA->BB; prints address when it changes)
; This path looks like a compare/scan/patch loop (could match COR/FIND).

016B  FE 0F        CP A,CMD_COR_CODE   ; COR XXXXYYYYAABB
016D  20 5A        JR NZ,$01C9
016F  CD DE 03     CALL $03DE ; COR: read start address XXXX -> HL
0172  E7           RST 20H
0173  E5           PUSH HL
0174  CD DE 03     CALL $03DE ; COR: read end address YYYY -> HL
0177  E7           RST 20H
0178  CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
017B  47           LD B,A
017C  E7           RST 20H
017D  CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
0180  4F           LD C,A
0181  E3           EX (SP),HL
0182  CD 93 03     CALL $0393     ; clear screen/work area before (re)printing prompt/status line
0185  11 40 80     LD DE,$8040
0188  7E           LD A,(HL)
0189  B8           DB $B8
018A  20 04        JR NZ,$0190
018C  71           LD (HL),C
018D  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
0190  CD 4E 03     CALL $034E
0193  23           INC HL
0194  EB           EX DE,HL
0195  E3           EX (SP),HL
0196  7A           LD A,D
0197  BC           DB $BC
0198  20 06        JR NZ,$01A0
019A  7B           LD A,E
019B  BD           DB $BD
019C  20 02        JR NZ,$01A0
019E  E1           POP HL
019F  C7           RST 00H
01A0  E3           EX (SP),HL
01A1  EB           EX DE,HL
01A2  18 E4        JR $0188
01A4  FE 08        CP A,CMD_LIST_CODE  ; LIST XXXX (list memory to screen)
01A6  CC 17 03     CALL Z,$0317        ; CMD_LIST handler (prints a full VDU screen)
01A9  C7           RST 00H
01AA  F5           PUSH AF
01AB  C5           PUSH BC
01AC  D5           PUSH DE
01AD  11 00 86     LD DE,$8600
01B0  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01B3  E1           POP HL
01B4  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01B7  E1           POP HL
01B8  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01BB  E1           POP HL
01BC  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01BF  E1           POP HL
01C0  00           NOP
01C1  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01C4  E1           POP HL
01C5  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01C8  C7           RST 00H
01C9  FE FE        CP A,CMD_FIND_CODE  ; FIND XX YY (search consecutive bytes; lists addresses)
01CB  20 32        JR NZ,$01FF
01CD  CD 93 03     CALL $0393     ; clear screen/work area before listing/search output
01D0  CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
01D3  08           EX AF,AF'
01D4  E7           RST 20H
01D5  CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
01D8  21 00 00     LD HL,$0000
01DB  01 00 20     LD BC,$2000
01DE  11 40 80     LD DE,$8040
01E1  08           EX AF,AF'
01E2  ED B1        CPIR
01E4  E2 00 00     JP PO,$0000
01E7  08           EX AF,AF'
01E8  ED A1        CPI
01EA  20 F5        JR NZ,$01E1
01EC  F5           PUSH AF
01ED  2B           DEC HL
01EE  2B           DEC HL
01EF  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01F2  CD 4E 03     CALL $034E
01F5  23           INC HL
01F6  7A           LD A,D
01F7  FE 88        CP A,$88
01F9  20 01        JR NZ,$01FC
01FB  C7           RST 00H
01FC  F1           POP AF
01FD  18 E2        JR $01E1
01FF  FE F1        CP A,CMD_TAPE_CODE  ; TAPE XXXXYYYY (write block to tape/serial on port $20)
0201  20 1E        JR NZ,$0221
0203  CD DE 03     CALL $03DE ; TAPE: read start address XXXX -> HL
0206  E7           RST 20H
0207  E5           PUSH HL
0208  CD DE 03     CALL $03DE ; TAPE: read end address YYYY -> HL
020B  CD 54 02     CALL $0254
020E  E3           EX (SP),HL
020F  C1           POP BC
0210  7E           LD A,(HL)
0211  CD 60 02     CALL $0260
0214  23           INC HL
0215  7C           LD A,H
0216  B8           DB $B8
0217  20 F7        JR NZ,$0210
0219  7D           LD A,L
021A  B9           DB $B9
021B  20 F3        JR NZ,$0210
021D  CD 54 02     CALL $0254
0220  C7           RST 00H
0221  FE F2        CP A,CMD_READ_CODE  ; READ XXXX (read tape into memory starting at XXXX; terminates on key)
0223  C2 A4 01     JP NZ,$01A4
0226  CD DE 03     CALL $03DE ; READ: read start address XXXX -> HL
0229  0E 00        LD C,$00
022B  DB 00        IN A,($00)
022D  E6 01        AND A,$01
022F  20 FA        JR NZ,$022B
0231  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0234  02           DB $02        ; delay count for INLINE_DELAY_1B
0235  DB 00        IN A,($00)
0237  E6 01        AND A,$01
0239  20 F0        JR NZ,$022B
023B  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
023E  4C           DB $4C        ; delay count for INLINE_DELAY_1B
023F  06 08        LD B,$08
0241  DB 00        IN A,($00)
0243  E6 01        AND A,$01
0245  81           DB $81
0246  07           RLCA
0247  4F           LD C,A
0248  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
024B  35           DB $35        ; delay count for INLINE_DELAY_1B
024C  10 F3        DJNZ $0241
024E  79           LD A,C
024F  0F           RRCA
0250  77           LD (HL),A
0251  23           INC HL
0252  18 D5        JR $0229
0254  3E FF        LD A,$FF
0256  47           LD B,A
0257  D3 20        OUT ($20),A
0259  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
025C  FF           DB $FF        ; delay count for INLINE_DELAY_1B
025D  10 FA        DJNZ $0259
025F  C9           RET
0260  C5           PUSH BC
0261  F5           PUSH AF
0262  AF           XOR A
0263  D3 20        OUT ($20),A
0265  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0268  35           DB $35        ; delay count for INLINE_DELAY_1B
0269  F1           POP AF
026A  06 08        LD B,$08
026C  D3 20        OUT ($20),A
026E  07           RLCA
026F  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0272  35           DB $35        ; delay count for INLINE_DELAY_1B
0273  10 F7        DJNZ $026C
0275  3E FF        LD A,$FF
0277  D3 20        OUT ($20),A
0279  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
027C  4C           DB $4C        ; delay count for INLINE_DELAY_1B
027D  C1           POP BC
027E  C9           RET
027F  CD F0 02     CALL $02F0
0282  7C           LD A,H
0283  CD 8E 02     CALL $028E
0286  7D           LD A,L
0287  CD 8E 02     CALL $028E
028A  CD EC 02     CALL $02EC
028D  C9           RET
028E  C5           PUSH BC
028F  4F           LD C,A
0290  E6 F0        AND A,$F0
0292  0F           RRCA
0293  0F           RRCA
0294  0F           RRCA
0295  0F           RRCA
0296  CD 9D 02     CALL $029D
0299  79           LD A,C
029A  E6 0F        AND A,$0F
029C  C1           POP BC
029D  C6 30        ADD A,$30
029F  FE 3A        CP A,$3A
02A1  38 02        JR C,$02A5
02A3  D6           DB $D6
02A4  39           ADD HL,SP
02A5  FE 1B        CP A,$1B
02A7  30 0E        JR NC,$02B7
02A9  08           EX AF,AF'
02AA  FE 1F        CP A,$1F
02AC  28 05        JR Z,$02B3
02AE  3E 1F        LD A,$1F
02B0  CD 01 03     CALL $0301
02B3  08           EX AF,AF'
02B4  C3 01 03     JP $0301
02B7  08           EX AF,AF'
02B8  FE 1B        CP A,$1B
02BA  28 05        JR Z,$02C1
02BC  3E 1B        LD A,$1B
02BE  CD 01 03     CALL $0301
02C1  08           EX AF,AF'
02C2  E5           PUSH HL
02C3  C6 AC        ADD A,$AC
02C5  6F           LD L,A
02C6  26 02        LD H,$02
02C8  7E           LD A,(HL)
02C9  E1           POP HL
02CA  18 E8        JR $02B4
02CC  1C           INC E
02CD  1C           INC E
02CE  09           ADD HL,BC
02CF  18 05        JR $02D6
02D1  0F           RRCA
02D2  0B           DEC BC
02D3  09           ADD HL,BC
02D4  11 12 03     LD DE,$0312
02D7  0B           DEC BC
02D8  0A           DB $0A
02D9  0D           DEC C
02DA  0E 17        LD C,$17
02DC  10 01        DJNZ $02DF
02DE  02           DB $02
02DF  13           INC DE
02E0  04           INC B
02E1  15           DEC D
02E2  16 07        LD D,$07
02E4  08           EX AF,AF'
02E5  19           ADD HL,DE
02E6  0C           INC C
02E7  1C           INC E
02E8  11 06 12     LD DE,$1206
02EB  14           INC D
02EC  3E 1C        LD A,$1C
02EE  18 11        JR $0301
02F0  3E 1D        LD A,$1D
02F2  CD 01 03     CALL $0301
02F5  3E 1E        LD A,$1E
02F7  CD 01 03     CALL $0301
02FA  3E 1B        LD A,$1B
02FC  CD 01 03     CALL $0301
02FF  08           EX AF,AF'
0300  C9           RET
0301  F5           PUSH AF
0302  C5           PUSH BC
0303  E6 1F        AND A,$1F
0305  07           RLCA
0306  07           RLCA
0307  C6 03        ADD A,$03
0309  06 08        LD B,$08
030B  D3 00        OUT ($00),A
030D  07           RLCA
030E  CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0311  CE           DB $CE        ; delay count for INLINE_DELAY_1B
0312  10 F7        DJNZ $030B
0314  C1           POP BC
0315  F1           POP AF
0316  C9           RET
; ---------------------------------------------------------------------------
; LIST / memory listing routine (strong candidate)
; This block formats a line starting at address in HL:
;   - DE is set to $8040 (display buffer pointer / line start)
;   - CALL $039F prints HL as 4 hex digits plus a separator (RST 20h)
;   - CALL $0383 likely prints spacing / punctuation
;   - CALL $03A9 prints the byte at (HL) as 2 hex chars (uses $03AA/$03B9)
;   - Loop increments HL and continues until D reaches $88 (line end)
; If you want a breakpoint for LIST execution, try BP at $0317 or $0320.
; ---------------------------------------------------------------------------

; ---------------------------------------------------------------------------
; CMD_LIST_PRINT_SCREEN: core LIST-style memory listing loop
; (prints address then bytes until end-of-line; used by LIST and also post-LOAD '@' listing)
; ---------------------------------------------------------------------------
0317  CD DE 03     CALL $03DE ; LIST: read start address XXXX -> HL
031A  22           DB $22
031B  F0           DB $F0
031C  1F           RRA
031D  2A           DB $2A
031E  F0           DB $F0
031F  1F           RRA
0320  11 40 80     LD DE,$8040
0323  CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
0326  CD 83 03     CALL $0383
0329  CD A9 03     CALL $03A9
032C  23           INC HL
032D  CD 72 03     CALL $0372     ; LIST/PRINT formatting: advance column (spaces/grouping); if end-of-line start next line + print address
0330  7A           LD A,D
0331  FE 88        CP A,$88
0333  20 F4        JR NZ,$0329
0335  C9           RET
; ---------------------------------------------------------------------------
; INLINE_DELAY: cycle-burn delay with 1-byte inline parameter
;
; Call pattern:
;     CALL INLINE_DELAY
;     DB   n          ; delay count (burn cycles roughly proportional to n)
;
; Implementation trick (same family as 03CE):
;   EX (SP),HL swaps the caller's return address into HL. That return address
;   points at the inline byte 'n'. The routine reads (HL) into B, then runs a
;   tight cycle-wasting loop (EX (SP),HL repeated) for B iterations.
;   Finally it increments HL to point past the inline byte and swaps that
;   updated HL back onto the stack as the return address, so RET continues
;   at the instruction after the DB parameter.
; ---------------------------------------------------------------------------
INLINE_DELAY_1B:
0336  E3           EX (SP),HL     ; HL = return address (points to inline delay count byte)
0337  C5           PUSH BC        ; preserve BC
0338  46           LD B,(HL)      ; B = inline delay count
0339  E3           EX (SP),HL     ; waste cycles (part of delay loop)
033A  E3           EX (SP),HL     ; waste cycles
033B  E3           EX (SP),HL     ; waste cycles
033C  E3           EX (SP),HL     ; waste cycles
033D  E3           EX (SP),HL     ; waste cycles
033E  E3           EX (SP),HL     ; waste cycles
033F  10 F8        DJNZ $0339     ; loop B times
0341  C1           POP BC         ; restore BC
0342  23           INC HL         ; HL -> byte after inline parameter
0343  E3           EX (SP),HL     ; update return address on stack to skip parameter
0344  C9           RET
0345  11 08 80     LD DE,$8008
0348  D5           PUSH DE
0349  CD C4 03     CALL $03C4  ; align output cursor (start-of-line) before status/echo output
034C  D1           POP DE
034D  C9           RET
034E  7B           LD A,E
034F  E6 07        AND A,$07
0351  C8           RET Z
0352  E7           RST 20H
0353  18 F9        JR $034E
; ---------------------------------------------------------------------------
; $0355: GETKEY/GETCMD – wait for a keypress using HALT+NMI, then decode it
;
; The COMP-80 monitor uses the Z80 NMI (vector $0066) as its keyboard interrupt.
; The mainline executes HALT to sleep until an NMI arrives. The NMI handler:
;   * verifies the CPU really was halted (checks the interrupted opcode == $76)
;     and jumps to $0000 (cold monitor restart) if not halted
;   * reads the keyboard latch via IN A,($01) / CPL and normalises the value
;     (letters folded to 1..26 via AND $1F, CR remapped, etc.)
;   * returns with RETN, leaving the decoded key value in A
;
; This routine ($0355) then performs a small decode/debounce sequence:
;   1) Sample 1: HALT -> A, take low 5 bits (A AND $1F) into B
;   2) Writes that sample to $8010 (scratch/display state)
;   3) Sample 2: HALT -> A, take low 5 bits into C
;   4) Waits until the key returns to idle (A == $20, SPACE) before completing
;   5) Returns A = (C - B).  This appears to be the monitor's compact keycode
;      decode step (two successive samples combined via subtraction).
;
; NOTE: The exact meaning of B and C depends on the keyboard encoder; empirically
; the final A is the command selector used by the dispatch compares near $0080.
; ---------------------------------------------------------------------------

0355  C5           PUSH BC
0356  76           HALT
0357  E6 1F        AND A,$1F
0359  47           LD B,A
035A  11 01 80     LD DE,$8001
035D  CD C4 03     CALL $03C4  ; align output cursor before writing prompt/status area
0360  1E 10        LD E,$10
0362  78           LD A,B
0363  12           LD (DE),A
0364  13           INC DE
0365  76           HALT
0366  E6 1F        AND A,$1F
0368  4F           LD C,A
0369  76           HALT
036A  FE 20        CP A,$20
036C  20 F8        JR NZ,$0366
036E  79           LD A,C
036F  90           SUB B
0370  C1           POP BC
0371  C9           RET
; ---------------------------------------------------------------------------
; LIST_ADVANCE_AND_MAYBE_NEWLINE
;
; Called after outputting a byte in the LIST/PRINT-style memory display.
; - Always outputs at least one space (RST 20h writes ' ' to (DE) and INC DE).
; - Adds extra spacing every 4 bytes (when (L & 3) == 0).
; - When a 16-byte group is complete (when (L & 0x0F) == 0), it pads to the
;   next 64-column line boundary and then jumps into the address-print path
;   at 039F to print the new line's address (HL) followed by the next bytes.
;
; Uses L (low byte of current address) to decide grouping/wrap points.
; ---------------------------------------------------------------------------
LIST_ADVANCE_AND_MAYBE_NEWLINE:
0372  E7           RST 20H
0373  7D           LD A,L
0374  E6 03        AND A,$03
0376  20 02        JR NZ,$037A
0378  E7           RST 20H
0379  E7           RST 20H
037A  7D           LD A,L
037B  E6 0F        AND A,$0F
037D  C0           DB $C0
037E  CD C4 03     CALL $03C4  ; align output cursor to line boundary before returning to main loop
0381  18 1C        JR PRINT_HEX_WORD_HL    ; start new line: print next address
0383  7D           LD A,L
0384  E6 0F        AND A,$0F
0386  C8           DB $C8
0387  4F           LD C,A
0388  E6 0C        AND A,$0C
038A  0F           RRCA
038B  81           DB $81
038C  81           DB $81
038D  81           DB $81
038E  47           LD B,A
038F  E7           RST 20H
0390  10 FD        DJNZ $038F
0392  C9           RET
; ---------------------------------------------------------------------------
; CLEAR_SCREEN_8040_87FF
;
; Clears the monitor's display/work area by filling 0x8040..0x87FF with SPACE
; (0x20).  Uses RST 20h which writes a space to (DE) and increments DE.
;
; On entry : DE preserved
; On exit  : 0x8040..0x87FF = 0x20, DE preserved
; ---------------------------------------------------------------------------
CLEAR_SCREEN_8040_87FF:
0393  D5           PUSH DE
0394  11 40 80     LD DE,$8040
0397  E7           RST 20H
0398  7A           LD A,D
0399  FE 88        CP A,$88
039B  20 FA        JR NZ,$0397
039D  D1           POP DE
039E  C9           RET
; ---------------------------------------------------------------------------
; PRINT_HEX_WORD_HL  (entry at 039F)
;
; Purpose:
;   Emit the 16-bit value in HL as 4 hexadecimal characters at (DE), advancing DE.
;   Output format: HHLL plus a trailing SPACE (via RST 20h) to separate fields.
;
; How it works:
;   - Load A=H and call PRINT_HEX_BYTE (03AA) to output two hex chars.
;   - Load A=L and call PRINT_HEX_BYTE (03AA) to output two hex chars.
;   - Output a trailing SPACE via RST 20h (which writes 0x20 at (DE) and INC DE).
;
; Used by:
;   - LIST/PRINT style routines to print the current address at the start of each line.
;   - FIND/COR/etc when reporting addresses.
; ---------------------------------------------------------------------------
PRINT_HEX_WORD_HL:
039F  7C           LD A,H
03A0  CD AA 03     CALL $03AA
03A3  7D           LD A,L
03A4  CD AA 03     CALL $03AA
03A7  E7           RST 20H
03A8  C9           RET
; --- Hex output helpers -----------------------------------------------------
; $03A9: PRINT_HEX_BYTE_FROM_HL
;   Loads A=(HL) and falls through into $03AA to emit two hex chars to (DE).
;   Used by the LIST/memory-dump code above.
; $03AA: PRINT_HEX_BYTE (A)  ; emits high nibble then low nibble
; $03B9: NIBBLE_TO_ASCII     ; converts 0..15 into '0'..'9','A'..'F'
; ---------------------------------------------------------------------------
03A9  7E           LD A,(HL)
03AA  C5           PUSH BC
03AB  47           LD B,A
03AC  E6 F0        AND A,$F0
03AE  07           RLCA
03AF  07           RLCA
03B0  07           RLCA
03B1  07           RLCA
03B2  CD B9 03     CALL $03B9
03B5  78           LD A,B
03B6  E6 0F        AND A,$0F
03B8  C1           POP BC
03B9  FE 0A        CP A,$0A
03BB  38 02        JR C,$03BF
03BD  D6           DB $D6
03BE  39           ADD HL,SP
03BF  C6 30        ADD A,$30
03C1  12           LD (DE),A
03C2  13           INC DE
03C3  C9           RET
; ------------------------------------------------------------------------------
; PAD_TO_NEXT_LINE_64COL  (entry at 03C4)
;
; Purpose:
;   Pad output with ASCII spaces until the display cursor DE reaches the next
;   64-column boundary (i.e. E & 0x3F == 0). This effectively advances to the
;   start of the next screen line on the COMP-80 (64 chars/row).
;
; How it works:
;   - Uses RST 20h to output a SPACE at (DE) and increment DE.
;   - Loops until (E & 0x3F) == 0, then exits via the common epilogue at 03DB.
;   - Prologue EX (SP),HL preserves caller HL using the same stack trick as the
;     inline string printer at 03CE (shared epilogue).
;
03C4  PAD_TO_NEXT_LINE_64COL: E3           EX (SP),HL  ; preserve caller HL via return-address swap (shared epilogue pattern)
03C5  F5           PUSH AF  ; save AF (A used for column check / clobbered by output)
03C6  7B           LD A,E  ; A = current column (low byte of cursor)
03C7  E6 3F        AND A,$3F  ; mask to 0..63 (column within 64-char row)
03C9  28 10        JR Z,$03DB  ; if already at col 0, exit via epilogue at 03DB
03CB  E7           RST 20H  ; output SPACE at (DE), increment DE (see RST 20h)
03CC  18 F8        JR $03C6  ; loop until aligned
; ------------------------------------------------------------------------------
; STR_PRINT_INLINE_AT_RETADDR  (entry at 03CE)
;
; Purpose:
;   Print an inline, terminator-delimited string placed immediately after the CALL
;   instruction. This is how the monitor prints the READY prompt at reset.
;
; Calling convention (Z80 trick):
;   Caller does:   CALL 03CE
;                 DB <byte0>,<byte1>,...,<terminator>
;   On entry, the return address (address of the first DB byte) is on the stack.
;   EX (SP),HL swaps that return address into HL, giving HL = string pointer.
;   When printing finishes, EX (SP),HL puts the *updated* HL back on the stack,
;   so RET returns to the byte *after* the terminator.
;
; String format:
;   Bytes are COMP-80 keyboard/display codes (often 5-bit letters: A=01..Z=1A,
;   plus space=20h). Terminator is GS = 1Dh.
;
; Output:
;   Each byte is sent to the normal character output routine at 0082.
; ------------------------------------------------------------------------------
03CE  E3           EX (SP),HL             ; HL <- return address (string ptr), [SP] <- old HL
03CF  F5           PUSH AF                 ; preserve A across printing
03D0  7E           LD A,(HL)               ; fetch next byte of inline string
03D1  23           INC HL                   ; advance pointer
03D2  FE 1D        CP A,$1D                ; terminator? (GS = 1Dh)
03D4  28 05        JR Z,$03DB              ; yes -> finish (return address now points past terminator)
03D6  CD 82 00     CALL $0082              ; output this character
03D9  18 F5        JR $03D0                ; loop for next byte
03DB  F1           POP AF                  ; restore A
03DC  E3           EX (SP),HL             ; put updated HL back as return address; restore original HL
03DD  C9           RET                     ; returns to byte after terminator in caller stream
; ---------------------------------------------------------------------------
; HEX INPUT HELPERS
;
; 03DE  HEXWORD(): read 4 hex digits from the keyboard and return the 16-bit
;       value in HL (high byte first). Used by most monitor commands that take
;       addresses/ranges: LIST, RUN, LOAD, MOV, FILL, ALT, COR, TAPE, READ, ...
;
;       Implementation: calls HEXBYTE() twice:
;           H <- HEXBYTE()   (two hex digits)
;           L <- HEXBYTE()   (two hex digits)
;
; 03E7  HEXBYTE(): read 2 hex digits and return the byte in A.
;       Implementation: reads two nibbles via HEXDIGIT(), shifts the first
;       left by 4, then adds the second.
;
; 03F6  HEXDIGIT(): wait for a keypress (HALT; NMI delivers keycode in A),
;       then normalise into a 0..15 nibble:
;         - if A < 0x20 (digit-ish path), add 9 so that A..F map correctly
;         - mask with 0x0F
;
; NOTE: Key acquisition is interrupt-driven. The mainline HALTs, the NMI handler
;       (at 0066) verifies we were halted (opcode 0x76) and then reads port 01,
;       inverts it (CPL), normalises it, and returns with A holding the key code.
; ---------------------------------------------------------------------------
03DE  CD E7 03     CALL $03E7 ; Read 16-bit hex word (4 digits) into HL  (HEXBYTE: read 2 hex digits -> A)
03E1  67           LD H,A
03E2  CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
03E5  6F           LD L,A
03E6  C9           RET
; -----------------------------------------------------------------------------
; 03E7  HEXBYTE_FROM_KEYPAD
;
; Reads a single byte expressed as **two hexadecimal digits** from the keyboard.
; Returns:
;   A = byte value (00h..FFh)
; Notes:
;   - Uses HALT+NMI keyboard delivery (see GET_KEY_SELECTOR / NMI handler).
;   - Calls HEXDIGIT (03F6) twice to obtain two nibbles (0..15),
;     shifts the first nibble left by 4, then adds the second.
;   - Used by HEXWORD (03DE) and by commands that accept 8-bit parameters.
; -----------------------------------------------------------------------------
03E7  CD F6 03     CALL $03F6  ; HEXBYTE: read 2 hex digits -> A
03EA  C5           PUSH BC
03EB  07           RLCA
03EC  07           RLCA
03ED  07           RLCA
03EE  07           RLCA
03EF  47           LD B,A
03F0  CD F6 03     CALL $03F6
03F3  80           ADD A,B               ; combine low nibble with (high_nibble<<4)
03F4  C1           POP BC
03F5  C9           RET
03F6  76           HALT
03F7  FE 20        CP A,$20
03F9  30 02        JR NC,$03FD
03FB  C6 09        ADD A,$09
03FD  E6 0F        AND A,$0F
03FF  C9           RET

; =============================================================================
; Added in v16 (based on v15)
; -----------------------------------------------------------------------------
; 0383  LIST_PAD_TO_START_BYTE_COLUMN
;
; Purpose:
;   When a LIST-style dump begins at an address not aligned to a 16-byte
;   boundary, this routine outputs the correct number of SPACE characters so
;   that the *first printed data byte* appears under the proper column.
;
; Operation (conceptual):
;   i = L & 0x0F          ; byte index within a 16-byte line
;   spaces =
;       3*i               ; 'HH ' per byte (two hex chars + space)
;     + 2*(i/4)           ; extra group spacing every 4 bytes
;
;   Outputs that many spaces using RST 20h, advancing DE accordingly.
;
; Why this exists:
;   LIST output groups bytes in sets of four with extra spacing. If LIST
;   starts at (say) xxxx3, the address header is printed first, then this
;   routine pads so the first byte printed lines up under the correct column.
;
; Call sites (from v15):
;   - 00A6 : align listing output before printing first data byte
;   - 0326 : LIST command, align for unaligned start address
;
; =============================================================================