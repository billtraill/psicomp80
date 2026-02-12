; ---------------------------------------------------------------------------
; PSI COMP-80 ROM DISASSEMBLY (Combined)
; Updated: 2026-02-03  (added annotations for $06BB/token $26; notes on $054B/$065F/$06AB)
;
; 0000-03FF: Monitor (from comp80_monitor_0000_03FF_annotated.asm)
; 0400-0BFF: BURP (derived from ROM_listing_fixedup.txt + trace annotations)
;
; NOTE: BURP section includes trace-driven path map for RUN 5 and monitor-call annotations.
; ---------------------------------------------------------------------------

; ===============================
; MONITOR ROM 0000-03FF
; ===============================

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
0000: 31 DF 1F     LD SP,$1FDF
0003: 11 00 80     LD DE,$8000
0006: CD CE 03     CALL $03CE              ; Print inline string (see STR_PRINT_HL_AT_RETADDR)

; Inline data consumed by CALL $03CE (03CE uses EX (SP),HL to treat the return address as a string pointer,
; prints bytes until terminator $1D (GS), then returns to the byte *after* the terminator).
READY_PROMPT_STR:
0009: DB  $20,$12,$05,$01,$04,$19,$1D  ; " READY" using 5-bit letter codes (R=12h,E=05h,A=01h,D=04h,Y=19h), terminated by GS ($1D)

0010: CD C4 03     CALL $03C4  ; pad after READY prompt (advance cursor to start of next 64-col line)
0013: 3E 80        LD A,$80
0015: D3 00        OUT ($00),A
; --- Main key dispatch (cold-start / command-loop entry)
; CALL $0355 returns a keycode in A (already normalised elsewhere).
; The monitor compares A against a small set of non-ASCII command keycodes
; and branches to the relevant handler.


; ---------------------------------------------------------------------------
; COMMAND_LOOP: wait for a command selector, dispatch to handlers
; ---------------------------------------------------------------------------
0017: CD 55 03     CALL $0355         ; READ_COMMAND_ID -> A
; A == $FC : special command key (non-ASCII)
; A == $FC : RUN XXXX (jump to address)

001A: FE FC        CP A,CMD_RUN_CODE   ; RUN XXXX
001C: 20 0D        JR NZ,$002B
001E: 18 22        JR $0042
0020: F5           PUSH AF
0021: 3E 20        LD A,$20
0023: 12           LD (DE),A
0024: 13           INC DE
0025: F1           POP AF
0026: C9           RET
0027: FF           RST 38H
0028: C3 AA 01     JP $01AA
; A == $06 : FILL XXXX (fill from XXXX to next xx00 with FF)
;


; ---------------------------------------------------------------------------
; CMD_FILL: implements FILL XXXX (fill from XXXX to next xx00 with FF)
; ---------------------------------------------------------------------------
002B: FE 06        CP A,CMD_FILL_CODE  ; FILL XXXX (fill to page with FF)
002D: 20 1A        JR NZ,$0049
002F: CD DE 03     CALL $03DE ; FILL: read start address XXXX -> HL
0032: 36 FF        LD (HL),$FF
0034: 2C           INC L
0035: 20 FB        JR NZ,$0032
0037: C7           RST 00H

; ---------------------------------------------------------------------------
; Interrupt handler for the MM57109 stores values in the address pointed to 
; via the HL register, which should have been setup prior to interrups being 
; enabled.
; ---------------------------------------------------------------------------
0038: F5           PUSH AF
0039: DB 03        IN A,($03)
003B: E6 0F        AND A,$0F
003D: 77           LD (HL),A
003E: 23           INC HL
003F: F1           POP AF
0040: FB           EI
0041: C9           RET


0042: CD 93 03     CALL $0393     ; clear screen/work area before showing READY / accepting command
0045: CD DE 03     CALL $03DE ; RUN: read target address XXXX -> HL (then JP (HL))
0048: E9           JP (HL)
; A == $09 : MOV XXXXYYYYZZZZ (block move)
;


; ---------------------------------------------------------------------------
; CMD_MOV: implements MOV XXXX YYYY ZZZZ (LDIR block move)
; ---------------------------------------------------------------------------
0049: FE 09        CP A,CMD_MOV_CODE   ; MOV XXXX YYYY ZZZZ (block move)
004B: 20 48        JR NZ,$0095
004D: CD DE 03     CALL $03DE ; MOV: read source address XXXX -> HL
0050: E5           PUSH HL
0051: E7           RST 20H
0052: CD DE 03     CALL $03DE ; MOV: read destination address YYYY -> HL
0055: C1           POP BC
0056: C5           PUSH BC
0057: A7           AND A
0058: ED 42        SBC HL,BC
005A: E5           PUSH HL
005B: C1           POP BC
005C: E7           RST 20H
005D: CD DE 03     CALL $03DE ; MOV: read length/limit ZZZZ -> HL (see handler logic)
0060: D1           POP DE
0061: EB           EX DE,HL
0062: ED B0        LDIR
0064: C7           RST 00H
0065: FF           RST 38H
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
0066: E3           EX (SP),HL           ; HL := return address (PC) from NMI entry
0067: 2B           DEC HL               ; point at opcode that was interrupted
0068: 7E           LD A,(HL)            ; fetch interrupted opcode
0069: FE 76        CP A,$76             ; was it HALT?
006B: 20 93        JR NZ,$0000          ; no: unexpected NMI -> reset monitor
006D: 23           INC HL               ; yes: restore return address
006E: E3           EX (SP),HL           ; put return address back on stack


KBD_READ_PORT01:
006F: DB 01        IN A,($01)         ; read raw keycode from keyboard latch (port $01)
0071: 2F           CPL                ; invert active-low keycode
0072: FE 0D        CP A,$0D           ; CR/ENTER from keyboard?
0074: 20 02        JR NZ,$0078
0076: 3E 1F        LD A,$1F           ; remap CR -> US (0x1F) as end-of-line marker
0078: FE 40        CP A,$40
007A: 38 02        JR C,$007E
007C: E6 1F        AND A,$1F          ; fold 0x40+ range to 5-bit (letters: A=1..Z=26)
007E: FE 1C        CP A,$1C           ; FS (0x1C) - escape/return to command state
0080: 28 E2        JR Z,$0064
0082: FE 1E        CP A,$1E

BURP_ENTRY_JP:
0084: CA 00 08     JP Z,$0800         ; jump into BURP (0x0800)
0087: FE 1F        CP A,$1F
0089: 20 05        JR NZ,$0090
008B: CD C4 03     CALL $03C4  ; end-of-line handling: advance cursor to next 64-col line
008E: ED 45        RETN
0090: 12           LD (DE),A
0091: 13           INC DE
0092: ED 45        RETN
0094: FF           RST 38H
; A == $F8 : special command key (non-ASCII).
; Enters the large block-handling routine that reads/writes the $8000 display RAM region.
; A == $F8 : LOAD XXXX (hex loader; '[' enters ASCII mode, ']' exits, '@' ends + lists)


; ---------------------------------------------------------------------------
; CMD_LOAD: implements LOAD XXXX (hex loader with '['..']' ASCII mode)
; '[' key normalises to 0x1B, ']' normalises to 0x1D (GS) (see KBD_READ_PORT01).
; ---------------------------------------------------------------------------
0095: FE F8        CP A,CMD_LOAD_CODE  ; LOAD XXXX (hex/ASCII loader)
0097: 20 5A        JR NZ,$00F3
0099: CD 93 03     CALL $0393     ; clear screen/work area before processing new command sequence
009C: CD DE 03     CALL $03DE ; LOAD: read load start address XXXX -> HL
009F: 11 40 80     LD DE,$8040
00A2: E5           PUSH HL
00A3: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
00A6: CD 83 03     CALL $0383
00A9: 76           HALT
00AA: FE 00        CP A,$00
00AC: 28 22        JR Z,$00D0
00AE: FE 1B        CP A,$1B
00B0: 20 11        JR NZ,$00C3
00B2: CD C4 03     CALL $03C4  ; align cursor to start of next line before continuing output
00B5: CD D5 00     CALL $00D5
00B8: 77           LD (HL),A
00B9: 23           INC HL
00BA: FE 1D        CP A,$1D           ; GS (0x1D) terminator/delimiter in this input loop
00BC: 20 F7        JR NZ,$00B5
00BE: CD C4 03     CALL $03C4  ; align cursor to start of next line (clear/rest position)
00C1: 18 E0        JR $00A3
00C3: CD F7 03     CALL $03F7
00C6: CD EA 03     CALL $03EA
00C9: 77           LD (HL),A
00CA: 23           INC HL
00CB: CD 72 03     CALL $0372     ; LIST/PRINT formatting: advance column (spaces/grouping); if end-of-line start next line + print address
00CE: 18 D9        JR $00A9
00D0: E1           POP HL
00D1: CD 20 03     CALL $0320
00D4: C7           RST 00H
00D5: 76           HALT
00D6: FE 1B        CP A,$1B
00D8: C0           DB $C0
00D9: 1B           DEC DE
00DA: 76           HALT
00DB: 1B           DEC DE
00DC: FE 1D        CP A,$1D
00DE: 28 F5        JR Z,$00D5
00E0: FE 2F        CP A,$2F
00E2: 28 08        JR Z,$00EC
00E4: C6 40        ADD A,$40
00E6: 12           LD (DE),A
00E7: 13           INC DE
00E8: 77           LD (HL),A
00E9: 23           INC HL
00EA: 13           INC DE
00EB: 23           INC HL
00EC: 2B           DEC HL
00ED: 1B           DEC DE
00EE: 3E 1F        LD A,$1F
00F0: 12           LD (DE),A
00F1: 18 E7        JR $00DA
; A == $FD : special command key (non-ASCII).
; This routine streams bytes from $1C00..$1CFF to output port $40/$80 (EPROM programmer interface).
; Strong candidate for PROM / TAPE / external device command.


; ---------------------------------------------------------------------------
; CMD_PROM: implements PROM (program 0x1C00-0x1CFF via EPROM programmer ports)
; ---------------------------------------------------------------------------
00F3: FE FD        CP A,CMD_PROM_CODE  ; PROM (EPROM programmer)
00F5: 20 25        JR NZ,$011C
00F7: 1E 80        LD E,$80
00F9: 21 00 1C     LD HL,$1C00
00FC: 16 00        LD D,$00
00FE: 06 08        LD B,$08
0100: 7E           LD A,(HL)
0101: D3 40        OUT ($40),A
0103: 07           RLCA
0104: 10 FB        DJNZ $0101
0106: 06 08        LD B,$08
0108: 7A           LD A,D
0109: D3 40        OUT ($40),A
010B: 07           RLCA
010C: 10 FB        DJNZ $0109
010E: D3 80        OUT ($80),A
0110: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0113: 0F           DB $0F        ; delay count for INLINE_DELAY_1B
0114: 23           INC HL
0115: 14           INC D
0116: 20 E6        JR NZ,$00FE
0118: 1D           DEC E
0119: 20 DE        JR NZ,$00F9
011B: C7           RST 00H
; A == $13 : ALT XXXXYY (alter memory; repeats until FS/RESET)
;

011C: FE 13        CP A,CMD_ALT_CODE   ; ALT XXXXYY (alter memory; repeats until FS/RESET)
011E: 20 1A        JR NZ,$013A
0120: CD DE 03     CALL $03DE ; ALT: read address XXXX -> HL
0123: E7           RST 20H
0124: CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
0127: 77           LD (HL),A
0128: CD 1D 03     CALL $031D
012B: CD 45 03     CALL $0345
012E: 18 F0        JR $0120
0130: FF           RST 38H
0131: FF           RST 38H
0132: FF           RST 38H
0133: FF           RST 38H
0134: FF           RST 38H
0135: FF           RST 38H
0136: FF           RST 38H
0137: FF           RST 38H
0138: FF           RST 38H
0139: FF           RST 38H
; A == $07 : ALPH (VDU alphanumeric test pattern on screen)
;

013A: FE 07        CP A,CMD_ALPH_CODE  ; ALPH (VDU alphanumeric test pattern)
013C: 20 0B        JR NZ,$0149
013E: 21 00 80     LD HL,$8000
0141: 75           LD (HL),L
0142: 23           INC HL
0143: 7C           LD A,H
0144: FE 88        CP A,$88
0146: 20 F9        JR NZ,$0141
0148: C7           RST 00H
; A == $04 : control keycode (EOT). Treated as a command trigger.
; Likely a text-command path (hex parsing, listing, etc) begins shortly after.

0149: FE 04        CP A,CMD_PRINT_CODE ; PRINT XXXX (list from XXXX on second output device)
014B: 20 1E        JR NZ,$016B
014D: CD DE 03     CALL $03DE ; PRINT: read start address XXXX -> HL
0150: CD 7F 02     CALL $027F
0153: 7E           LD A,(HL)
0154: CD 8E 02     CALL $028E
0157: 23           INC HL
0158: CD EC 02     CALL $02EC
015B: 7D           LD A,L
015C: E6 03        AND A,$03
015E: CC           DB $CC
015F: EC           DB $EC
0160: 02           DB $02
0161: CC           DB $CC
0162: EC           DB $EC
0163: 02           DB $02
0164: 7D           LD A,L
0165: E6 0F        AND A,$0F
0167: 28 E7        JR Z,$0150
0169: 18 E8        JR $0153
; A == $0F : COR XXXXYYYYAABB (scan range and replace AA->BB; prints address when it changes)
; This path looks like a compare/scan/patch loop (could match COR/FIND).

016B: FE 0F        CP A,CMD_COR_CODE   ; COR XXXXYYYYAABB
016D: 20 5A        JR NZ,$01C9
016F: CD DE 03     CALL $03DE ; COR: read start address XXXX -> HL
0172: E7           RST 20H
0173: E5           PUSH HL
0174: CD DE 03     CALL $03DE ; COR: read end address YYYY -> HL
0177: E7           RST 20H
0178: CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
017B: 47           LD B,A
017C: E7           RST 20H
017D: CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
0180: 4F           LD C,A
0181: E3           EX (SP),HL
0182: CD 93 03     CALL $0393     ; clear screen/work area before (re)printing prompt/status line
0185: 11 40 80     LD DE,$8040
0188: 7E           LD A,(HL)
0189: B8           DB $B8
018A: 20 04        JR NZ,$0190
018C: 71           LD (HL),C
018D: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
0190: CD 4E 03     CALL $034E
0193: 23           INC HL
0194: EB           EX DE,HL
0195: E3           EX (SP),HL
0196: 7A           LD A,D
0197: BC           DB $BC
0198: 20 06        JR NZ,$01A0
019A: 7B           LD A,E
019B: BD           DB $BD
019C: 20 02        JR NZ,$01A0
019E: E1           POP HL
019F: C7           RST 00H
01A0: E3           EX (SP),HL
01A1: EB           EX DE,HL
01A2: 18 E4        JR $0188
01A4: FE 08        CP A,CMD_LIST_CODE  ; LIST XXXX (list memory to screen)
01A6: CC 17 03     CALL Z,$0317        ; CMD_LIST handler (prints a full VDU screen)
01A9: C7           RST 00H
01AA: F5           PUSH AF
01AB: C5           PUSH BC
01AC: D5           PUSH DE
01AD: 11 00 86     LD DE,$8600
01B0: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01B3: E1           POP HL
01B4: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01B7: E1           POP HL
01B8: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01BB: E1           POP HL
01BC: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01BF: E1           POP HL
01C0: 00           NOP
01C1: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01C4: E1           POP HL
01C5: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01C8: C7           RST 00H
01C9: FE FE        CP A,CMD_FIND_CODE  ; FIND XX YY (search consecutive bytes; lists addresses)
01CB: 20 32        JR NZ,$01FF
01CD: CD 93 03     CALL $0393     ; clear screen/work area before listing/search output
01D0: CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
01D3: 08           EX AF,AF'
01D4: E7           RST 20H
01D5: CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
01D8: 21 00 00     LD HL,$0000
01DB: 01 00 20     LD BC,$2000
01DE: 11 40 80     LD DE,$8040
01E1: 08           EX AF,AF'
01E2: ED B1        CPIR
01E4: E2 00 00     JP PO,$0000
01E7: 08           EX AF,AF'
01E8: ED A1        CPI
01EA: 20 F5        JR NZ,$01E1
01EC: F5           PUSH AF
01ED: 2B           DEC HL
01EE: 2B           DEC HL
01EF: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
01F2: CD 4E 03     CALL $034E
01F5: 23           INC HL
01F6: 7A           LD A,D
01F7: FE 88        CP A,$88
01F9: 20 01        JR NZ,$01FC
01FB: C7           RST 00H
01FC: F1           POP AF
01FD: 18 E2        JR $01E1
01FF: FE F1        CP A,CMD_TAPE_CODE  ; TAPE XXXXYYYY (write block to tape/serial on port $20)
0201: 20 1E        JR NZ,$0221
0203: CD DE 03     CALL $03DE ; TAPE: read start address XXXX -> HL
0206: E7           RST 20H
0207: E5           PUSH HL
0208: CD DE 03     CALL $03DE ; TAPE: read end address YYYY -> HL
020B: CD 54 02     CALL $0254
020E: E3           EX (SP),HL
020F: C1           POP BC
0210: 7E           LD A,(HL)
0211: CD 60 02     CALL $0260
0214: 23           INC HL
0215: 7C           LD A,H
0216: B8           DB $B8
0217: 20 F7        JR NZ,$0210
0219: 7D           LD A,L
021A: B9           DB $B9
021B: 20 F3        JR NZ,$0210
021D: CD 54 02     CALL $0254
0220: C7           RST 00H
0221: FE F2        CP A,CMD_READ_CODE  ; READ XXXX (read tape into memory starting at XXXX; terminates on key)
0223: C2 A4 01     JP NZ,$01A4
0226: CD DE 03     CALL $03DE ; READ: read start address XXXX -> HL
0229: 0E 00        LD C,$00
022B: DB 00        IN A,($00)
022D: E6 01        AND A,$01
022F: 20 FA        JR NZ,$022B
0231: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0234: 02           DB $02        ; delay count for INLINE_DELAY_1B
0235: DB 00        IN A,($00)
0237: E6 01        AND A,$01
0239: 20 F0        JR NZ,$022B
023B: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
023E: 4C           DB $4C        ; delay count for INLINE_DELAY_1B
023F: 06 08        LD B,$08
0241: DB 00        IN A,($00)
0243: E6 01        AND A,$01
0245: 81           DB $81
0246: 07           RLCA
0247: 4F           LD C,A
0248: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
024B: 35           DB $35        ; delay count for INLINE_DELAY_1B
024C: 10 F3        DJNZ $0241
024E: 79           LD A,C
024F: 0F           RRCA
0250: 77           LD (HL),A
0251: 23           INC HL
0252: 18 D5        JR $0229
0254: 3E FF        LD A,$FF
0256: 47           LD B,A
0257: D3 20        OUT ($20),A
0259: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
025C: FF           DB $FF        ; delay count for INLINE_DELAY_1B
025D: 10 FA        DJNZ $0259
025F: C9           RET
0260: C5           PUSH BC
0261: F5           PUSH AF
0262: AF           XOR A
0263: D3 20        OUT ($20),A
0265: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0268: 35           DB $35        ; delay count for INLINE_DELAY_1B
0269: F1           POP AF
026A: 06 08        LD B,$08
026C: D3 20        OUT ($20),A
026E: 07           RLCA
026F: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0272: 35           DB $35        ; delay count for INLINE_DELAY_1B
0273: 10 F7        DJNZ $026C
0275: 3E FF        LD A,$FF
0277: D3 20        OUT ($20),A
0279: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
027C: 4C           DB $4C        ; delay count for INLINE_DELAY_1B
027D: C1           POP BC
027E: C9           RET
027F: CD F0 02     CALL $02F0
0282: 7C           LD A,H
0283: CD 8E 02     CALL $028E
0286: 7D           LD A,L
0287: CD 8E 02     CALL $028E
028A: CD EC 02     CALL $02EC
028D: C9           RET
028E: C5           PUSH BC
028F: 4F           LD C,A
0290: E6 F0        AND A,$F0
0292: 0F           RRCA
0293: 0F           RRCA
0294: 0F           RRCA
0295: 0F           RRCA
0296: CD 9D 02     CALL $029D
0299: 79           LD A,C
029A: E6 0F        AND A,$0F
029C: C1           POP BC
029D: C6 30        ADD A,$30
029F: FE 3A        CP A,$3A
02A1: 38 02        JR C,$02A5
02A3: D6           DB $D6
02A4: 39           ADD HL,SP
02A5: FE 1B        CP A,$1B
02A7: 30 0E        JR NC,$02B7
02A9: 08           EX AF,AF'
02AA: FE 1F        CP A,$1F
02AC: 28 05        JR Z,$02B3
02AE: 3E 1F        LD A,$1F
02B0: CD 01 03     CALL $0301
02B3: 08           EX AF,AF'
02B4: C3 01 03     JP $0301
02B7: 08           EX AF,AF'
02B8: FE 1B        CP A,$1B
02BA: 28 05        JR Z,$02C1
02BC: 3E 1B        LD A,$1B
02BE: CD 01 03     CALL $0301
02C1: 08           EX AF,AF'
02C2: E5           PUSH HL
02C3: C6 AC        ADD A,$AC
02C5: 6F           LD L,A
02C6: 26 02        LD H,$02
02C8: 7E           LD A,(HL)
02C9: E1           POP HL
02CA: 18 E8        JR $02B4
02CC: 1C           INC E
02CD: 1C           INC E
02CE: 09           ADD HL,BC
02CF: 18 05        JR $02D6
02D1: 0F           RRCA
02D2: 0B           DEC BC
02D3: 09           ADD HL,BC
02D4: 11 12 03     LD DE,$0312
02D7: 0B           DEC BC
02D8: 0A           DB $0A
02D9: 0D           DEC C
02DA: 0E 17        LD C,$17
02DC: 10 01        DJNZ $02DF
02DE: 02           DB $02
02DF: 13           INC DE
02E0: 04           INC B
02E1: 15           DEC D
02E2: 16 07        LD D,$07
02E4: 08           EX AF,AF'
02E5: 19           ADD HL,DE
02E6: 0C           INC C
02E7: 1C           INC E
02E8: 11 06 12     LD DE,$1206
02EB: 14           INC D
02EC: 3E 1C        LD A,$1C
02EE: 18 11        JR $0301
02F0: 3E 1D        LD A,$1D
02F2: CD 01 03     CALL $0301
02F5: 3E 1E        LD A,$1E
02F7: CD 01 03     CALL $0301
02FA: 3E 1B        LD A,$1B
02FC: CD 01 03     CALL $0301
02FF: 08           EX AF,AF'
0300: C9           RET
0301: F5           PUSH AF
0302: C5           PUSH BC
0303: E6 1F        AND A,$1F
0305: 07           RLCA
0306: 07           RLCA
0307: C6 03        ADD A,$03
0309: 06 08        LD B,$08
030B: D3 00        OUT ($00),A
030D: 07           RLCA
030E: CD 36 03     CALL $0336 ; INLINE_DELAY_1B: 1-byte delay parameter follows
0311: CE           DB $CE        ; delay count for INLINE_DELAY_1B
0312: 10 F7        DJNZ $030B
0314: C1           POP BC
0315: F1           POP AF
0316: C9           RET
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
0317: CD DE 03     CALL $03DE ; LIST: read start address XXXX -> HL
031A: 22           DB $22
031B: F0           DB $F0
031C: 1F           RRA
031D: 2A           DB $2A
031E: F0           DB $F0
031F: 1F           RRA
0320: 11 40 80     LD DE,$8040
0323: CD 9F 03     CALL PRINT_HEX_WORD_HL    ; print HL as 4 hex digits + space
0326: CD 83 03     CALL $0383
0329: CD A9 03     CALL $03A9
032C: 23           INC HL
032D: CD 72 03     CALL $0372     ; LIST/PRINT formatting: advance column (spaces/grouping); if end-of-line start next line + print address
0330: 7A           LD A,D
0331: FE 88        CP A,$88
0333: 20 F4        JR NZ,$0329
0335: C9           RET
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
0336: E3           EX (SP),HL     ; HL = return address (points to inline delay count byte)
0337: C5           PUSH BC        ; preserve BC
0338: 46           LD B,(HL)      ; B = inline delay count
0339: E3           EX (SP),HL     ; waste cycles (part of delay loop)
033A: E3           EX (SP),HL     ; waste cycles
033B: E3           EX (SP),HL     ; waste cycles
033C: E3           EX (SP),HL     ; waste cycles
033D: E3           EX (SP),HL     ; waste cycles
033E: E3           EX (SP),HL     ; waste cycles
033F: 10 F8        DJNZ $0339     ; loop B times
0341: C1           POP BC         ; restore BC
0342: 23           INC HL         ; HL -> byte after inline parameter
0343: E3           EX (SP),HL     ; update return address on stack to skip parameter
0344: C9           RET
0345: 11 08 80     LD DE,$8008
0348: D5           PUSH DE
0349: CD C4 03     CALL $03C4  ; align output cursor (start-of-line) before status/echo output
034C: D1           POP DE
034D: C9           RET
034E: 7B           LD A,E
034F: E6 07        AND A,$07
0351: C8           RET Z
0352: E7           RST 20H
0353: 18 F9        JR $034E
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

0355: C5           PUSH BC
0356: 76           HALT
0357: E6 1F        AND A,$1F
0359: 47           LD B,A
035A: 11 01 80     LD DE,$8001
035D: CD C4 03     CALL $03C4  ; align output cursor before writing prompt/status area
0360: 1E 10        LD E,$10
0362: 78           LD A,B
0363: 12           LD (DE),A
0364: 13           INC DE
0365: 76           HALT
0366: E6 1F        AND A,$1F
0368: 4F           LD C,A
0369: 76           HALT
036A: FE 20        CP A,$20
036C: 20 F8        JR NZ,$0366
036E: 79           LD A,C
036F: 90           SUB B
0370: C1           POP BC
0371: C9           RET
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
0372: E7           RST 20H
0373: 7D           LD A,L
0374: E6 03        AND A,$03
0376: 20 02        JR NZ,$037A
0378: E7           RST 20H
0379: E7           RST 20H
037A: 7D           LD A,L
037B: E6 0F        AND A,$0F
037D: C0           DB $C0
037E: CD C4 03     CALL $03C4  ; align output cursor to line boundary before returning to main loop
0381: 18 1C        JR PRINT_HEX_WORD_HL    ; start new line: print next address
0383: 7D           LD A,L
0384: E6 0F        AND A,$0F
0386: C8           DB $C8
0387: 4F           LD C,A
0388: E6 0C        AND A,$0C
038A: 0F           RRCA
038B: 81           DB $81
038C: 81           DB $81
038D: 81           DB $81
038E: 47           LD B,A
038F: E7           RST 20H
0390: 10 FD        DJNZ $038F
0392: C9           RET
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
0393: D5           PUSH DE
0394: 11 40 80     LD DE,$8040
0397: E7           RST 20H
0398: 7A           LD A,D
0399: FE 88        CP A,$88
039B: 20 FA        JR NZ,$0397
039D: D1           POP DE
039E: C9           RET
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
039F: 7C           LD A,H
03A0: CD AA 03     CALL $03AA
03A3: 7D           LD A,L
03A4: CD AA 03     CALL $03AA
03A7: E7           RST 20H
03A8: C9           RET
; --- Hex output helpers -----------------------------------------------------
; $03A9: PRINT_HEX_BYTE_FROM_HL
;   Loads A=(HL) and falls through into $03AA to emit two hex chars to (DE).
;   Used by the LIST/memory-dump code above.
; $03AA: PRINT_HEX_BYTE (A)  ; emits high nibble then low nibble
; $03B9: NIBBLE_TO_ASCII     ; converts 0..15 into '0'..'9','A'..'F'
; ---------------------------------------------------------------------------
03A9: 7E           LD A,(HL)
03AA: C5           PUSH BC
03AB: 47           LD B,A
03AC: E6 F0        AND A,$F0
03AE: 07           RLCA
03AF: 07           RLCA
03B0: 07           RLCA
03B1: 07           RLCA
03B2: CD B9 03     CALL $03B9
03B5: 78           LD A,B
03B6: E6 0F        AND A,$0F
03B8: C1           POP BC
03B9: FE 0A        CP A,$0A
03BB: 38 02        JR C,$03BF
03BD: D6           DB $D6
03BE: 39           ADD HL,SP
03BF: C6 30        ADD A,$30
03C1: 12           LD (DE),A
03C2: 13           INC DE
03C3: C9           RET
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
03C4: PAD_TO_NEXT_LINE_64COL: E3           EX (SP),HL  ; preserve caller HL via return-address swap (shared epilogue pattern)
03C5: F5           PUSH AF  ; save AF (A used for column check / clobbered by output)
03C6: 7B           LD A,E  ; A = current column (low byte of cursor)
03C7: E6 3F        AND A,$3F  ; mask to 0..63 (column within 64-char row)
03C9: 28 10        JR Z,$03DB  ; if already at col 0, exit via epilogue at 03DB
03CB: E7           RST 20H  ; output SPACE at (DE), increment DE (see RST 20h)
03CC: 18 F8        JR $03C6  ; loop until aligned
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
03CE: E3           EX (SP),HL             ; HL <- return address (string ptr), [SP] <- old HL
03CF: F5           PUSH AF                 ; preserve A across printing
03D0: 7E           LD A,(HL)               ; fetch next byte of inline string
03D1: 23           INC HL                   ; advance pointer
03D2: FE 1D        CP A,$1D                ; terminator? (GS = 1Dh)
03D4: 28 05        JR Z,$03DB              ; yes -> finish (return address now points past terminator)
03D6: CD 82 00     CALL $0082              ; output this character
03D9: 18 F5        JR $03D0                ; loop for next byte
03DB: F1           POP AF                  ; restore A
03DC: E3           EX (SP),HL             ; put updated HL back as return address; restore original HL
03DD: C9           RET                     ; returns to byte after terminator in caller stream
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
03DE: CD E7 03     CALL $03E7 ; Read 16-bit hex word (4 digits) into HL  (HEXBYTE: read 2 hex digits -> A)
03E1: 67           LD H,A
03E2: CD E7 03     CALL $03E7  ; HEXBYTE: read 2 hex digits -> A
03E5: 6F           LD L,A
03E6: C9           RET
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
03E7: CD F6 03     CALL $03F6  ; HEXBYTE: read 2 hex digits -> A
03EA: C5           PUSH BC
03EB: 07           RLCA
03EC: 07           RLCA
03ED: 07           RLCA
03EE: 07           RLCA
03EF: 47           LD B,A
03F0: CD F6 03     CALL $03F6
03F3: 80           ADD A,B               ; combine low nibble with (high_nibble<<4)
03F4: C1           POP BC
03F5: C9           RET
03F6: 76           HALT
03F7: FE 20        CP A,$20
03F9: 30 02        JR NC,$03FD
03FB: C6 09        ADD A,$09
03FD: E6 0F        AND A,$0F
03FF: C9           RET

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

; ===============================
; BURP ROM 0400-0BFF
; ===============================
;
; The following section was originally in markdown; narrative lines are preserved as ';' comments.
; Disassembly lines are kept as-is where possible.

; # PSI COMP-80 BURP ROM disassembly (0x0400–0x0BFF)

; Generated from `ROM_listing_fixedup.txt`. Monitor routine names/comments are taken from `comp80_monitor_0000_03FF_annotated.asm` when the BURP ROM calls into 0x0000–0x03FF.

0400: D9          EXX
0401: 21 0B 1E    LD HL,$1E0B
0404: 7E          LD A,(HL)
0405: FE 0C       CP $0C
0407: 20 03       JR NZ,$040C
0409: AF          XOR A
040A: 18 20       JR $042C
040C: 2E 0D       LD L,$0D
040E: 56          LD D,(HL)
040F: 14          INC D
0410: 2E 00       LD L,$00
0412: 46          LD B,(HL)
0413: 23          INC HL
0414: 15          DEC D
0415: 28 0D       JR Z,$0424
0417: 23          INC HL
0418: 7E          LD A,(HL)
0419: CB 20       SLA B
041B: 80          ADD A,B
041C: CB 20       SLA B
041E: CB 20       SLA B
0420: 80          ADD A,B
0421: 47          LD B,A
0422: 18 F0       JR $0414
0424: 23          INC HL
0425: 7E          LD A,(HL)
0426: FE 05       CP $05
0428: 38 01       JR C,$042B
042A: 04          INC B
042B: 78          LD A,B
042C: D9          EXX
042D: C9          RET


; -----------------------------------------------------------------------------
; MM57109_SEND_INSTRUCTION_IN_A ($042E)
;
;  Purpose:
;    Executes the MM57109 instruction in register A. The sequence checks that the MM57109 is ready, outputs 
;    the instruction with hold off, waits for READY to go off (to indicate instruction is being execited) and then puts the hold on again, 
;    this stops the MM57109 after the current instuction has been completed.
;
;  Calling convention (inferred from ROM usage):
;    IN : A  = byte to send (command/data)
;    OUT: A  preserved (via B), flags not guaranteed
;    Uses: B  (saves A in B), polls port $03 bit5 (mask $20)
;    Preserves: BC (PUSH/POP), other regs unaffected
;
;  Hardware behaviour (as used by ROM):
;    - Port $03 bit5 (mask $20) is treated as RDY/handshake status.
;    - Port $60 is the output latch to the coprocessor interface.
;    - Protocol implemented here:
;        1) Wait for RDY=0 (busy/ready-to-accept phase)
;        2) Output the byte (A) to port $60
;        3) Wait for RDY=1 (acknowledge phase)
;        4) Output the same byte again with bit7 set (A|$80) to complete strobe
;
;  Notes:
;    - This is the primary low-level primitive used throughout BURP to talk to
;      the MM57109 (directly or via wrapper routines like $0446/$0460).
;    - If port $03 bit5 behaviour is wrong in emulation, BURP can hang in the
;      busy/ack loops here or mis-sequence the coprocessor stream.
; -----------------------------------------------------------------------------
; — Z80 polls port 0x03 bit5 (RDY), OUT to 0x60, waits RDY=1 then sets bit7 and OUT again (MM57109 hold).
042E: C5          PUSH BC ; preserve caller's BC
042F: 47          LD B,A  ; B := A (save byte to send)
; Is MM57109 Ready?
0430: DB 03       IN A,($03)  ; poll status: IN A,($03), is the MM57109 Ready?
0432: E6 20       AND $20  ; mask RDY bit (bit5)
0434: 20 FA       JR NZ,$0430  ; wait for READY state, busy is indicated by RDY==1, and ready is indicated by RDY=0
; Send instruction to MM57109
0436: 78          LD A,B  ; restore byte to send
0437: D3 60       OUT ($60),A  ; phase 1: OUT ($60),A
; Wait for MM57109 to show it is executing the instruction (RDY=1 when it is busy executing, ie not ready)
0439: DB 03       IN A,($03)  ; poll for acknowledge: IN A,($03)
043B: E6 20       AND $20  ; mask RDY bit (bit5)
043D: 28 FA       JR Z,$0439  ; wait for RDY==1 (indication that the instruction is being executed)
; Set the hold bit. This holds the MM57109 when it has completed the current instruction (ie when RDY=0)
043F: 78          LD A,B  ; restore byte to send
0440: F6 80       OR $80  ; set hold bit7
0442: D3 60       OUT ($60),A  ; Sets HOLD
0444: C1          POP BC  ; Restore BC
0445: C9          RET  ; RET


; ## BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF ($0446)

; -----------------------------------------------------------------------------
; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF ($0446)
;  Repeats 042E for sequence of MM57109 instructions terminated with an FF.
;  Reads a byte stream located immediately after the CALL instruction that invoked
;  this routine (i.e., inline data at the return address).
;
;  For each byte read:
;    - If byte == $FF: stop and return to caller with HL advanced past the terminator
;    - Else: send it to the MM57109 interface via MM57109_SEND_INSTRUCTION_IN_A(A=byte) at $042E
;
;  Calling convention:
;    IN : return address points to inline byte stream
;    OUT: HL points to first byte after the $FF terminator (in caller's stream)
;
;  Used throughout BURP to emit short MM57109 “bytecode” sequences from ROM.
; -----------------------------------------------------------------------------
0446: E3          EX (SP),HL
0447: 7E          LD A,(HL)
0448: 23          INC HL
0449: E3          EX (SP),HL
044A: FE FF       CP $FF
044C: C8          RET Z
044D: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=byte)

0450: 18 F4       JR $0446
;
; Jumps over next work in the program line. Used in FOR statements to miss STEP and UNTIL
;
0452: 23          INC HL
0453: 23          INC HL
0454: 7E          LD A,(HL)
0455: FE 20       CP $20
0457: 20 FA       JR NZ,$0453
;
; Move to next token and BURP_EXPR_GET_TOKEN_AND_EMIT
;
0459: 23          INC HL       ; Move to the next char in the input
; 
; 04E6 with BC protected. Repeats 042E for sequence of MM57109 instructions terminated with an FF
;
045A: C5          PUSH BC
045B: CD E6 04    CALL $04E6   ; BURP_EXPR_GET_TOKEN_AND_EMIT
045E: C1          POP BC
045F: C9          RET

; ## BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT ($0460)

; -----------------------------------------------------------------------------
; BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT ($0460)
;  High-level wrapper used by statement handlers (e.g., FOR) to emit an MM57109 OUT* instruction 
;  This basically reads the MM57109 X register in scientific notation.
;
;  Observed behaviour:
;    - Enables interrupts (IM 1 / EI) briefly around emitting an inline stream via $0446
;      (likely to allow MM57109 to signal completion / data-ready via INT).
;    - Calls $0446 to read & send inline bytes until $FF (therefore repeatedly calling
;      MM57109_SEND_INSTRUCTION_IN_A(A=byte) at $042E).
;    - The OUT instruction results in 12 interrupts, which is outputing the value of X reg 
;    - Interacts with workspace around $1FF4/$1FF6 and uses small formatting logic.
;
;  Calling convention (inferred):
;
; -----------------------------------------------------------------------------
0460: D9          EXX
0461: F5          PUSH AF
0462: 21 F4 1F    LD HL,$1FF4
0465: ED 56       IM 1
0467: FB          EI  ; Enable interupts from MM57109 to results (if any from instruction can be sent)
0468: CD 46 04    CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 046B-046D terminated by $FF
046B:              DB  $16,$2B,$FF  ; MM57109 instructions OUT*($2B)
046E: F3          DI  ; Disable the interrupts again, the results should now be at $1FF4 (all 12 interrupts should have happened)
046F: F1          POP AF
0470: CD 14 07    CALL $0714 ; by the time this is called the OUT instuction should have completed and the results will have been put in $1FF4
0473: 7D          LD A,L
0474: E6 F0       AND $F0
0476: 6F          LD L,A
0477: E5          PUSH HL
0478: C6 0A       ADD A,$0A
047A: 6F          LD L,A
047B: 11 F6 1F    LD DE,$1FF6
047E: EB          EX DE,HL
047F: 3E 0B       LD A,$0B
0481: 12          LD (DE),A
0482: 13          INC DE
0483: CB 46       BIT 0,(HL)
0485: 28 03       JR Z,$048A
0487: 3E 0C       LD A,$0C
0489: 12          LD (DE),A
048A: 13          INC DE
048B: 2B          DEC HL
048C: 2B          DEC HL
048D: ED A0       LDI
048F: ED A0       LDI
0491: 7B          LD A,E
0492: E6 F0       AND $F0
0494: C6 09       ADD A,$09
0496: 5F          LD E,A
0497: CB 5E       BIT 3,(HL)
0499: 28 03       JR Z,$049E
049B: 3E 0C       LD A,$0C
049D: 12          LD (DE),A
049E: D1          POP DE
049F: 23          INC HL
04A0: 7E          LD A,(HL)
04A1: 2F          CPL
04A2: E6 0F       AND $0F
04A4: D6 03       SUB $03
04A6: 23          INC HL
04A7: 06 00       LD B,$00
04A9: 4F          LD C,A
04AA: ED B0       LDIR
04AC: 2F          CPL
04AD: C6 09       ADD A,$09
04AF: 4F          LD C,A
04B0: 3E 0A       LD A,$0A
04B2: 12          LD (DE),A
04B3: 13          INC DE
04B4: 28 02       JR Z,$04B8
04B6: ED B0       LDIR
04B8: D9          EXX
04B9: C9          RET

;
; Need to annotate this
;
04BA: E6 0F       AND $0F
04BC: 4F          LD C,A
04BD: 23          INC HL
04BE: 7E          LD A,(HL)
04BF: FE 20       CP $20
04C1: C8          RET Z
04C2: E6 0F       AND $0F
04C4: CB 01       RLC C
04C6: 81          ADD A,C
04C7: CB 01       RLC C
04C9: CB 01       RLC C
04CB: 81          ADD A,C
04CC: 4F          LD C,A
04CD: 18 EE       JR $04BD
04CF: FF          RST $38
04D0: FF          RST $38
04D1: FF          RST $38
04D2: FF          RST $38
04D3: FF          RST $38
04D4: CD 7B 05    CALL $057B
04D7: CD 46 04    CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 04DA-04DF terminated by $FF
04DA:              DB  $3C,$01,$02,$06,$3B,$FF  ;   MM57109 instructions  /,1,2,3,*            
04E0: 3E 00       LD A,$00
04E2: CD 60 04    CALL $0460  ; BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)

04E5: C9          RET
;---------------------------------------------------
; BURP_EXPR_GET_TOKEN_AND_EMIT
; get next expression token and emit the corresponding MM57109 bytecode/opcode (skipping spaces), with special handling for numbers and a special operator token.”
;  - Skips spaces
;  - Reads next expression token from (HL)
;  - Classifies token range
;  - Emits corresponding math-coprocessor opcode via $042E
;  - Advances HL
;---------------------------------------------------
; -----------------------------------------------------------------------------
; BURP_EXPR_GET_TOKEN_AND_EMIT ($04E6)
;  Expression compiler primitive: reads the next non-space token from the source line
;  (HL), classifies it by value range, and either:
;    - emits one or more MM57109 bytes (via MM57109_SEND_INSTRUCTION_IN_A(A=byte) / $042E), or
;    - jumps to helpers for small tokens ($0545) or numeric literals ($050B/$050F).
;
;  Inputs/Outputs:
;    IN : HL -> source token stream
;    OUT: HL advanced past consumed token(s); MM57109 stream extended
; -----------------------------------------------------------------------------
04E6: 7E          LD  A,(HL)        ; read next byte from source line
04E7: 23          INC HL
04E8: 0E 0F       LD  C,$0F         ; set up a format code 0F for 050F formatting (and possibly other routines)...
04EA: FE 20       CP  $20           ; space?
04EC: 28 F8       JR  Z,$04E6       ; yes -> skip spaces and keep scanning

04EE: FE 1B       CP  $1B
04F0: 38 53       JR  C,$0545       ; if A < 1B -> handle “small tokens” elsewhere  ; BURP_EXPR_DECODE_SMALLTOKEN_AND_EMIT_OP (tokens < $1B)
;  If token is followed by space ($20), uses $057B to emit a fixed 16-byte operand block.

                                     ; (likely variables, separators, parens, etc.)

04F2: FE 30       CP  $30
04F4: 30 19       JR  NC,$050F      ; if A >= 30 -> handle ASCII/number-ish tokens elsewhere
                                     ; (likely numeric literal parsing: '0'..'9', maybe quotes, etc.)

; ---- so here: 1B <= A < 30 is a “mid-range token” fast-path ----

04F6: FE 2D       CP  $2D           ; token 2D special-cased
04F8: 20 03       JR  NZ,$04FD      ; if not 2D, skip the special check
04FA: BE          CP  (HL)          ; compare A (2D) with NEXT token in stream
04FB: 38 0E       JR  C,$050B       ; if 2D < (HL) -> go handle as special case
                                     ; (very likely disambiguating unary/binary '-' or function vs operator)

04FD: C6 0D       ADD A,$0D         ; map token range into MM57109 opcode space

04FF: A7          AND A             ; refresh flags based on A
0500: EA 07 05    JP  PE,$0507      ; if P/V=1 after the ADD -> take direct emit

0503: F6 09       OR  $09           ; otherwise tweak bits...
0505: E6 FB       AND $FB           ; ...force bit2 clear, bits0+3 set (see below)

0507: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=byte) ; emit the resulting byte to MM57109 interface

050A: C9          RET


; -----------------------------------------------------------------------------
; BURP_EXPR_PARSE_NUMBER_LITERAL_AND_EMIT
;  Jump target from BURP_EXPR_GET_TOKEN_AND_EMIT when a special token (often $2D)
;  requires lookahead/number handling, and also entered for tokens >= $30.
;
;  Purpose (inferred):
;    - Parse a numeric literal / numeric token sequence from the source line
;      (stream at DE) and build a packed representation in a workspace buffer
;      at $1E00.
;    - Encodes digits (and a few special cases) into nibbles/bytes in $1E00.
;    - Terminates/finishes the buffer with marker bytes ($0B/$0C) in certain cases.
;    - Eventually the resulting buffer is used by later code to emit math-coprocessor
;      bytecode/operands via $042E (not shown in this fragment).
;
;  Key mechanics:
;    - Saves/restores registers with EX AF,AF' and pushes DE.
;    - Uses HL=$1E00 as a destination buffer, DE as input pointer.
;    - Calls $0720 with B=$0F (likely clears/initializes a 0x0F-byte area).
;    - Packs values into (HL) while advancing HL/DE.
;    - Loops while input bytes are >= $28, treating them as digit-like tokens.
;    - Special-cases $20 (space) -> jump to $0577 (finish/emit).
;    - Handles '-' ($2D) specially by storing $0C marker and continuing.
; -----------------------------------------------------------------------------
050B: 0E 0C       LD C,$0C  ; set mode/flag in C (0x0C) for number parsing

050D: 7E          LD A,(HL)
050E: 23          INC HL

; This is the entry point from the expression parser for literal numbers (A >= x30)
; C should have the mode in it...
050F: 08          EX AF,AF'  ; save A in AF' (token/char), switch to alternate accumulator

0510: D5          PUSH DE  ; preserve DE (input pointer)

0511: EB          EX DE,HL  ; DE <- HL (input ptr), HL will become destination buffer
0512: 21 00 1E    LD HL,$1E00  ; HL = $1E00 (numeric literal workspace)
0515: 06 0F       LD B,$0F  ; B = $0F (size/count for init routine)
0517: CD 20 07    CALL $0720  ; init/clear workspace region (likely 0x0F bytes)

051A: 2E 09       LD L,$09  ; HL = $1E09
051C: 71          LD (HL),C  ; store mode/flag C at $1E09

051D: 2E 00       LD L,$00  ; HL = $1E00
051F: 08          EX AF,AF'
0520: E6 0F       AND $0F  ; extract low nibble (digit code)

0522: FE 0E       CP $0E
0524: 20 02       JR NZ,$0528
0526: 3E 0A       LD A,$0A  ; remap 0x0E -> 0x0A (special digit case)

0528: 77          LD (HL),A  ; store packed nibble/digit at workspace

0529: 1A          LD A,(DE)  ; fetch next source byte via DE

052A: 23          INC HL
052B: 13          INC DE
052C: FE 28       CP $28  ; if byte >= $28, continue accumulating digits

052E: 30 F0       JR NC,$0520
0530: FE 20       CP $20  ; if next byte is space, finish/emit via $0577

0532: 28 43       JR Z,$0577
0534: 2E 0A       LD L,$0A  ; write terminator/marker $0B at $1E0A

0536: 36 0B       LD (HL),$0B
0538: 23          INC HL
0539: 1A          LD A,(DE)
053A: 13          INC DE
053B: FE 2D       CP $2D  ; if next byte != '-' continue digit loop

053D: 20 E1       JR NZ,$0520
053F: 36 0C       LD (HL),$0C  ; write marker $0C (likely negative sign)

0541: 23          INC HL
0542: 7E          LD A,(HL)  ; reload current workspace byte (post-marker) and continue loop

0543: 18 DB       JR $0520
;
; Jumped to from BURP_EXPR_GET_TOKEN_AND_EMIT function.
; 
0545: 08          EX AF,AF'
0546: 3E 20       LD A,$20
0548: BE          CP (HL)  ; peek next source byte: space ($20) means single-token form

0549: 20 03       JR NZ,$054E
054B: 08          EX AF,AF'  ; NOTE in the original scan this byte was ambiguious but it is def 08 NOTE: $08 (EX AF,AF') is far more plausible here than $0B (DEC BC) given control-flow/AF' usage.
054C: 18 2D       JR $057B  ; if single-token form, branch to $057B (build/emit fixed-width value)

054E: 2B          DEC HL
054F: CD 95 07    CALL $0795  ; compute 2-token dispatch code (drops into $0795): returns A = C + 2*B

0552: FE 20       CP $20  ; normalize dispatch code into table index: if A<20, add 20


0554: 30 02       JR NC,$0558
0556: C6 20       ADD A,$20
0558: FE 50       CP $50  ; if A>=50, fold range down by subtracting 10

055A: 38 02       JR C,$055E
055C: D6 10       SUB $10
055E: C6 B4       ADD A,$B4  ; bias into ROM table region: index += B4

0560: C5          PUSH BC
0561: 4F          LD C,A
0562: 06 07       LD B,$07  ; BC := $07xx points at opcode descriptor table in ROM

0564: 0A          LD A,(BC)  ; A := opcode descriptor from ROM table


0565: C1          POP BC
0566: FE 80       CP $80  ; descriptor bit7 indicates prefix $20 should be emitted

0568: 38 07       JR C,$0571  ; bit7 set? => emit prefix $20 first

056A: 08          EX AF,AF'
056B: 3E 20       LD A,$20
056D: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=byte)

0570: 08          EX AF,AF'
0571: E6 3F       AND $3F  ; opcode := descriptor & 3F (low 6 bits)

0573: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=byte) ; emit opcode byte to math-coprocessor interface ($042E)

0576: C9          RET

; -----------------------------------------------------------------------------
; BURP_EXPR_FINISH_NUMBER_LITERAL_AND_EMIT_16B
;  Common tail used by BURP_EXPR_PARSE_NUMBER_LITERAL_AND_EMIT and also reached
;  from BURP_EXPR_DECODE_SMALLTOKEN_AND_EMIT_OP (via $0577/$057B).
;
;  Purpose (inferred):
;    - Restore pointers after number/symbol parsing (undo a DE increment, swap
;      DE/HL back, restore saved DE).
;    - Call $07AC to set up HL to point at a 16-byte buffer (often derived from
;      $1E00 workspace or a constant), then emit exactly 16 bytes via $042E.
;      This looks like pushing a fixed-width operand/descriptor block to the
;      math-coprocessor byte stream.
;
;  Behaviour:
;    - Sets A=0 (XOR A) before calling $07AC.
;    - Emits 16 bytes starting at (HL) after $07AC returns.
; -----------------------------------------------------------------------------
; -----------------------------------------------------------------------------
; BURP_EXPR_FINISH_NUMBER_LITERAL_AND_EMIT_16B ($0577)
;  Tail routine used after parsing a number literal (and also by the 'single-token'
;  small-token path) to emit a fixed-width 16-byte operand block to the MM57109 stream.
;
;  Behaviour (observed):
;    - Restores HL/DE after lookahead parsing
;    - Sets A=0 and calls $07AC to prepare HL to a 16-byte buffer
;    - Emits exactly 16 bytes via MM57109_SEND_INSTRUCTION_IN_A(A=byte) / $042E in a DJNZ loop
; -----------------------------------------------------------------------------
0577: 1B          DEC DE  ; step DE back one (caller had advanced past delimiter)
0578: EB          EX DE,HL  ; restore HL from DE (input pointer back to HL)
0579: D1          POP DE  ; restore DE saved earlier (POP)
057A: AF          XOR A  ; A := 0 (select default mode for $07AC)
057B: E5          PUSH HL  ; save HL, then call $07AC to prepare 16-byte emit source
057C: CD AC 07    CALL $07AC  ; BURP_PREPARE_16BYTE_OPERAND_BLOCK(A=selector)
057F: 06 10       LD B,$10  ; emit 16 bytes to coprocessor stream
0581: 7E          LD A,(HL)
0582: 23          INC HL
0583: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=(HL)) ; emit operand byte
0586: 10 F9       DJNZ $0581
0588: E1          POP HL  ; restore HL and return
0589: C9          RET

; -----------------------------------------------------------------------------
; MM57109_SEND_AND_WAIT_RDDY_BR ($058A)
;  Handles the MM57109 BR (branch) output which pulses low whenever one of the MM57109
;  branch instructions proves to be true.
;  Example instuctions are (passed in register A) are
;
;      TJC*   0x10(o20) - Test Jump Conditional
;      TX=0*  0x11(o21) - Test X=0
;      TXLTO* 0x12(o22) - Test X < 0 
;      TXF*   0x13(o23) - Test |X| < 1 i.e. test if x is a fraction
;      TERR*  0x14(o24) - Test error flag    
;
;  The subroutine starts the execution of the instruction in resgister A and then reads in
;  the 6 bit data word from the MM57109. The 4 digit out lines are blanked odd so that
;  only the READY and BR lines both initally high get through (0591). By continually reading
;  and jumping back on even parity the Z80 is effectively waiting for one of these two lines to become active.
;  If it is the BR line the Z80 outputs a NOP to the 57109 (because when tests prove true the 57109 
;  immediately looks for a new instruction and waits for its completion). 
;  If READY became active to indicate a failed test the last procedure is jumped. 
;  Finally the read in and masked byte which caused the exit from the parity check loop stored in register B 
;  as part of that loop is read into A and masked for bit 6 so that the state of the line and hence the zero flag in the F register is 
;  set on a successfil test.
;
;  Send a byte in A reg to the MM57109, then wait for a status condition on port $03, returns 
;  
;
;  Sequence (inferred from hardware description + code):
;    1) Calls MM57109_SEND_INSTRUCTION_IN_A(A=byte) to output the command/data.
;    2) Polls port $03 and examines bits $20 (RDY) and $40 (BR/test).
;       Uses a parity trick on (A & $60) to wait until exactly ONE of the two
;       status bits is asserted (i.e., value is $20 or $40; not $00 or $60).
;    3) If the asserted bit is RDY ($20), outputs $3F to port $60 and waits for
;       RDY to deassert (RDY==0).
;    4) Returns A = latched status bit6 (A & $40) from the sample taken.
;       (Z flag set if bit6 clear; NZ if bit6 set).
;
;  Calling convention:
;    IN : A = byte to send
;    OUT: A = $00 or $40 (bit6 status); flags reflect A (Z/NZ)
;    Preserves: BC (push/pop), restores DE/HL unchanged
; -----------------------------------------------------------------------------
058A: C5          PUSH BC  ; PUSH BC (preserve)
058B: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=byte) ; send command/data
058E: DB 03       IN A,($03)  ; poll port $03 (status + DO bits)
0590: 47          LD B,A  ; B := raw port sample (latched for return)
0591: E6 60       AND $60  ; mask status bits RDY($20) and BR($40)
0593: EA 8E 05    JP PE,$058E  ; loop while parity-even => 0 or 2 bits set ($00 or $60); exit when $20 or $40
0596: FE 30       CP $30  ; if masked value >= $30, it's $40 (BR) (since $60 would not exit)
0598: 30 04       JR NC,$059E
059A: 3E 3F       LD A,$3F  ; else it is $20 (RDY): Output a NOP instruction
059C: D3 60       OUT ($60),A  ; Output a NOP instruction ...
059E: DB 03       IN A,($03)  ; wait for RDY to deassert (bit5==0)
05A0: E6 20       AND $20
05A2: 20 FA       JR NZ,$059E
05A4: 78          LD A,B  ; A := latched raw port value
05A5: E6 40       AND $40  ; keep only bit6 (BR/test/status)
05A7: C1          POP BC  ; POP BC
05A8: C9          RET  ; RET with A=$00 or $40 (Z/NZ)

; -----------------------------------------------------------------------------
; BURP_FORMAT_AND_EMIT_NUMERIC_FIELD
;
; Inputs:
;   A  = operand-block selector for $07AC
;   DE = output pointer (destination buffer)
;
; Effects:
;   - Prepares operand record, normalises decimal point/spacing
;   - Performs rounding and fixed-width padding
;   - Copies formatted field to (DE)
;   - Optionally appends 3-byte suffix if record[+2A] == 05
;
; Calls:
;   $07AC  select/prepare 16-byte operand block (HL)
;   $07B7  transfer primitive (direction inferred: see notes)
; -----------------------------------------------------------------------------

05A9: E5          PUSH HL
05AA: D5          PUSH DE
05AB: CD AC 07    CALL $07AC      ; HL <- base of selected 16-byte operand block, BURP_PREPARE_16BYTE_OPERAND_BLOCK(A=selector)
05AE: E5          PUSH HL         ; save base pointer

05AF: 11 00 1E    LD DE,$1E00     ; DE = numeric formatting workspace
05B2: 7D          LD A,L
05B3: C6 09       ADD A,$09
05B5: 6F          LD L,A          ; HL = block + 9
05B6: CD B7 07    CALL $07B7      ; transfer workspace<->block at offset +9

05B9: E1          POP HL          ; restore block base
05BA: 06 09       LD B,$09
05BC: CD B7 07    CALL $07B7      ; transfer 9 bytes (loop)
05BF: 10 FB       DJNZ $05BC

05C1: 23          INC HL          ; skip (field boundary)
05C2: 06 06       LD B,$06
05C4: CD B7 07    CALL $07B7      ; transfer 6 bytes (loop)
05C7: 10 FB       DJNZ $05C4

05C9: EB          EX DE,HL        ; HL now indexes workspace record, DE holds block pointer

; --- normalise decimal point / leading digit structure ---

05CA: 2E 0C       LD L,$0C
05CC: 7E          LD A,(HL)
05CD: FE 30       CP $30          ; ASCII '0'?
05CF: 20 56       JR NZ,$0627     ; if not '0', skip leading-zero fixups

05D1: 2D          DEC L           ; L=0B
05D2: 7E          LD A,(HL)
05D3: FE A0       CP $A0          ; A0 = filler/blank marker?
05D5: 23          INC HL
05D6: 23          INC HL          ; advance to L=0D
05D7: 7E          LD A,(HL)
05D8: 20 17       JR NZ,$05F1     ; branch based on field content pattern

05DA: FE 38       CP $38          ; ASCII '8' boundary check (digit range test)
05DC: 30 49       JR NC,$0627     ; if >= '8', bail to decimal scan

; Case A: shift digits left and insert decimal point near front
05DE: 2E 03       LD L,$03
05E0: E6 0F       AND $0F         ; digit count nibble?
05E2: 28 3A       JR Z,$061E      ; if 0, skip to A0-fill

05E4: 47          LD B,A
05E5: 7E          LD A,(HL)
05E6: 2B          DEC HL
05E7: 77          LD (HL),A       ; shift bytes left by one
05E8: 23          INC HL
05E9: 23          INC HL
05EA: 10 F9       DJNZ $05E5
05EC: 2B          DEC HL
05ED: 36 2E       LD (HL),$2E     ; write '.' (decimal point)
05EF: 18 2D       JR $061E        ; continue with A0-fill

; Case B: alternative shift/decimal arrangement
05F1: FE 34       CP $34          ; ASCII '4' boundary
05F3: 30 32       JR NC,$0627
05F5: E6 0F       AND $0F
05F7: 28 25       JR Z,$061E

05F9: 47          LD B,A
05FA: 2E 01       LD L,$01
05FC: 7E          LD A,(HL)
05FD: 36 2E       LD (HL),$2E     ; place '.'
05FF: 23          INC HL
0600: 77          LD (HL),A       ; shift digit right

0601: 2E 08       LD L,$08
0603: 7E          LD A,(HL)
0604: 23          INC HL
0605: 77          LD (HL),A
0606: 2B          DEC HL
0607: 2B          DEC HL
0608: 7D          LD A,L
0609: FE 00       CP $00
060B: 20 F6       JR NZ,$0603
060D: 10 F2       DJNZ $0601

060F: 2E 01       LD L,$01
0611: 36 30       LD (HL),$30     ; force leading '0'
0613: 23          INC HL
0614: 23          INC HL
0615: 7E          LD A,(HL)
0616: FE 2E       CP $2E
0618: 20 04       JR NZ,$061E
061A: 36 30       LD (HL),$30     ; replace '.' adjacency with '0'
061C: 18 F6       JR $0614

; Fill a region with A0 (blank marker)
061E: 2E 0A       LD L,$0A
0620: 06 05       LD B,$05
0622: 36 A0       LD (HL),$A0
0624: 23          INC HL
0625: 10 FB       DJNZ $0622

; --- scan backward to decimal point '.' ---
0627: 3E 2E       LD A,$2E
0629: 2D          DEC L
062A: BE          CP (HL)
062B: 20 FC       JR NZ,$0629     ; loop until '.' found

; restore DE and recover an index nibble from next char
062D: D1          POP DE
062E: E3          EX (SP),HL
062F: 23          INC HL
0630: 7E          LD A,(HL)
0631: FE 30       CP $30
0633: 30 03       JR NC,$0638
0635: 2B          DEC HL
0636: 18 05       JR $063D
0638: E6 0F       AND $0F
063A: 32 E0 1F    LD ($1FE0),A    ; store digit nibble
063D: E3          EX (SP),HL

; compute placement / rounding target index based on $1FE0 + L
063E: 3A E0 1F    LD A,($1FE0)
0641: 85          ADD A,L
0642: FE 09       CP $09
0644: 30 3C       JR NC,$0682     ; if too large, skip rounding/pad path

0646: 6F          LD L,A
0647: 23          INC HL
0648: E5          PUSH HL         ; save rounding position
0649: 7E          LD A,(HL)
064A: FE 35       CP $35          ; >= '5' ?
064C: 38 2A       JR C,$0678      ; if < '5', no rounding increment

; rounding: walk left, skip '.', increment digit with carry
064E: 2D          DEC L
064F: 7D          LD A,L
0650: FE 01       CP $01
0652: 7E          LD A,(HL)
0653: 28 11       JR Z,$0666
0655: FE 2E       CP $2E
0657: 28 F5       JR Z,$064E      ; skip '.' while carrying

0659: 7E          LD A,(HL)
065A: FE 39       CP $39
065C: 28 03       JR Z,$0661      ; if '9', wrap to '0' and keep carrying
065E: 34          INC (HL)         ; increment digit
065F: 18 17       JR $0678         ; **(byte here should be 18, not 1B)** NOTE: $18 (JR) is strongly preferred over $1B; this is a forward jump over the carry/rounding block.

0661: 36 30       LD (HL),$30
0663: 7E          LD A,(HL)
0664: 18 E8       JR $064E

; carry reached left boundary: create leading '1' and shift decimal right
0666: FE 39       CP $39
0668: 20 F4       JR NZ,$065E
066A: 36 31       LD (HL),$31
066C: 3E 2E       LD A,$2E
066E: 2C          INC L
066F: BE          CP (HL)
0670: 20 FC       JR NZ,$066E
0672: 23          INC HL
0673: 77          LD (HL),A
0674: 2B          DEC HL
0675: 36 30       LD (HL),$30
0677: 00          NOP

; pad with spaces to fixed width
0678: E1          POP HL
0679: 3E 0A       LD A,$0A
067B: 95          SUB L
067C: 47          LD B,A
067D: 36 20       LD (HL),$20      ; ASCII space
067F: 23          INC HL
0680: 10 FB       DJNZ $067D

; emit up to 10 chars to output buffer (DE), stop on space
0682: 2E 00       LD L,$00
0684: 06 0A       LD B,$0A
0686: 7E          LD A,(HL)
0687: FE 20       CP $20
0689: 28 05       JR Z,$0690
068B: 12          LD (DE),A
068C: 13          INC DE
068D: 23          INC HL
068E: 10 F6       DJNZ $0686

; output padding/separators depending on next source character and remaining width
0690: E3          EX (SP),HL
0691: 23          INC HL
0692: 7E          LD A,(HL)
0693: FE 2C       CP $2C          ; comma?
0695: 00          NOP
0696: E3          EX (SP),HL
0697: 28 11       JR Z,$06AA

0699: AF          XOR A
069A: B8          CP B
069B: 28 03       JR Z,$06A0
069D: E7          RST $20         ; emit filler (likely space)
069E: 10 FD       DJNZ $069D

06A0: 2E 0A       LD L,$0A
06A2: 7E          LD A,(HL)
06A3: FE 05       CP $05
06A5: 28 03       JR Z,$06AA
06A7: E7          RST $20
06A8: E7          RST $20
06A9: E7          RST $20

; optional 3-byte suffix if record[+2A] == 05
06AA: 2E 2A       LD L,$2A         ; **(byte here should be 2A, not xA)**
06AC: 7E          LD A,(HL)
06AD: FE 05       CP $05
06AF: 20 08       JR NZ,$06B9
06B1: 06 03       LD B,$03
06B3: 23          INC HL
06B4: 7E          LD A,(HL)
06B5: 12          LD (DE),A
06B6: 13          INC DE
06B7: 10 FA       DJNZ $06B3

06B9: E1          POP HL
06BA: C9          RET




; -----------------------------------------------------------------------------
; BURP_TOKEN26_PARSE_FORMAT_SPECIFIER (inferred)
;
; Called from the statement parser when it encounters token $26:
;   0996: CP $26
;   099F: CALL $06BB   ; with A = (HL)  (selector / format subtype)
;
; High-level purpose (best-fit inference):
;   Parse a *numeric formatting specifier* (field/precision/flags) from the
;   token stream and build a normalised 10-character ASCII field (plus metadata)
;   into a 16-byte workspace block selected by A (via $0714/$07AC).
;
; What makes this routine "odd" is the repeated opcode $76 (HALT).  In the
; context of BURP parsing, these behave like "consume next token/char into A"
; checkpoints.  On real hardware the system is interrupt-driven, so HALT is used
; as a cheap synchronisation point while an interrupt service routine supplies
; the next input token/character.  If your ROM listing has any ambiguity around
; $76 bytes, these are the *first* ones to re-check on the original printout.
;
; Data layout (inferred within the selected 16-byte block):
;   Offsets are relative to the base address produced by $07AC / initialised by $0714.
;   - $+00..$+09 : 10-char ASCII field being built (right-justified), padded with ' '
;   - $+0A..$+0E : padding/flags area (initialised to $A0 later)
;   - $+2A..$+2D : optional extra 3-byte suffix copied out if block+$2A == 05
;     (Note: this implies the "block" can be a larger structure than 16 bytes;
;      $07AC seems to return a base inside a wider workspace region.)
;
; Behaviour summary:
;   1) Initialises the operand/format workspace (CALL $0714).
;   2) Parses an optional leading '-' and/or '.' and a run of digit-like tokens
;      (>= $28, digit encoded in low nibble) into the field buffer.
;   3) Normalises / shifts digits to insert a decimal point '.' (0x2E) when needed:
;      - If it detects an exponent or specific prefix pattern, it shifts right/left
;        and inserts '.' at a fixed position.
;   4) Pads the tail of the field with spaces to a fixed width.
;   5) Copies the resulting 10-char field to the output buffer at DE.
;   6) Handles separators/terminators:
;      - If next input is ',' then it may emit additional items
;      - It expects $1F as an end-of-line/statement sentinel (via RST $20 checks)
;   7) Optionally appends a 3-byte suffix from offset $2B..$2D when offset $2A == 05.
;
; Side-effects:
;   - Writes a small "digit count"/index nibble to $1FE0 during normalisation.
;   - On exit, DE points just past the copied output bytes.
;
; Open questions / likely dump ambiguities:
;   - The many $76 bytes are semantically "wait/consume next token"; confirm against scan.
;   - 06AA: 'LD L,$2A' looks intentional (offset $2A), but scan quality could confuse '2A' with 'xA'.
; -----------------------------------------------------------------------------
06BB: E5          PUSH HL
06BC: CD 14 07    CALL $0714
06BF: 01 0A 09    LD BC,$090A
06C2: 76          HALT
06C3: FE 2D       CP $2D
06C5: 20 08       JR NZ,$06CF
06C7: 7D          LD A,L
06C8: E6 F9       AND $F9
06CA: 6F          LD L,A
06CB: 3E 0C       LD A,$0C
06CD: 77          LD (HL),A
06CE: 76          HALT
06CF: 08          EX AF,AF'
06D0: 7D          LD A,L
06D1: E6 F0       AND $F0
06D3: 6F          LD L,A
06D4: 08          EX AF,AF'
06D5: FE 28       CP $28
06D7: 38 16       JR C,$06EF
06D9: FE 2E       CP $2E
06DB: 20 03       JR NZ,$06E0
06DD: 79          LD A,C
06DE: 0E 00       LD C,$00
06E0: E6 0F       AND $0F
06E2: 77          LD (HL),A
06E3: 23          INC HL
06E4: 76          HALT
06E5: 10 EE       DJNZ $06D5
06E7: 06 01       LD B,$01
06E9: FE 30       CP $30
06EB: 30 F7       JR NC,$06E4
06ED: 18 01       JR $06F0
06EF: 71          LD (HL),C
06F0: FE 20       CP $20
06F2: 28 1E       JR Z,$0712
06F4: 7D          LD A,L
06F5: E6 F0       AND $F0
06F7: C6 0A       ADD A,$0A
06F9: 6F          LD L,A
06FA: 36 0B       LD (HL),$0B
06FC: 23          INC HL
06FD: 06 02       LD B,$02
06FF: 76          HALT
0700: FE 2D       CP $2D
0702: 20 05       JR NZ,$0709
0704: 3E 0C       LD A,$0C
0706: 77          LD (HL),A
0707: 18 F4       JR $06FD
0709: 23          INC HL
070A: 00          NOP
070B: E6 0F       AND $0F
070D: 77          LD (HL),A
070E: 00          NOP
070F: 10 EE       DJNZ $06FF
0711: E7          RST $20
0712: E1          POP HL
0713: C9          RET

; -----------------------------------------------------------------------------
; BURP_INIT_16BYTE_OPERAND_BLOCK  ($0714)
;
; Purpose:
;   Initialise a selected 16-byte operand/descriptor block in BURP workspace
;   memory ($1E00–$1EFF or $1F00–$1FFF). This sets a known baseline before
;   callers pack digits, punctuation markers, and control bytes into the block.
;
; Block selection:
;   Uses $07AC with selector A:
;     - Low nibble (A & $0F) selects which 16-byte slot
;     - Bit4 selects page:
;         bit4=0 -> base $1E00
;         bit4=1 -> base $1F00
;   Returns HL = base + (A & $0F)*16.
;
; Initialised layout (relative to returned HL base):
;   [00..08] = 00 00 00 00 00 00 00 00 00    ; 9 bytes cleared
;   [09..0E] = 0F 0F 0F 0F 0F 0F              ; 6 bytes set to 0F (nibble filler)
;   [0F]     = 3F                             ; final control/terminator byte
;
; Interpretation (inferred from usage):
;   - The [09..0E]=0F region looks like “unset digit/nibble placeholders”.
;   - The final byte 3F is a common “all ones / terminator / default control”
;     value in this ROM (and also appears in MM57109 handshake-related logic),
;     so this likely marks the record as “initialised / empty / default”.
;
; Inputs:
;   A = operand block selector (passed through to $07AC)
;
; Outputs:
;   The 16-byte block is initialised in RAM.
;   HL is left pointing at the final byte (offset +0F).
;
; Called from:
;   - $06BB (token $26 path) before building a packed numeric/format operand
;   - Other operand/format preparation paths that fill these 16 bytes
; -----------------------------------------------------------------------------
0714: CD AC 07    CALL $07AC      ; HL <- base of selected 16-byte block ($1Exx/$1Fxx),BURP_PREPARE_16BYTE_OPERAND_BLOCK(A=selector)

0717: 06 09       LD  B,$09       ; clear first 9 bytes
0719: AF          XOR A           ; A=00
071A: 77          LD  (HL),A
071B: 23          INC HL
071C: 10 FC       DJNZ $071A

071E: 06 06       LD  B,$06       ; fill next 6 bytes with 0F

;
; Fill region with count stored in B, with 0F, terminate with 3F
;
0720: 3E 0F       LD  A,$0F
0722: 77          LD  (HL),A
0723: 23          INC HL
0724: 10 FC       DJNZ $0722

0726: 36 3F       LD  (HL),$3F    ; record[+0F] = 3F (terminator/default)
0728: C9          RET

; ## BURP_WAIT_KEY ($0729)

0729: 76          HALT
072A: 47          LD B,A
072B: 76          HALT
072C: 4F          LD C,A
072D: 76          HALT
072E: FE 20       CP $20
0730: 20 FA       JR NZ,$072C
0732: 79          LD A,C
0733: 80          ADD A,B
0734: 80          ADD A,B
0735: C9          RET
0736: 76          HALT
0737: E6 0F       AND $0F
0739: 4F          LD C,A
073A: 76          HALT
073B: FE 20       CP $20
073D: C8          RET Z
073E: E6 0F       AND $0F
0740: 47          LD B,A
0741: 79          LD A,C
0742: 07          RLCA
0743: 4F          LD C,A
0744: 07          RLCA
0745: 07          RLCA
0746: 81          ADD A,C
0747: 80          ADD A,B
0748: 18 EF       JR $0739
074A: C5          PUSH BC
074B: 06 30       LD B,$30
074D: FE 64       CP $64
074F: 38 05       JR C,$0756
0751: 04          INC B
0752: D6 64       SUB $64
0754: 18 F7       JR $074D
0756: 0E 30       LD C,$30
0758: FE 0A       CP $0A
075A: 38 05       JR C,$0761
075C: 0C          INC C
075D: D6 0A       SUB $0A
075F: 18 F7       JR $0758
0761: C6 30       ADD A,$30
0763: EB          EX DE,HL
0764: 70          LD (HL),B
0765: 23          INC HL
0766: 71          LD (HL),C
0767: 23          INC HL
0768: 77          LD (HL),A
0769: 23          INC HL
076A: EB          EX DE,HL
076B: C1          POP BC
076C: C9          RET
076D: C5          PUSH BC
076E: 01 30 30    LD BC,$3030
0771: FE 64       CP $64
0773: 38 05       JR C,$077A
0775: D6 64       SUB $64
0777: 04          INC B
0778: 18 F7       JR $0771
077A: FE 0A       CP $0A
077C: 38 05       JR C,$0783
077E: D6 0A       SUB $0A
0780: 0C          INC C
0781: 18 F7       JR $077A
0783: F5          PUSH AF
0784: 78          LD A,B
0785: CD A5 02    CALL $02A5 — MON: CP A,$1B ;
0788: 79          LD A,C
0789: CD A5 02    CALL $02A5 — MON: CP A,$1B ;
078C: F1          POP AF
078D: C6 30       ADD A,$30
078F: CD A5 02    CALL $02A5 — MON: CP A,$1B ;
0792: C1          POP BC
0793: C9          RET

; 0794: BURP_DECODE_LINE_OPCODE
; HL -> byte after line number
; Returns A = statement dispatch code
;
; Gets the 1st char of text and the last char before a space and makes a uniq token from it.

0794: 23          INC HL    ; move past the line number byte
0795: 46          LD B,(HL) ; load next token into B
0796: 23          INC HL    ; move to next token on line
0797: 4E          LD C,(HL) ; move token into C
0798: 23          INC HL    ; move to next token
0799: 7E          LD A,(HL) ; move token into A
079A: FE 20       CP $20    ; is it a space
079C: 20 F9       JR NZ,$0797 ; loop until it is a space
079E: 79          LD A,C    ;  C holds last char and b the 1st char
079F: 80          ADD A,B   ; make a uniq token for the word
07A0: 80          ADD A,B   ;
07A1: C9          RET       ; Return

07A2: 17          RLA
07A3: 12          LD (DE),A
07A4: 09 14 05    ADD HL,BC
07A7: 10 12       DJNZ $07BB
07A9: 09 0E 14    ADD HL,BC
; -----------------------------------------------------------------------------
; BURP_PREPARE_16BYTE_OPERAND_BLOCK ($07AC)
;  Prepare HL to point at a fixed 16-byte operand/descriptor block.
;
;  Calling convention:
;    IN : A = block selector. Low nibble selects which 16-byte block.
;         Bit4 selects base page: 0 -> $1E00, 1 -> $1F00.
;    OUT: HL = base + (A & $0F) * 16, where base is $1E00 or $1F00.
;    Flags: C is used as a convenient bit4 test (carry after 4x RLA).
;
;  Implementation notes:
;    AND A clears carry. Four RLA operations effectively compute (A << 4)
;    and leave carry = original bit4. L receives the shifted value.
;    If carry set (original bit4=1) H is incremented to select page $1Fxx.
; -----------------------------------------------------------------------------
07AC: A7          AND A  ; clear carry; set flags from A (selector)
07AD: 26 1E       LD H,$1E  ; H := $1E (base page $1E00)
07AF: 17          RLA  ; shift selector left 1 (1/4): builds offset*16; carry tracks original bit4 after 4 shifts
07B0: 17          RLA  ; shift left (2/4)
07B1: 17          RLA  ; shift left (3/4)
07B2: 17          RLA  ; shift left (4/4)
07B3: 6F          LD L,A  ; L := A (low byte = (selector<<4) & $F0)
07B4: D0          RET NC  ; if carry==0 (original bit4=0), return with HL in $1E00 page
07B5: 24          INC H  ; else select $1F00 page
07B6: C9          RET  ; return

07B7: 7E          LD A,(HL)
07B8: FE 0B       CP $0B
07BA: 20 02       JR NZ,$07BE
07BC: 3E D5       LD A,$D5
07BE: FE 0A       CP $0A
07C0: 20 02       JR NZ,$07C4
07C2: 3E FE       LD A,$FE
07C4: FE 0F       CP $0F
07C6: 20 02       JR NZ,$07CA
07C8: 3E 70       LD A,$70
07CA: FE 0C       CP $0C
07CC: 20 02       JR NZ,$07D0
07CE: 3E FD       LD A,$FD
07D0: C6 30       ADD A,$30
07D2: 12          LD (DE),A
07D3: 13          INC DE
07D4: 23          INC HL
07D5: C9          RET
07D6: 31 0C 3F    LD SP,$3F0C
07D9: 3F          CCF
07DA: 35          DEC (HL)
07DB: 37          SCF
07DC: 2C          INC L
07DD: 0D          DEC C
07DE: 3F          CCF
07DF: 3F          CCF
07E0: 1D          DEC E
07E1: 1C          INC E
07E2: 3F          CCF
07E3: 22 23 3F    LD ($3F23),HL
07E6: 3F          CCF
07E7: A5          AND L
07E8: 24          INC H
07E9: 3F          CCF
07EA: 26 33       LD H,$33
07EC: 34          INC (HL)
07ED: 25          DEC H
07EE: 2D          DEC L
07EF: 2F          CPL
07F0: 2B          DEC HL
07F1: 1B          DEC DE
07F2: 21 36 32    LD HL,$3236
07F5: 3F          CCF
07F6: 3F          CCF
07F7: A4          AND H
07F8: 3F          CCF
07F9: A6          AND (HL)
07FA: 3F          CCF
07FB: 3F          CCF
07FC: 3F          CCF
07FD: 30 38       JR NC,$0837
07FF: F0          RET P

; ## BURP_ENTRY ($0800)

0800: 31 DF 1F    LD SP,$1FDF
0803: 11 00 80    LD DE,$8000
0806: CD CE 03    CALL $03CE — MON: EX (SP),HL ; HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0809-080F terminated by $1D
0809:              DB  $20,$02,$15,$12,$10,$20,$1D  ; " BURP "
0810: E7          RST $20
0811: E7          RST $20
0812: D5          PUSH DE
0813: CD C4 03    CALL $03C4
0816: D1          POP DE
0817: 3E 04       LD A,$04
0819: 32 E0 1F    LD ($1FE0),A
081C: 1E 08       LD E,$08
081E: 3E 40       LD A,$40
0820: CD 36 03    CALL $0336 — MON: EX (SP),HL ; HL = return address (points to inline delay count byte) [MON:INLINE_DELAY_1B]
0823: 10 3E       DJNZ $0863
0825: 3F          CCF
0826: D3 60       OUT ($60),A
0828: ED 56       IM 1
082A: CD 36 03    CALL $0336 — MON: EX (SP),HL ; HL = return address (points to inline delay count byte) [MON:INLINE_DELAY_1B]
082D: 90          SUB B
082E: 3E BF       LD A,$BF
0830: D3 60       OUT ($60),A
0832: CD 46 04    CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 0835-0837 terminated by $FF
0835:              DB  $2F,$22,$FF  ; MM57109 instructions MCLR,TOGM,
0839: 29 07 FE    ADD HL,None
083C: 14          INC D
083D: 20 7F       JR NZ,$08BE
083F: E7          RST $20
0840: CD 36 07    CALL $0736
0843: 21 00 0C    LD HL,$0C00
0846: 7E          LD A,(HL)
0847: FE C0       CP $C0
0849: 28 B5       JR Z,$0800
084B: 23          INC HL
084C: FE ED       CP $ED
084E: 20 F6       JR NZ,$0846
0850: 7E          LD A,(HL)
0851: B9          CP C
0852: 20 F3       JR NZ,$0847
0854: 2B          DEC HL
0855: 2B          DEC HL
0856: E5          PUSH HL
0857: D1          POP DE
0858: 13          INC DE
0859: 1A          LD A,(DE)
085A: FE 1F       CP $1F
085C: 20 FA       JR NZ,$0858
085E: 1A          LD A,(DE)
085F: 77          LD (HL),A
0860: 23          INC HL
0861: 13          INC DE
0862: 7A          LD A,D
0863: FE 1E       CP $1E
0865: 2B          DEC HL
0866: F7          RST $30
0867: 0E 01       LD C,$01
0869: CD 93 03    CALL $0393 — MON: PUSH DE ; [MON:CLEAR_SCREEN_8040_87FF]
086C: 11 40 80    LD DE,$8040
086F: 0D          DEC C
0870: 0C          INC C
0871: 20 05       JR NZ,$0878
0873: CD 9F 03    CALL $039F — MON: LD A,H ; [MON:PRINT_HEX_WORD_HL]
0876: 18 88       JR $0800
0878: 21 00 0C    LD HL,$0C00
087B: 7E          LD A,(HL)
087C: FE C0       CP $C0
087E: 28 F0       JR Z,$0870
0880: FE ED       CP $ED
0882: 23          INC HL
0883: 20 F6       JR NZ,$087B
0885: 7E          LD A,(HL)
0886: B9          CP C
0887: 20 F7       JR NZ,$0880
0889: CD 4A 07    CALL $074A
088C: E7          RST $20
088D: 7A          LD A,D
088E: FE 88       CP $88
0890: 20 16       JR NZ,$08A8
0892: CD CE 03    CALL $03CE — MON: EX (SP),HL ; HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0895-08A4 terminated by $1D
0895:              DB  $0C,$09,$13,$14,$20,$09,$0E,$03,$0F,$0D,$10,$0C,$05,$14,$05,$1D  ; "LIST INCOMPLETE"
08A5: 76          HALT
08A6: 18 C1       JR $0869
08A8: 23          INC HL
08A9: 7E          LD A,(HL)
08AA: FE C0       CP $C0
08AC: 28 C2       JR Z,$0870
08AE: 12          LD (DE),A
08AF: 13          INC DE
08B0: FE 1F       CP $1F
08B2: 20 F4       JR NZ,$08A8
08B4: CD C4 03    CALL $03C4
08B7: 7A          LD A,D
08B8: FE 1E       CP $1E
08BA: 20 B4       JR NZ,$0870
08BC: 18 B8       JR $0876
08BE: F5          PUSH AF
08BF: CD 93 03    CALL $0393 — MON: PUSH DE ; [MON:CLEAR_SCREEN_8040_87FF]
08C2: F1          POP AF
08C3: FE 1E       CP $1E
08C5: 20 2C       JR NZ,$08F3
08C7: 21 FF 0B    LD HL,$0BFF
08CA: 23          INC HL
08CB: 7E          LD A,(HL)
08CC: FE C0       CP $C0
08CE: 28 97       JR Z,$0867
08D0: FE ED       CP $ED
08D2: 20 F6       JR NZ,$08CA
08D4: 23          INC HL
08D5: CD 94 07    CALL $0794
08D8: FE 34       CP $34
08DA: 20 0D       JR NZ,$08E9
08DC: 11 A6 07    LD DE,$07A6
08DF: 01 05 00    LD BC,$0005
08E2: EB          EX DE,HL
08E3: 1B          DEC DE
08E4: ED B8       LDDR
08E6: EB          EX DE,HL
08E7: 18 E1       JR $08CA
08E9: FE 33       CP $33
08EB: 20 DD       JR NZ,$08CA
08ED: 11 AB 07    LD DE,$07AB
08F0: 18 ED       JR $08DF
08F2: 0E FE       LD C,$FE
08F4: 06 20       LD B,$20
08F6: 30 21       JR NC,$0919
08F8: FF          RST $38
08F9: 0B          DEC BC
08FA: 23          INC HL
08FB: 7E          LD A,(HL)
08FC: FE C0       CP $C0
08FE: 20 FA       JR NZ,$08FA
0900: 18 03       JR $0905
0902: 21 00 0C    LD HL,$0C00
0905: 11 40 80    LD DE,$8040
0908: 36 ED       LD (HL),$ED
090A: 23          INC HL
090B: CD 36 07    CALL $0736
090E: 71          LD (HL),C
090F: 23          INC HL
0910: 76          HALT
0911: FE 3A       CP $3A
0913: 28 0B       JR Z,$0920
0915: CD D6 00    CALL $00D6 — MON: CP A,$1B ;
0918: 77          LD (HL),A
0919: 23          INC HL
091A: FE 1F       CP $1F
091C: 28 EA       JR Z,$0908
091E: 18 F0       JR $0910
0920: 36 1F       LD (HL),$1F
0922: 23          INC HL
0923: 36 C0       LD (HL),$C0
0925: 18 95       JR $08BC
0927: FE 1C       CP $1C
0929: 28 D7       JR Z,$0902
092B: FE 2C       CP $2C
092D: 20 06       JR NZ,$0935
092F: CD 36 07    CALL $0736
0932: C3 69 08    JP $0869
0935: FE 18       CP $18
0937: 20 3A       JR NZ,$0973
0939: CD 36 07    CALL $0736
093C: CD F0 02    CALL $02F0 — MON: LD A,$1D ;
093F: 0D          DEC C
0940: 0C          INC C
0941: 20 05       JR NZ,$0948
0943: CD 7F 02    CALL $027F — MON: CALL $02F0 ;
0946: 18 DD       JR $0925
0948: 21 00 0C    LD HL,$0C00
094B: 7E          LD A,(HL)
094C: FE C0       CP $C0
094E: 28 F0       JR Z,$0940
0950: FE ED       CP $ED
0952: 23          INC HL
0953: 20 F6       JR NZ,$094B
0955: 7E          LD A,(HL)
0956: B9          CP C
0957: 20 F7       JR NZ,$0950
0959: CD 6D 07    CALL $076D
095C: CD EC 02    CALL $02EC — MON: LD A,$1C ;
095F: 23          INC HL
0960: 7E          LD A,(HL)
0961: FE C0       CP $C0
0963: 28 DB       JR Z,$0940
0965: FE 1F       CP $1F
0967: 28 05       JR Z,$096E
0969: CD A5 02    CALL $02A5 — MON: CP A,$1B ;
096C: 18 F1       JR $095F
096E: CD F0 02    CALL $02F0 — MON: LD A,$1D ;
0971: 18 CD       JR $0940
0973: FE 32       CP $32
0975: 20 BE       JR NZ,$0935
0977: CD 36 07    CALL $0736
097A: 11 40 80    LD DE,$8040
097D: 0D          DEC C
097E: C5          PUSH BC
097F: C1          POP BC
0980: 0C          INC C
0981: C5          PUSH BC
; -----------------------------------------------------------------------------
;
; Main parse  loop 
; 
; -----------------------------------------------------------------------------
0982: 21 00 0C    LD HL,$0C00 ;  Looks like the main parse of the program. 0C00 is where BURP programs are loaded into.
0985: 7E          LD A,(HL)   ; Get next char in program... Look for end of program of start of line markers
0986: FE C0       CP $C0      ; C0 is the end of program marker 
0988: 28 F5       JR Z,$097F  ; Jump here if its all over 
098A: FE ED       CP $ED      ; is it the start of line marker
098C: 23          INC HL      ; move onto next char
098D: 20 F6       JR NZ,$0985 ; if not start of line marker or end of program, loop 
098F: 7E          LD A,(HL)   ; Get the line number
0990: B9          CP C        ; C holds the line we are interested in
0991: 20 F7       JR NZ,$098A ; if its not loop until we find the right line.
0993: CD 94 07    CALL $0794  ; We are at the right line, parse the opcode BURP_DECODE_LINE_OPCODE A returns the code.

;
; Parse token 26
;
0996: FE 26       CP $26    ; token $26: parse numeric format specifier (CALL $06BB on following selector byte)
0998: 20 14       JR NZ,$09AE
099A: CD C4 03    CALL $03C4
099D: 23          INC HL
099E: 7E          LD A,(HL)
099F: CD BB 06    CALL $06BB
09A2: 23          INC HL
09A3: 7E          LD A,(HL)
09A4: FE 20       CP $20
09A6: 28 FA       JR Z,$09A2
09A8: FE 1F       CP $1F
09AA: 20 F2       JR NZ,$099E
09AC: 18 D1       JR $097F
;
; Parse token 34 - PRINT Statement.
;
09AE: FE 34       CP $34
09B0: 20 22       JR NZ,$09D4
09B2: CD C4 03    CALL $03C4
09B5: 23          INC HL
09B6: 7E          LD A,(HL)
09B7: FE 20       CP $20
09B9: 28 FA       JR Z,$09B5
09BB: FE 1F       CP $1F
09BD: 28 C0       JR Z,$097F
09BF: FE 22       CP $22
09C1: 20 0A       JR NZ,$09CD
09C3: 23          INC HL
09C4: 7E          LD A,(HL)
09C5: FE 22       CP $22
09C7: 28 EC       JR Z,$09B5
09C9: 12          LD (DE),A
09CA: 13          INC DE
09CB: 18 F6       JR $09C3
09CD: FE 1B       CP $1B
09CF: DC A9 05    CALL C,$05A9
09D2: 18 E1       JR $09B5
;
; Parse token 0e
;
09D4: FE 0E       CP $0E
09D6: 20 03       JR NZ,$09DB
09D8: C3 00 08    JP $0800
;
; Parse token 1D 
;
09DB: FE 1D       CP $1D
09DD: 20 08       JR NZ,$09E7
09DF: 23          INC HL
09E0: 7E          LD A,(HL)
09E1: CD BA 04    CALL $04BA
09E4: E1          POP HL
09E5: 18 9A       JR $0981
;
; Parse token 2C - LET statement.
;
09E7: FE 2C       CP $2C
09E9: 20 15       JR NZ,$0A00
09EB: 23          INC HL
09EC: 46          LD B,(HL)
09ED: C5          PUSH BC
09EE: 23          INC HL
09EF: 23          INC HL
09F0: 7E          LD A,(HL)
09F1: FE 1F       CP $1F
09F3: 20 06       JR NZ,$09FB
09F5: F1          POP AF
09F6: CD 60 04    CALL $0460  ; BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)

09F9: 18 84       JR $097F
09FB: CD E6 04    CALL $04E6
09FE: 18 EF       JR $09EF
;
; Parse token 18 
;
; -----------------------------------------------------------------------------
; BURP_STMT_TOKEN18_EXECUTE_MATH_OP ($0A00)
;  Statement handler for token $18.
;
;  Behaviour (inferred from code & MM57109 helpers):
;    - Reads an operand block selector byte from the source stream and emits a fixed
;      16-byte operand/descriptor block via BURP_EXPR_FINISH_NUMBER_LITERAL_AND_EMIT_16B
;      (entry at $057B).
;    - Parses the next expression token(s) via BURP_EXPR_GET_TOKEN_AND_EMIT ($04E6),
;      extending the MM57109 command stream.
;    - Emits MM57109 separator/marker bytes ($3A and sometimes $30) and then sends
;      either $11 or $12 via MM57109_SEND_AND_WAIT_RDDY_BR ($058A) depending on the
;      following token ($3D/$3E checks on B).
;    - Branches based on the returned status bit6 (A&$40) from $058A:
;        NZ -> $09F9 (abort/return-to-monitor path)
;        Z  -> continue scanning to next numeric token and resume at $09E1
;
;  Calling convention:
;    IN : HL -> token stream positioned just before/at token $18 operands
;    Uses: B as lookahead token, emits multiple bytes via MM57109_SEND_INSTRUCTION_IN_A.
; -----------------------------------------------------------------------------
0A00: FE 18       CP $18  ; dispatch: token == $18 ?

0A02: 20 3B       JR NZ,$0A3F  ; if not token $18, try next statement handler

0A04: 23          INC HL  ; advance to operand selector byte

0A05: 7E          LD A,(HL)  ; A := operand-block selector

0A06: CD 7B 05    CALL $057B  ; emit 16-byte operand/descriptor block to MM57109 stream (A selects block)

0A09: 23          INC HL  ; advance to next token after operand selector

0A0A: 46          LD B,(HL)  ; B := lookahead token

0A0B: 23          INC HL
0A0C: 7E          LD A,(HL)  ; A := next token/value

0A0D: C5          PUSH BC  ; save BC across expression emit

0A0E: CD E6 04    CALL $04E6  ; emit next expression token(s) to MM57109 stream (skips spaces etc.)

0A11: C1          POP BC
0A12: 78          LD A,B  ; A := lookahead token B

0A13: A7          AND A
0A14: FE 3E       CP $3E
0A16: 20 05       JR NZ,$0A1D  ; if B == $3E then also emit marker $30

0A18: 3E 30       LD A,$30
0A1A: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=$30) ; optional marker


0A1D: 3E 3A       LD A,$3A  ; emit separator/marker $3A to MM57109 stream

0A1F: CD 2E 04    CALL $042E  ; MM57109_SEND_INSTRUCTION_IN_A(A=$3A)


0A22: 78          LD A,B  ; choose command byte based on B ($3D ?)

0A23: A7          AND A
0A24: FE 3D       CP $3D
0A26: 20 04       JR NZ,$0A2C
0A28: 3E 11       LD A,$11  ; if B == $3D use $11 else use $12

0A2A: 18 02       JR $0A2E
0A2C: 3E 12       LD A,$12    ; Send MM57109 TXLTO* 
0A2E: CD 8A 05    CALL $058A  ; send $11/$12 and wait for RDY/BR status; returns A&$40 (Z/NZ)


0A31: 20 C6       JR NZ,$09F9  ; if status bit6 set (NZ), branch to abort/return-to-monitor path

0A33: 23          INC HL  ; scan forward until reaching a token >= $30 (numeric/identifier region)

0A34: 7E          LD A,(HL)
0A35: FE 30       CP $30
0A37: 38 FA       JR C,$0A33  ; loop while token < $30

0A39: 18 A6       JR $09E1  ; resume main execution/parse loop

0A3B: 18 BC       JR $09F9  ; abort/return-to-monitor path

0A3D: 18 A5       JR $09E4  ; alternate resume/cleanup path

;
; Parse token 33 
;
0A3F: FE 33       CP $33
0A41: 20 3C       JR NZ,$0A7F
0A43: CD F0 02    CALL $02F0 — MON: LD A,$1D ;
0A46: D5          PUSH DE
0A47: 11 C0 1D    LD DE,$1DC0
0A4A: D5          PUSH DE
0A4B: 23          INC HL
0A4C: 7E          LD A,(HL)
0A4D: FE 20       CP $20
0A4F: 28 FA       JR Z,$0A4B
0A51: FE 1F       CP $1F
0A53: 28 15       JR Z,$0A6A
0A55: FE 22       CP $22
0A57: 20 0A       JR NZ,$0A63
0A59: 23          INC HL
0A5A: 7E          LD A,(HL)
0A5B: FE 22       CP $22
0A5D: 28 EC       JR Z,$0A4B
0A5F: 12          LD (DE),A
0A60: 13          INC DE
0A61: 18 F6       JR $0A59
0A63: FE 1B       CP $1B
0A65: DC A9 05    CALL C,$05A9
0A68: 18 E1       JR $0A4B
0A6A: 3E FF       LD A,$FF
0A6C: 12          LD (DE),A
0A6D: 00          NOP
0A6E: D1          POP DE
0A6F: 1A          LD A,(DE)
0A70: FE FF       CP $FF
0A72: 28 08       JR Z,$0A7C
0A74: E6 3F       AND $3F
0A76: CD A5 02    CALL $02A5 — MON: CP A,$1B ;
0A79: 13          INC DE
0A7A: 18 F3       JR $0A6F
0A7C: D1          POP DE
0A7D: 18 BC       JR $0A3B
;
; Parse token 0F 
;
0A7F: FE 0F       CP $0F
0A81: 20 08       JR NZ,$0A8B
0A83: 11 40 80    LD DE,$8040
0A86: CD 93 03    CALL $0393 — MON: PUSH DE ; [MON:CLEAR_SCREEN_8040_87FF]
0A89: 18 F2       JR $0A7D
;
; Parse token 38
;
0A8B: FE 38       CP $38
0A8D: 20 0B       JR NZ,$0A9A
0A8F: 11 40 80    LD DE,$8040
0A92: D5          PUSH DE
0A93: E7          RST $20
0A94: CD C4 03    CALL $03C4
0A97: D1          POP DE
0A98: 18 EF       JR $0A89
;
; Parse token 10
;
0A9A: FE 10       CP $10
0A9C: 20 08       JR NZ,$0AA6
0A9E: 23          INC HL
0A9F: 7E          LD A,(HL)
0AA0: CD BA 04    CALL $04BA
0AA3: E5          PUSH HL
0AA4: 18 97       JR $0A3D
;
; Parse token 32
;
0AA6: FE 32       CP $32
0AA8: 20 04       JR NZ,$0AAE
0AAA: C1          POP BC
0AAB: 00          NOP
0AAC: 18 8D       JR $0A3B
; ------------------------------------------------------------
; Parse token 1E  -- FOR
; FOR X=... STEP ... UNTIL ...
; Note the Return line number is stored in 1FE3 
; BURP does not support embedded FOR loops, only a single loop
; can be active at a time.
; ------------------------------------------------------------
0AAE: FE 1E        CP  $1E
0AB0: 20 2C        JR  NZ,$0ADE          ; not FOR -> try next statement type

0AB2: C1           POP BC
0AB3: C5           PUSH BC               ; peek/preserve BC (interpreter state)

0AB4: 0C           INC C                 ; C = current line number -> line after FOR
0AB5: 79           LD  A,C
0AB6: 32 E3 1F     LD  ($1FE3),A         ; save "loop body start line" for NEXT 1FE3 is the global address used for this.

0AB9: 23           INC HL
0ABA: 46           LD  B,(HL)            ; B = loop variable token/id (e.g. 'A')
0ABB: 23           INC HL

0ABC: CD 59 04     CALL $0459            ; parse/eval the "= <expr>" part
                                         ; (calls into expression parser at 04E6)
                                         ; Stores the value in the MM57109 X register.

0ABF: 78           LD  A,B
0AC0: CD 60 04     CALL $0460            ; BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)
                                         ; (very likely MM57109-side "store into var B")
                                         ; Reads the value from the MM57109 X register 

0AC3: CD 52 04     CALL $0452            ; skip ahead to next clause delimiter (space scanning)

0AC6: 3E 1B        LD  A,$1B
0AC8: CD 60 04     CALL $0460  ; BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)


0ACB: CD 46 04     CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
0ACE: DB  $30,$FF                        ; MM57109 instructions  XEY

0AD0: CD 52 04     CALL $0452            ; skip ahead again (toward UNTIL clause)

0AD3: CD 46 04     CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
0AD6: DB  $30,$3A,$30,$3C,$1C,$FF        ; likely compiles UNTIL value + compare/jump micro-sequence,  MM57109 instructions  XEY,-,XEY,/,MS

0ADC: 18 9F        JR  $0A7D             ; back to main statement dispatch loop
; ------------------------------------------------------------
; Parse token 30 - NEXT statement
; ------------------------------------------------------------
0ADE: FE 30       CP $30
0AE0: 20 2D       JR NZ,$0B0F
0AE2: CD 46 04    CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)

; Inline data for CALL $0446: bytes 0AE5-0AE6 terminated by $FF
0AE5:              DB  $1D,$FF  ; MR (M <-> X) Loop counter is held in memory register M
0AE7: 3E 13       LD A,$13    ; Load the TXF* instruction into A, Branch if X < 0 MM57109 instruction
0AE9: CD 8A 05    CALL $058A  ; MM57109_SEND_AND_WAIT_RDDY_BR(A=byte) -> A&$40, Z/NZ indicates bit6

0AEC: 28 EE       JR Z,$0ADC
0AEE: 23          INC HL
0AEF: 7E          LD A,(HL)
0AF0: F5          PUSH AF
0AF1: CD 7B 05    CALL $057B
0AF4: 3E 1B       LD A,$1B
0AF6: CD 7B 05    CALL $057B
0AF9: CD 46 04    CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)

; Inline data for CALL $0446: bytes 0AFC-0AFD terminated by $FF
0AFC:              DB  $39,$FF  ; "<39>"
0AFF: CD 60 04    CALL $0460  ; BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)

0B02: CD 46 04    CALL $0446  ; BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)

; Inline data for CALL $0446: bytes 0B05-0B08 terminated by $FF
0B05:              DB  $01,$20,$3A,$FF  ; "A :"
0B09: 3A E3 1F    LD A,($1FE3) ; Get the line to loop back to, this was saved by the FOR handler. 
                               ; It holds the next line after the FOR line was on. 
                               ; NOTE only a single FOR loop can be active at a time (no embedded loops using FOR statements)
0B0C: 4F          LD C,A
0B0D: 18 95       JR $0AA4
;
; Parse token 24
;
0B0F: FE 24       CP $24
0B11: 20 01       JR NZ,$0B14
0B13: 76          HALT
;
; Deal with anything else ???
;
0B14: 18 C6       JR $0ADC
0B16: 11 40 80    LD DE,$8040
0B19: 21 E4 1F    LD HL,$1FE4
0B1C: D5          PUSH DE
0B1D: E5          PUSH HL
0B1E: 06 02       LD B,$02
0B20: ED 5F       LD A,R
0B22: CD AB 0B    CALL $0BAB
0B25: 10 F9       DJNZ $0B20
0B27: EB          EX DE,HL
0B28: E1          POP HL
0B29: 01 04 00    LD BC,$0004
0B2C: ED B0       LDIR
0B2E: EB          EX DE,HL
0B2F: D1          POP DE
0B30: 06 02       LD B,$02
0B32: CD E7 03    CALL $03E7 — MON: CALL $03F6 ; HEXBYTE: read 2 hex digits -> A
0B35: CD AB 0B    CALL $0BAB
0B38: 10 F8       DJNZ $0B32
0B3A: E7          RST $20
0B3B: CD A0 0B    CALL $0BA0
0B3E: 1A          LD A,(DE)
0B3F: BE          CP (HL)
0B40: 20 05       JR NZ,$0B47
0B42: 2F          CPL
0B43: 12          LD (DE),A
0B44: 36 EE       LD (HL),$EE
0B46: 0C          INC C
0B47: 13          INC DE
0B48: 23          INC HL
0B49: 10 F3       DJNZ $0B3E
0B4B: 79          LD A,C
0B4C: D9          EXX
0B4D: FE 34       CP $34
0B4F: 28 46       JR Z,$0B97
0B51: 12          LD (DE),A
0B52: 13          INC DE
0B53: CD CE 03    CALL $03CE — MON: EX (SP),HL ; HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0B56-0B5F terminated by $1D
0B56:              DB  $20,$02,$0C,$01,$03,$0B,$13,$2C,$20,$1D  ; " BLACKS, "
0B60: CD A0 0B    CALL $0BA0
0B63: EB          EX DE,HL
0B64: 1A          LD A,(DE)
0B65: FE 10       CP $10
0B67: 30 0E       JR NC,$0B77
0B69: BE          CP (HL)
0B6A: 20 05       JR NZ,$0B71
0B6C: 0C          INC C
0B6D: 36 DD       LD (HL),$DD
0B6F: 2F          CPL
0B70: 12          LD (DE),A
0B71: 23          INC HL
0B72: 7D          LD A,L
0B73: FE EC       CP $EC
0B75: 20 ED       JR NZ,$0B64
0B77: 13          INC DE
0B78: 2E E8       LD L,$E8
0B7A: 10 E8       DJNZ $0B64
0B7C: 79          LD A,C
0B7D: D9          EXX
0B7E: 12          LD (DE),A
0B7F: 13          INC DE
0B80: CD CE 03    CALL $03CE — MON: EX (SP),HL ; HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0B83-0B8A terminated by $1D
0B83:              DB  $20,$17,$08,$09,$14,$05,$13,$1D  ; " WHITES"
0B8B: CD C4 03    CALL $03C4
0B8E: 21 E4 1F    LD HL,$1FE4
0B91: D5          PUSH DE
0B92: E5          PUSH HL
0B93: 2E E8       LD L,$E8
0B95: 18 90       JR $0B27
0B97: CD CE 03    CALL $03CE — MON: EX (SP),HL ; HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0B9A-0B9E terminated by $1D
0B9A:              DB  $19,$05,$13,$21,$1D  ; "YES!"
0BA0: D9          EXX
0BA1: 01 30 04    LD BC,$0430
0BA4: 11 E8 1F    LD DE,$1FE8
0BA7: 21 EC 1F    LD HL,$1FEC
0BAA: C9          RET
0BAB: E6 77       AND $77
0BAD: 77          LD (HL),A
0BAE: AF          XOR A
0BAF: ED 67       RRD
0BB1: 23          INC HL
0BB2: 77          LD (HL),A
0BB3: 23          INC HL
0BB4: C9          RET
0BB5: ED 05       ED 05
0BB7: 06 0F       LD B,$0F
0BB9: 12          LD (DE),A
0BBA: 20 01       JR NZ,$0BBD
0BBC: 3D          DEC A
0BBD: 31 20 13    LD SP,$1320
0BC0: 14          INC D
0BC1: 05          DEC B
0BC2: 10 20       DJNZ $0BE4
0BC4: 31 20 15    LD SP,$1520
0BC7: 0E 14       LD C,$14
0BC9: 09 0C 20    ADD HL,BC
0BCC: 32 35 20    LD ($2035),A
0BCF: 1F          RRA
0BD0: ED 06       ED 06
0BD2: 0C          INC C
0BD3: 05          DEC B
0BD4: 14          INC D
0BD5: 20 0C       JR NZ,$0BE3
0BD7: 3D          DEC A
0BD8: 01 20 0C    LD BC,$0C20
0BDB: 0F          RRCA
0BDC: 07          RLCA
0BDD: 20 1F       JR NZ,$0BFE
0BDF: ED 07       ED 07
0BE1: 10 12       DJNZ $0BF5
0BE3: 09 0E 14    ADD HL,BC
0BE6: 20 01       JR NZ,$0BE9
0BE8: 30 20       JR NC,$0C0A
0BEA: 0C          INC C
0BEB: 38 20       JR C,$0C0D
0BED: 1F          RRA
0BEE: ED 08       ED 08
0BF0: 0E 05       LD C,$05
0BF2: 18 14       JR $0C08
0BF4: 20 01       JR NZ,$0BF7
0BF6: 20 1F       JR NZ,$0C17
0BF8: ED 09       ED 09
0BFA: 05          DEC B
0BFB: 0E 04       LD C,$04
0BFD: 20 1F       JR NZ,$0C1E
0BFF: C0          RET NZ


; ## Trace notes: `run5_v2.trc` (executing the final SPACE in `RUN 5␠`)

; This trace begins in the monitor keyboard NMI ISR at **0x0066** (the “any key causes NMI” handler).
; The trace then returns to BURP’s command parser and, after the final space, branches into the command
; execution path.

; Key waypoints seen in the trace:

; 0x073B–0x073D: whitespace handling / end-of-token check (returns if A == 0x20).
; 0x097A…: begins scanning the program store at 0x0C00 looking for a line record matching the requested line number.
;   You can see the loop reading bytes at (HL) and checking for 0xED / 0xC0 sentinels.
; 0x0AC6–0x0AC8: loads A=0x1B and calls 0x0460 (looks like an “emit control/clear” helper used before execution).
; 0x0460: sets up IM 1 / EI briefly, calls the inline-data reader at 0x0446, then performs a block copy/format loop
;   ending at **0x04B9 RET**.

; Important observation:
; In your breakpoint capture at 0x04B9, the return address at (SP) is 0x0AC3 (bytes C3 0A at SP=0x1FDB),
;   so the `RET` at 0x04B9 should return to BURP at 0x0AC3, *not* to 0x0000.
;   If you see an immediate fall-through to 0x0000 in a trace, it likely means control later jumped/reset,
;   or the trace output was truncated/filtered right after the `RET`.

; Next targeted breakpoint:
; Break at 0x0AC3 and 0x0066 while executing RUN 5␠ to determine whether the post-RET path is:
;   (a) an intentional reset/jump, (b) an interrupt entry (NMI), or (c) a bad branch due to a ROM typo.


; ---

; ## Path map: `RUN 5␠` execution (from `run5_v2.trc`)

; This is a **trace-driven** “where the CPU goes next” map for the moment you press the **final space** in `RUN 5␠`.
; It’s not the full BURP interpreter yet, but it captures the concrete blocks we *know* are involved.

; ### 0) Keyboard interrupt entry (Monitor ROM)
; 0x0066 — NMI_KBD_ISR (monitor NMI handler)
;   - Reads the key from **port 0x01** (`IN A,(01h)`), normalises it, and returns back to the halted caller.
;   - The handler contains the well-known guard:
;     - it inspects the opcode at **(PC-1)** and compares it with **0x76 (HALT)**; if it wasn’t halted it can jump to **0x0000** (reset path).

; **Seen in trace:** `0066..0090` (key normalisation), then returns into BURP.

; ### 1) BURP command input loop (BURP ROM)
; ~0x0714–0x073A — command line editor / token collector
;   - This is the region you already observed: it repeatedly executes **HALT**, waking once per keypress.
;   - Each character advances to the next “wait” HALT (e.g. 0x0729, 0x072B, 0x072D, 0x0736, 0x073A).

; **Interpretation:** by the time you hit the final space in `RUN 5␠`, BURP has:
; recognised the command token RUN
; parsed the numeric argument 5
; and the space acts as the “commit/execute” trigger.

; ### 2) “Execute” trigger: screen/control action + dispatcher entry
; From the trace, the first concrete thing we see after commit is:

; 0x0AC6: LD A,0x1B then CALL 0x0460

; This looks like “emit a control code” (0x1B is very plausibly **ESC / clear / mode control** in the COMP-80 display subsystem),
; so it’s likely the start of “run-mode setup” (clear screen / reset print cursor / etc).

; ### 3) Display/control helper that consumes inline byte streams
; 0x0460 — run-mode display/control helper (uses inline data)
;   - Sets **IM 1**, enables interrupts briefly, and calls the inline-byte consumer:
;     - **`CALL 0x0446`** then consumes bytes immediately after the call until a terminator is seen.
;   - In the ROM listing at **0x046D** you see a literal `0xFF`. In this context it is the **terminator byte** for the inline stream.

; **Why this matters:** if the `0xFF` byte were mistyped in the ROM, the reader would continue scanning and would corrupt the return address (classic failure mode).
; Your current trace *does* show it returning through this machinery, so the inline-data path is real.

; ### 4) MM57109 handshake used as a general “write byte to math latch” primitive
; Inside this control/helper path we hit:

; 0x044D: CALL 0x042E
; 0x042E–0x0445: MM57109_SEND_INSTRUCTION_IN_A
;   - Wait for RDY bit (port 0x03 bit5) to be low
;   - `OUT (0x60),A` (bit7 clear)
;   - Wait for RDY bit to go high
;   - `OUT (0x60),A|0x80` (bit7 set)
;   - return

; This is the exact loop you previously identified at 0x0430/0x0439.

; ### 5) Bulk move / workspace setup
; The trace then shows a block around **0x0473–0x04B6** that uses `LDIR` and manipulates **DE/HL**.
; This looks like moving a template or setting up a buffer for the run-mode screen layout.

; ### 6) Return, then “reset-like” behaviour
; 0x04B9: RET

; Immediately after, the trace shows execution at:

; 0x0000: reset vector (LD SP,1FDF, LD DE,8000, CALL 03CE, ...)

; There are two plausible explanations:

; 1) The code that executes after returning (likely around **0x0AC3**) deliberately jumps into the monitor reset path (a “bail out” path).
; 2) An interrupt (NMI or maskable INT) arrives while not halted and forces the monitor’s escape-to-0x0000 behaviour.

; Your **0x04B9 breakpoint dump** is important here: it shows **SP=0x1FDB** and the word at (SP) is **0x0AC3**, not 0x0000.
; So the `RET` itself is returning to 0x0AC3. The jump to 0x0000 happens **after** that return (or during the subsequent control flow).

; ### What this map suggests to instrument next
; To turn this path map into a precise “why does RUN bail out?” explanation, the most valuable breakpoints are:

; BP 0x0AC3 (immediately after the RET at 0x04B9)
;   → tells us what the caller does next (normal continuation vs deliberate reset vs error branch)
; BP 0x0066 (NMI entry) + capture PC-1 opcode check
;   → tells us if an “escape NMI” is happening during run-mode
; BP 0x0038 (IM1 interrupt vector)
;   → tells us if the MM57109 “R/W → INT” path is being exercised/expected during RUN

; If you’d like, I can extend this section with a follow-up trace (“from 0x0AC3 onward”) and integrate it into the disassembly as a step-by-step narrative.
