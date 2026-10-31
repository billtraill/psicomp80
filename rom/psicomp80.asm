; PSI COMP80 ROM: monitor (0000-03FF) and BURP (0400-0BFF)
;
; Annotated disassembly. It assembles with z80asm to psicomp80.rom byte for
; byte (rom/build.sh checks). Each line's comment starts with the address and
; the bytes, as in the magazine's hex listing. Branch targets without a
; name are labelled L<address>.
;
; Made from the earlier annotated disassemblies (old/) by
; rom/tools/make_rom_asm.py; edit this file from now on.

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

; ---------------------------------------------------------------------------
; Monitor command dispatch (as observed in ROM)
; The monitor reads a normalised command selector in A from CALL $0355 and
; compares it against a small set of command IDs, then jumps to handlers.
; These IDs are *not* ASCII; they are compact key/command codes produced by
; the monitor's command scanner.
;
; Mappings below are inferred from the handler behaviour and monitor_cmds.md:
;   $FC : RUN  XXXX     (parse address -> JP (HL))        ()
;   $13 : ALT           (alter memory; loops until FS/RESET)
;   $0F : COR           (scan/replace AA->BB across range)
;   $FE : FIND          (search for consecutive bytes XX YY)
;   $08 : LIST          (list memory to screen)
;   $04 : PRINT         (list memory on second output device)
;   $F1 : TAPE          (write block to tape/serial on port $20)
;   $F2 : READ          (read tape into memory via port $00)
;   $07 : ALPH          (VDU alphanumeric test pattern)
;   $FD : PROM          (program $1C00-$1CFF via ports)  ()
; ---------------------------------------------------------------------------
; === v5: relabelled command dispatch + monitor commands ===

CMD_RUN_CODE:   EQU $FC
CMD_LOAD_CODE:  EQU $F8
CMD_MOV_CODE:   EQU $09
CMD_FILL_CODE:  EQU $06
CMD_PROM_CODE:  EQU $FD
CMD_ALT_CODE:   EQU $13
CMD_COR_CODE:   EQU $0F
CMD_FIND_CODE:  EQU $FE
CMD_LIST_CODE:  EQU $08
CMD_PRINT_CODE: EQU $04
CMD_TAPE_CODE:  EQU $F1
CMD_READ_CODE:  EQU $F2
CMD_ALPH_CODE:  EQU $07

        ORG     $0000

MON_START:
        LD SP,$1FDF           ; 0000  31 DF 1F
        LD DE,$8000           ; 0003  11 00 80
        CALL PRINT_INLINE     ; 0006  CD CE 03     Print inline string (see STR_PRINT_HL_AT_RETADDR)
; Inline data consumed by CALL $03CE (03CE uses EX (SP),HL to treat the return address as a string pointer,
; prints bytes until terminator $1D (GS), then returns to the byte *after* the terminator).
READY_PROMPT_STR:
        DB $20,$12,$05,$01,$04,$19,$1D   ; 0009  20 12 05 01 04 19 1D  " READY" using 5-bit letter codes (R=12h,E=05h,A=01h,D=04h,Y=19h), terminated by GS ($1D)
        CALL PAD_TO_NEXT_LINE ; 0010  CD C4 03     pad after READY prompt (advance cursor to start of next 64-col line)
        LD A,$80              ; 0013  3E 80
        OUT ($00),A           ; 0015  D3 00
; --- Main key dispatch (cold-start / command-loop entry)
; CALL $0355 returns a keycode in A (already normalised elsewhere).
; The monitor compares A against a small set of non-ASCII command keycodes
; and branches to the relevant handler.

; ---------------------------------------------------------------------------
; COMMAND_LOOP: wait for a command selector, dispatch to handlers
; ---------------------------------------------------------------------------
        CALL GET_KEY_SELECTOR ; 0017  CD 55 03     READ_COMMAND_ID -> A
; A == $FC : special command key (non-ASCII)
; A == $FC : RUN XXXX (jump to address)

        CP $FC                ; 001A  FE FC        RUN XXXX
        JR NZ,L002B           ; 001C  20 0D
        JR L0042              ; 001E  18 22
        PUSH AF               ; 0020  F5
        LD A,$20              ; 0021  3E 20
        LD (DE),A             ; 0023  12
        INC DE                ; 0024  13
        POP AF                ; 0025  F1
        RET                   ; 0026  C9
        RST $38               ; 0027  FF
        JP L01AA              ; 0028  C3 AA 01
; A == $06 : FILL XXXX (fill from XXXX to next xx00 with FF)
;

; ---------------------------------------------------------------------------
; CMD_FILL: implements FILL XXXX (fill from XXXX to next xx00 with FF)
; ---------------------------------------------------------------------------
L002B:
        CP $06                ; 002B  FE 06        FILL XXXX (fill to page with FF)
        JR NZ,L0049           ; 002D  20 1A
        CALL READ_HEX_WORD    ; 002F  CD DE 03     FILL: read start address XXXX -> HL
L0032:
        LD (HL),$FF           ; 0032  36 FF
        INC L                 ; 0034  2C
        JR NZ,L0032           ; 0035  20 FB
        RST $00               ; 0037  C7
; ---------------------------------------------------------------------------
; Interrupt handler for the MM57109 stores values in the address pointed to
; via the HL register, which should have been setup prior to interrups being
; enabled.
; ---------------------------------------------------------------------------
        PUSH AF               ; 0038  F5
        IN A,($03)            ; 0039  DB 03
        AND $0F               ; 003B  E6 0F
        LD (HL),A             ; 003D  77
        INC HL                ; 003E  23
        POP AF                ; 003F  F1
        EI                    ; 0040  FB
        RET                   ; 0041  C9
L0042:
        CALL CLEAR_SCREEN     ; 0042  CD 93 03     clear screen/work area before showing READY / accepting command
        CALL READ_HEX_WORD    ; 0045  CD DE 03     RUN: read target address XXXX -> HL (then JP (HL))
        JP (HL)               ; 0048  E9
; A == $09 : MOV XXXXYYYYZZZZ (block move)
;

; ---------------------------------------------------------------------------
; CMD_MOV: implements MOV XXXX YYYY ZZZZ (LDIR block move)
; ---------------------------------------------------------------------------
L0049:
        CP $09                ; 0049  FE 09        MOV XXXX YYYY ZZZZ (block move)
        JR NZ,L0095           ; 004B  20 48
        CALL READ_HEX_WORD    ; 004D  CD DE 03     MOV: read source address XXXX -> HL
        PUSH HL               ; 0050  E5
        RST $20               ; 0051  E7
        CALL READ_HEX_WORD    ; 0052  CD DE 03     MOV: read destination address YYYY -> HL
        POP BC                ; 0055  C1
        PUSH BC               ; 0056  C5
        AND A                 ; 0057  A7
        SBC HL,BC             ; 0058  ED 42
        PUSH HL               ; 005A  E5
        POP BC                ; 005B  C1
        RST $20               ; 005C  E7
        CALL READ_HEX_WORD    ; 005D  CD DE 03     MOV: read length/limit ZZZZ -> HL (see handler logic)
        POP DE                ; 0060  D1
        EX DE,HL              ; 0061  EB
        LDIR                  ; 0062  ED B0
L0064:
        RST $00               ; 0064  C7
        RST $38               ; 0065  FF
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
        EX (SP),HL            ; 0066  E3           HL := return address (PC) from NMI entry
        DEC HL                ; 0067  2B           point at opcode that was interrupted
        LD A,(HL)             ; 0068  7E           fetch interrupted opcode
        CP $76                ; 0069  FE 76        was it HALT?
        JR NZ,MON_START       ; 006B  20 93        no: unexpected NMI -> reset monitor
        INC HL                ; 006D  23           yes: restore return address
        EX (SP),HL            ; 006E  E3           put return address back on stack
KBD_READ_PORT01:
        IN A,($01)            ; 006F  DB 01        read raw keycode from keyboard latch (port $01)
        CPL                   ; 0071  2F           invert active-low keycode
        CP $0D                ; 0072  FE 0D        CR/ENTER from keyboard?
        JR NZ,L0078           ; 0074  20 02
        LD A,$1F              ; 0076  3E 1F        remap CR -> US (0x1F) as end-of-line marker
L0078:
        CP $40                ; 0078  FE 40
        JR C,L007E            ; 007A  38 02
        AND $1F               ; 007C  E6 1F        fold 0x40+ range to 5-bit (letters: A=1..Z=26)
L007E:
        CP $1C                ; 007E  FE 1C        FS (0x1C) - escape/return to command state
        JR Z,L0064            ; 0080  28 E2
L0082:
        CP $1E                ; 0082  FE 1E
BURP_ENTRY_JP:
        JP Z,BURP_ENTRY       ; 0084  CA 00 08     jump into BURP (0x0800)
        CP $1F                ; 0087  FE 1F
        JR NZ,L0090           ; 0089  20 05
        CALL PAD_TO_NEXT_LINE ; 008B  CD C4 03     end-of-line handling: advance cursor to next 64-col line
        RETN                  ; 008E  ED 45
L0090:
        LD (DE),A             ; 0090  12
        INC DE                ; 0091  13
        RETN                  ; 0092  ED 45
        RST $38               ; 0094  FF
; A == $F8 : special command key (non-ASCII).
; Enters the large block-handling routine that reads/writes the $8000 display RAM region.
; A == $F8 : LOAD XXXX (hex loader; '[' enters ASCII mode, ']' exits, '@' ends + lists)

; ---------------------------------------------------------------------------
; CMD_LOAD: implements LOAD XXXX (hex loader with '['..']' ASCII mode)
; '[' key normalises to 0x1B, ']' normalises to 0x1D (GS) (see KBD_READ_PORT01).
; ---------------------------------------------------------------------------
L0095:
        CP $F8                ; 0095  FE F8        LOAD XXXX (hex/ASCII loader)
        JR NZ,L00F3           ; 0097  20 5A
        CALL CLEAR_SCREEN     ; 0099  CD 93 03     clear screen/work area before processing new command sequence
        CALL READ_HEX_WORD    ; 009C  CD DE 03     LOAD: read load start address XXXX -> HL
        LD DE,$8040           ; 009F  11 40 80
        PUSH HL               ; 00A2  E5
L00A3:
        CALL PRINT_HEX_WORD_HL; 00A3  CD 9F 03     print HL as 4 hex digits + space
        CALL L0383            ; 00A6  CD 83 03
L00A9:
        HALT                  ; 00A9  76
        CP $00                ; 00AA  FE 00
        JR Z,L00D0            ; 00AC  28 22
        CP $1B                ; 00AE  FE 1B
        JR NZ,L00C3           ; 00B0  20 11
        CALL PAD_TO_NEXT_LINE ; 00B2  CD C4 03     align cursor to start of next line before continuing output
L00B5:
        CALL L00D5            ; 00B5  CD D5 00
        LD (HL),A             ; 00B8  77
        INC HL                ; 00B9  23
        CP $1D                ; 00BA  FE 1D        GS (0x1D) terminator/delimiter in this input loop
        JR NZ,L00B5           ; 00BC  20 F7
        CALL PAD_TO_NEXT_LINE ; 00BE  CD C4 03     align cursor to start of next line (clear/rest position)
        JR L00A3              ; 00C1  18 E0
L00C3:
        CALL L03F7            ; 00C3  CD F7 03
        CALL L03EA            ; 00C6  CD EA 03
        LD (HL),A             ; 00C9  77
        INC HL                ; 00CA  23
        CALL LIST_ADVANCE_AND_MAYBE_NEWLINE; 00CB  CD 72 03     LIST/PRINT formatting: advance column (spaces/grouping); if end-of-line start next line + print address
        JR L00A9              ; 00CE  18 D9
L00D0:
        POP HL                ; 00D0  E1
        CALL L0320            ; 00D1  CD 20 03
        RST $00               ; 00D4  C7
L00D5:
        HALT                  ; 00D5  76
L00D6:
        CP $1B                ; 00D6  FE 1B
        RET NZ                ; 00D8  C0
        DEC DE                ; 00D9  1B
L00DA:
        HALT                  ; 00DA  76
        DEC DE                ; 00DB  1B
        CP $1D                ; 00DC  FE 1D
        JR Z,L00D5            ; 00DE  28 F5
        CP $2F                ; 00E0  FE 2F
        JR Z,L00EC            ; 00E2  28 08
        ADD A,$40             ; 00E4  C6 40
        LD (DE),A             ; 00E6  12
        INC DE                ; 00E7  13
        LD (HL),A             ; 00E8  77
        INC HL                ; 00E9  23
        INC DE                ; 00EA  13
        INC HL                ; 00EB  23
L00EC:
        DEC HL                ; 00EC  2B
        DEC DE                ; 00ED  1B
        LD A,$1F              ; 00EE  3E 1F
        LD (DE),A             ; 00F0  12
        JR L00DA              ; 00F1  18 E7
; A == $FD : special command key (non-ASCII).
; This routine streams bytes from $1C00..$1CFF to output port $40/$80 (EPROM programmer interface).
; Strong candidate for PROM / TAPE / external device command.

; ---------------------------------------------------------------------------
; CMD_PROM: implements PROM (program 0x1C00-0x1CFF via EPROM programmer ports)
; ---------------------------------------------------------------------------
L00F3:
        CP $FD                ; 00F3  FE FD        PROM (EPROM programmer)
        JR NZ,L011C           ; 00F5  20 25
        LD E,$80              ; 00F7  1E 80
L00F9:
        LD HL,$1C00           ; 00F9  21 00 1C
        LD D,$00              ; 00FC  16 00
L00FE:
        LD B,$08              ; 00FE  06 08
        LD A,(HL)             ; 0100  7E
L0101:
        OUT ($40),A           ; 0101  D3 40
        RLCA                  ; 0103  07
        DJNZ L0101            ; 0104  10 FB
        LD B,$08              ; 0106  06 08
        LD A,D                ; 0108  7A
L0109:
        OUT ($40),A           ; 0109  D3 40
        RLCA                  ; 010B  07
        DJNZ L0109            ; 010C  10 FB
        OUT ($80),A           ; 010E  D3 80
        CALL INLINE_DELAY_1B  ; 0110  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $0F                           ; 0113  0F  delay count for INLINE_DELAY_1B
        INC HL                ; 0114  23
        INC D                 ; 0115  14
        JR NZ,L00FE           ; 0116  20 E6
        DEC E                 ; 0118  1D
        JR NZ,L00F9           ; 0119  20 DE
        RST $00               ; 011B  C7
; A == $13 : ALT XXXXYY (alter memory; repeats until FS/RESET)
;

L011C:
        CP $13                ; 011C  FE 13        ALT XXXXYY (alter memory; repeats until FS/RESET)
        JR NZ,L013A           ; 011E  20 1A
L0120:
        CALL READ_HEX_WORD    ; 0120  CD DE 03     ALT: read address XXXX -> HL
        RST $20               ; 0123  E7
        CALL READ_HEX_BYTE    ; 0124  CD E7 03     HEXBYTE: read 2 hex digits -> A
        LD (HL),A             ; 0127  77
        CALL L031D            ; 0128  CD 1D 03
        CALL L0345            ; 012B  CD 45 03
        JR L0120              ; 012E  18 F0
        RST $38               ; 0130  FF
        RST $38               ; 0131  FF
        RST $38               ; 0132  FF
        RST $38               ; 0133  FF
        RST $38               ; 0134  FF
        RST $38               ; 0135  FF
        RST $38               ; 0136  FF
        RST $38               ; 0137  FF
        RST $38               ; 0138  FF
        RST $38               ; 0139  FF
; A == $07 : ALPH (VDU alphanumeric test pattern on screen)
;

L013A:
        CP $07                ; 013A  FE 07        ALPH (VDU alphanumeric test pattern)
        JR NZ,L0149           ; 013C  20 0B
        LD HL,$8000           ; 013E  21 00 80
L0141:
        LD (HL),L             ; 0141  75
        INC HL                ; 0142  23
        LD A,H                ; 0143  7C
        CP $88                ; 0144  FE 88
        JR NZ,L0141           ; 0146  20 F9
        RST $00               ; 0148  C7
; A == $04 : control keycode (EOT). Treated as a command trigger.
; Likely a text-command path (hex parsing, listing, etc) begins shortly after.

L0149:
        CP $04                ; 0149  FE 04        PRINT XXXX (list from XXXX on second output device)
        JR NZ,L016B           ; 014B  20 1E
        CALL READ_HEX_WORD    ; 014D  CD DE 03     PRINT: read start address XXXX -> HL
L0150:
        CALL TTY_NEWLINE_HL   ; 0150  CD 7F 02
L0153:
        LD A,(HL)             ; 0153  7E
        CALL TTY_HEX_BYTE     ; 0154  CD 8E 02
        INC HL                ; 0157  23
        CALL TTY_SPACE        ; 0158  CD EC 02
        LD A,L                ; 015B  7D
        AND $03               ; 015C  E6 03
        CALL Z,TTY_SPACE      ; 015E  CC EC 02
        CALL Z,TTY_SPACE      ; 0161  CC EC 02
        LD A,L                ; 0164  7D
        AND $0F               ; 0165  E6 0F
        JR Z,L0150            ; 0167  28 E7
        JR L0153              ; 0169  18 E8
; A == $0F : COR XXXXYYYYAABB (scan range and replace AA->BB; prints address when it changes)
; This path looks like a compare/scan/patch loop (could match COR/FIND).

L016B:
        CP $0F                ; 016B  FE 0F        COR XXXXYYYYAABB
        JR NZ,L01C9           ; 016D  20 5A
        CALL READ_HEX_WORD    ; 016F  CD DE 03     COR: read start address XXXX -> HL
        RST $20               ; 0172  E7
        PUSH HL               ; 0173  E5
        CALL READ_HEX_WORD    ; 0174  CD DE 03     COR: read end address YYYY -> HL
        RST $20               ; 0177  E7
        CALL READ_HEX_BYTE    ; 0178  CD E7 03     HEXBYTE: read 2 hex digits -> A
        LD B,A                ; 017B  47
        RST $20               ; 017C  E7
        CALL READ_HEX_BYTE    ; 017D  CD E7 03     HEXBYTE: read 2 hex digits -> A
        LD C,A                ; 0180  4F
        EX (SP),HL            ; 0181  E3
        CALL CLEAR_SCREEN     ; 0182  CD 93 03     clear screen/work area before (re)printing prompt/status line
        LD DE,$8040           ; 0185  11 40 80
L0188:
        LD A,(HL)             ; 0188  7E
        CP B                  ; 0189  B8
        JR NZ,L0190           ; 018A  20 04
        LD (HL),C             ; 018C  71
        CALL PRINT_HEX_WORD_HL; 018D  CD 9F 03     print HL as 4 hex digits + space
L0190:
        CALL DE_TO_NEXT_8     ; 0190  CD 4E 03
        INC HL                ; 0193  23
        EX DE,HL              ; 0194  EB
        EX (SP),HL            ; 0195  E3
        LD A,D                ; 0196  7A
        CP H                  ; 0197  BC
        JR NZ,L01A0           ; 0198  20 06
        LD A,E                ; 019A  7B
        CP L                  ; 019B  BD
        JR NZ,L01A0           ; 019C  20 02
        POP HL                ; 019E  E1
        RST $00               ; 019F  C7
L01A0:
        EX (SP),HL            ; 01A0  E3
        EX DE,HL              ; 01A1  EB
        JR L0188              ; 01A2  18 E4
L01A4:
        CP $08                ; 01A4  FE 08        LIST XXXX (list memory to screen)
        CALL Z,CMD_LIST       ; 01A6  CC 17 03     CMD_LIST handler (prints a full VDU screen)
        RST $00               ; 01A9  C7
L01AA:
        PUSH AF               ; 01AA  F5
        PUSH BC               ; 01AB  C5
        PUSH DE               ; 01AC  D5
        LD DE,$8600           ; 01AD  11 00 86
        CALL PRINT_HEX_WORD_HL; 01B0  CD 9F 03     print HL as 4 hex digits + space
        POP HL                ; 01B3  E1
        CALL PRINT_HEX_WORD_HL; 01B4  CD 9F 03     print HL as 4 hex digits + space
        POP HL                ; 01B7  E1
        CALL PRINT_HEX_WORD_HL; 01B8  CD 9F 03     print HL as 4 hex digits + space
        POP HL                ; 01BB  E1
        CALL PRINT_HEX_WORD_HL; 01BC  CD 9F 03     print HL as 4 hex digits + space
        POP HL                ; 01BF  E1
        NOP                   ; 01C0  00
        CALL PRINT_HEX_WORD_HL; 01C1  CD 9F 03     print HL as 4 hex digits + space
        POP HL                ; 01C4  E1
        CALL PRINT_HEX_WORD_HL; 01C5  CD 9F 03     print HL as 4 hex digits + space
        RST $00               ; 01C8  C7
L01C9:
        CP $FE                ; 01C9  FE FE        FIND XX YY (search consecutive bytes; lists addresses)
        JR NZ,L01FF           ; 01CB  20 32
        CALL CLEAR_SCREEN     ; 01CD  CD 93 03     clear screen/work area before listing/search output
        CALL READ_HEX_BYTE    ; 01D0  CD E7 03     HEXBYTE: read 2 hex digits -> A
        EX AF,AF'             ; 01D3  08
        RST $20               ; 01D4  E7
        CALL READ_HEX_BYTE    ; 01D5  CD E7 03     HEXBYTE: read 2 hex digits -> A
        LD HL,$0000           ; 01D8  21 00 00
        LD BC,$2000           ; 01DB  01 00 20
        LD DE,$8040           ; 01DE  11 40 80
L01E1:
        EX AF,AF'             ; 01E1  08
        CPIR                  ; 01E2  ED B1
        JP PO,MON_START       ; 01E4  E2 00 00
        EX AF,AF'             ; 01E7  08
        CPI                   ; 01E8  ED A1
        JR NZ,L01E1           ; 01EA  20 F5
        PUSH AF               ; 01EC  F5
        DEC HL                ; 01ED  2B
        DEC HL                ; 01EE  2B
        CALL PRINT_HEX_WORD_HL; 01EF  CD 9F 03     print HL as 4 hex digits + space
        CALL DE_TO_NEXT_8     ; 01F2  CD 4E 03
        INC HL                ; 01F5  23
        LD A,D                ; 01F6  7A
        CP $88                ; 01F7  FE 88
        JR NZ,L01FC           ; 01F9  20 01
        RST $00               ; 01FB  C7
L01FC:
        POP AF                ; 01FC  F1
        JR L01E1              ; 01FD  18 E2
L01FF:
        CP $F1                ; 01FF  FE F1        TAPE XXXXYYYY (write block to tape/serial on port $20)
        JR NZ,L0221           ; 0201  20 1E
        CALL READ_HEX_WORD    ; 0203  CD DE 03     TAPE: read start address XXXX -> HL
        RST $20               ; 0206  E7
        PUSH HL               ; 0207  E5
        CALL READ_HEX_WORD    ; 0208  CD DE 03     TAPE: read end address YYYY -> HL
        CALL TAPE_LEADER      ; 020B  CD 54 02
        EX (SP),HL            ; 020E  E3
        POP BC                ; 020F  C1
L0210:
        LD A,(HL)             ; 0210  7E
        CALL L0260            ; 0211  CD 60 02     Transmits the byte in register A to the tape interface
        INC HL                ; 0214  23
        LD A,H                ; 0215  7C
        CP B                  ; 0216  B8
        JR NZ,L0210           ; 0217  20 F7
        LD A,L                ; 0219  7D
        CP C                  ; 021A  B9
        JR NZ,L0210           ; 021B  20 F3
        CALL TAPE_LEADER      ; 021D  CD 54 02
        RST $00               ; 0220  C7
L0221:
        CP $F2                ; 0221  FE F2        READ XXXX (read tape into memory starting at XXXX; terminates on key)
        JP NZ,L01A4           ; 0223  C2 A4 01
;
; READ XXXX (read tape into memory starting at XXXX; terminates on key)
;
        CALL READ_HEX_WORD    ; 0226  CD DE 03     READ: read start address XXXX -> HL
L0229:
        LD C,$00              ; 0229  0E 00
L022B:
        IN A,($00)            ; 022B  DB 00        Read tape interface
        AND $01               ; 022D  E6 01
        JR NZ,L022B           ; 022F  20 FA
        CALL INLINE_DELAY_1B  ; 0231  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $02                           ; 0234  02  delay count for INLINE_DELAY_1B
        IN A,($00)            ; 0235  DB 00
        AND $01               ; 0237  E6 01
        JR NZ,L022B           ; 0239  20 F0
        CALL INLINE_DELAY_1B  ; 023B  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $4C                           ; 023E  4C  delay count for INLINE_DELAY_1B
        LD B,$08              ; 023F  06 08
L0241:
        IN A,($00)            ; 0241  DB 00
        AND $01               ; 0243  E6 01
        ADD A,C               ; 0245  81
        RLCA                  ; 0246  07
        LD C,A                ; 0247  4F
        CALL INLINE_DELAY_1B  ; 0248  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $35                           ; 024B  35  delay count for INLINE_DELAY_1B
        DJNZ L0241            ; 024C  10 F3
        LD A,C                ; 024E  79
        RRCA                  ; 024F  0F
        LD (HL),A             ; 0250  77
        INC HL                ; 0251  23
        JR L0229              ; 0252  18 D5
;
; Sets the tape interface to 2400Hz and then calls 255 long time delays - about 4 seconds
;
TAPE_LEADER:
        LD A,$FF              ; 0254  3E FF
        LD B,A                ; 0256  47
        OUT ($20),A           ; 0257  D3 20
L0259:
        CALL INLINE_DELAY_1B  ; 0259  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $FF                           ; 025C  FF  delay count for INLINE_DELAY_1B
        DJNZ L0259            ; 025D  10 FA
        RET                   ; 025F  C9
;
; Transmits the byte in register A to the tape interface preceded by a start bit and followed by 2 stop bits
;
L0260:
        PUSH BC               ; 0260  C5
        PUSH AF               ; 0261  F5
        XOR A                 ; 0262  AF
        OUT ($20),A           ; 0263  D3 20
        CALL INLINE_DELAY_1B  ; 0265  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $35                           ; 0268  35  delay count for INLINE_DELAY_1B
        POP AF                ; 0269  F1
        LD B,$08              ; 026A  06 08
L026C:
        OUT ($20),A           ; 026C  D3 20
        RLCA                  ; 026E  07
        CALL INLINE_DELAY_1B  ; 026F  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $35                           ; 0272  35  delay count for INLINE_DELAY_1B
        DJNZ L026C            ; 0273  10 F7
        LD A,$FF              ; 0275  3E FF
        OUT ($20),A           ; 0277  D3 20
        CALL INLINE_DELAY_1B  ; 0279  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $4C                           ; 027C  4C  delay count for INLINE_DELAY_1B
        POP BC                ; 027D  C1
        RET                   ; 027E  C9
;
; Calls a new line and then prints the contents of HL on the teleprinter
;
TTY_NEWLINE_HL:
        CALL TTY_NEWLINE      ; 027F  CD F0 02     Prints new line on teleprinter
        LD A,H                ; 0282  7C
        CALL TTY_HEX_BYTE     ; 0283  CD 8E 02
        LD A,L                ; 0286  7D
        CALL TTY_HEX_BYTE     ; 0287  CD 8E 02
        CALL TTY_SPACE        ; 028A  CD EC 02
        RET                   ; 028D  C9
;
; Formats the hex byte in register A for printing as two characters on the teleprinter
;
TTY_HEX_BYTE:
        PUSH BC               ; 028E  C5
        LD C,A                ; 028F  4F
        AND $F0               ; 0290  E6 F0
        RRCA                  ; 0292  0F
        RRCA                  ; 0293  0F
        RRCA                  ; 0294  0F
        RRCA                  ; 0295  0F
        CALL L029D            ; 0296  CD 9D 02
        LD A,C                ; 0299  79
        AND $0F               ; 029A  E6 0F
        POP BC                ; 029C  C1
L029D:
        ADD A,$30             ; 029D  C6 30
        CP $3A                ; 029F  FE 3A
        JR C,L02A5            ; 02A1  38 02
        SUB $39               ; 02A3  D6 39
L02A5:
        CP $1B                ; 02A5  FE 1B
        JR NC,L02B7           ; 02A7  30 0E
        EX AF,AF'             ; 02A9  08
        CP $1F                ; 02AA  FE 1F
        JR Z,L02B3            ; 02AC  28 05
        LD A,$1F              ; 02AE  3E 1F
        CALL TTY_PUTC         ; 02B0  CD 01 03
L02B3:
        EX AF,AF'             ; 02B3  08
L02B4:
        JP TTY_PUTC           ; 02B4  C3 01 03
L02B7:
        EX AF,AF'             ; 02B7  08
        CP $1B                ; 02B8  FE 1B
        JR Z,L02C1            ; 02BA  28 05
        LD A,$1B              ; 02BC  3E 1B
        CALL TTY_PUTC         ; 02BE  CD 01 03
L02C1:
        EX AF,AF'             ; 02C1  08
        PUSH HL               ; 02C2  E5
        ADD A,$AC             ; 02C3  C6 AC
        LD L,A                ; 02C5  6F
        LD H,$02              ; 02C6  26 02
        LD A,(HL)             ; 02C8  7E
        POP HL                ; 02C9  E1
        JR L02B4              ; 02CA  18 E8
        INC E                 ; 02CC  1C
        INC E                 ; 02CD  1C
        ADD HL,BC             ; 02CE  09
        JR $02D6              ; 02CF  18 05
        RRCA                  ; 02D1  0F
        DEC BC                ; 02D2  0B
        ADD HL,BC             ; 02D3  09
        LD DE,$0312           ; 02D4  11 12 03
        DEC BC                ; 02D7  0B
        LD A,(BC)             ; 02D8  0A
        DEC C                 ; 02D9  0D
        LD C,$17              ; 02DA  0E 17
        DJNZ L02DF            ; 02DC  10 01
        LD (BC),A             ; 02DE  02
L02DF:
        INC DE                ; 02DF  13
        INC B                 ; 02E0  04
        DEC D                 ; 02E1  15
        LD D,$07              ; 02E2  16 07
        EX AF,AF'             ; 02E4  08
        ADD HL,DE             ; 02E5  19
        INC C                 ; 02E6  0C
        INC E                 ; 02E7  1C
        LD DE,$1206           ; 02E8  11 06 12
        INC D                 ; 02EB  14
;
; Prints a space on the teleprinter
;
TTY_SPACE:
        LD A,$1C              ; 02EC  3E 1C
        JR TTY_PUTC           ; 02EE  18 11
;
; Calls a new line on the teleprinter
;
TTY_NEWLINE:
        LD A,$1D              ; 02F0  3E 1D
        CALL TTY_PUTC         ; 02F2  CD 01 03
        LD A,$1E              ; 02F5  3E 1E
        CALL TTY_PUTC         ; 02F7  CD 01 03
        LD A,$1B              ; 02FA  3E 1B
        CALL TTY_PUTC         ; 02FC  CD 01 03
        EX AF,AF'             ; 02FF  08
        RET                   ; 0300  C9
;
; Prints the contents of register A on the teleprinter
;
TTY_PUTC:
        PUSH AF               ; 0301  F5
        PUSH BC               ; 0302  C5
        AND $1F               ; 0303  E6 1F
        RLCA                  ; 0305  07
        RLCA                  ; 0306  07
        ADD A,$03             ; 0307  C6 03
        LD B,$08              ; 0309  06 08
L030B:
        OUT ($00),A           ; 030B  D3 00
        RLCA                  ; 030D  07
        CALL INLINE_DELAY_1B  ; 030E  CD 36 03     INLINE_DELAY_1B: 1-byte delay parameter follows
        DB $CE                           ; 0311  CE  delay count for INLINE_DELAY_1B
        DJNZ L030B            ; 0312  10 F7
        POP BC                ; 0314  C1
        POP AF                ; 0315  F1
        RET                   ; 0316  C9
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
CMD_LIST:
        CALL READ_HEX_WORD    ; 0317  CD DE 03     LIST: read start address XXXX -> HL
        LD ($1FF0),HL         ; 031A  22 F0 1F
L031D:
        LD HL,($1FF0)         ; 031D  2A F0 1F
L0320:
        LD DE,$8040           ; 0320  11 40 80
        CALL PRINT_HEX_WORD_HL; 0323  CD 9F 03     print HL as 4 hex digits + space
        CALL L0383            ; 0326  CD 83 03
L0329:
        CALL PRINT_HEX_BYTE_HL; 0329  CD A9 03
        INC HL                ; 032C  23
        CALL LIST_ADVANCE_AND_MAYBE_NEWLINE; 032D  CD 72 03     LIST/PRINT formatting: advance column (spaces/grouping); if end-of-line start next line + print address
        LD A,D                ; 0330  7A
        CP $88                ; 0331  FE 88
        JR NZ,L0329           ; 0333  20 F4
        RET                   ; 0335  C9
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
        EX (SP),HL            ; 0336  E3           HL = return address (points to inline delay count byte)
        PUSH BC               ; 0337  C5           preserve BC
        LD B,(HL)             ; 0338  46           B = inline delay count
L0339:
        EX (SP),HL            ; 0339  E3           waste cycles (part of delay loop)
        EX (SP),HL            ; 033A  E3           waste cycles
        EX (SP),HL            ; 033B  E3           waste cycles
        EX (SP),HL            ; 033C  E3           waste cycles
        EX (SP),HL            ; 033D  E3           waste cycles
        EX (SP),HL            ; 033E  E3           waste cycles
        DJNZ L0339            ; 033F  10 F8        loop B times
        POP BC                ; 0341  C1           restore BC
        INC HL                ; 0342  23           HL -> byte after inline parameter
        EX (SP),HL            ; 0343  E3           update return address on stack to skip parameter
        RET                   ; 0344  C9
;
; Clears the top line and sets DE to 8008
;
L0345:
        LD DE,$8008           ; 0345  11 08 80
        PUSH DE               ; 0348  D5
        CALL PAD_TO_NEXT_LINE ; 0349  CD C4 03     align output cursor (start-of-line) before status/echo output
        POP DE                ; 034C  D1
        RET                   ; 034D  C9
;
; Used to format results as in FIND and COR this rounds DE up to the next multiple of 8
;
DE_TO_NEXT_8:
        LD A,E                ; 034E  7B
        AND $07               ; 034F  E6 07
        RET Z                 ; 0351  C8
        RST $20               ; 0352  E7
        JR DE_TO_NEXT_8       ; 0353  18 F9
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

GET_KEY_SELECTOR:
        PUSH BC               ; 0355  C5
        HALT                  ; 0356  76
        AND $1F               ; 0357  E6 1F
        LD B,A                ; 0359  47
        LD DE,$8001           ; 035A  11 01 80
        CALL PAD_TO_NEXT_LINE ; 035D  CD C4 03     align output cursor before writing prompt/status area
        LD E,$10              ; 0360  1E 10
        LD A,B                ; 0362  78
        LD (DE),A             ; 0363  12
        INC DE                ; 0364  13
        HALT                  ; 0365  76
L0366:
        AND $1F               ; 0366  E6 1F
        LD C,A                ; 0368  4F
        HALT                  ; 0369  76
        CP $20                ; 036A  FE 20
        JR NZ,L0366           ; 036C  20 F8
        LD A,C                ; 036E  79
        SUB B                 ; 036F  90
        POP BC                ; 0370  C1
        RET                   ; 0371  C9
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
        RST $20               ; 0372  E7
        LD A,L                ; 0373  7D
        AND $03               ; 0374  E6 03
        JR NZ,L037A           ; 0376  20 02
        RST $20               ; 0378  E7
        RST $20               ; 0379  E7
L037A:
        LD A,L                ; 037A  7D
        AND $0F               ; 037B  E6 0F
        RET NZ                ; 037D  C0
        CALL PAD_TO_NEXT_LINE ; 037E  CD C4 03     align output cursor to line boundary before returning to main loop
        JR PRINT_HEX_WORD_HL  ; 0381  18 1C        start new line: print next address
L0383:
        LD A,L                ; 0383  7D
        AND $0F               ; 0384  E6 0F
        RET Z                 ; 0386  C8
        LD C,A                ; 0387  4F
        AND $0C               ; 0388  E6 0C
        RRCA                  ; 038A  0F
        ADD A,C               ; 038B  81
        ADD A,C               ; 038C  81
        ADD A,C               ; 038D  81
        LD B,A                ; 038E  47
L038F:
        RST $20               ; 038F  E7
        DJNZ L038F            ; 0390  10 FD
        RET                   ; 0392  C9
; ---------------------------------------------------------------------------
; CLEAR_SCREEN_8040_87FF
;
; Clears the monitor's display/work area by filling 0x8040..0x87FF with SPACE
; (0x20).  Uses RST 20h which writes a space to (DE) and increments DE.
;
; On entry : DE preserved
; On exit  : 0x8040..0x87FF = 0x20, DE preserved
; ---------------------------------------------------------------------------
CLEAR_SCREEN:
        PUSH DE               ; 0393  D5
        LD DE,$8040           ; 0394  11 40 80
L0397:
        RST $20               ; 0397  E7
        LD A,D                ; 0398  7A
        CP $88                ; 0399  FE 88
        JR NZ,L0397           ; 039B  20 FA
        POP DE                ; 039D  D1
        RET                   ; 039E  C9
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
        LD A,H                ; 039F  7C
        CALL PRINT_HEX_BYTE   ; 03A0  CD AA 03
        LD A,L                ; 03A3  7D
        CALL PRINT_HEX_BYTE   ; 03A4  CD AA 03
        RST $20               ; 03A7  E7
        RET                   ; 03A8  C9
; --- Hex output helpers -----------------------------------------------------
; $03A9: PRINT_HEX_BYTE_FROM_HL
;   Loads A=(HL) and falls through into $03AA to emit two hex chars to (DE).
;   Used by the LIST/memory-dump code above.
; $03AA: PRINT_HEX_BYTE (A)  ; emits high nibble then low nibble
; $03B9: NIBBLE_TO_ASCII     ; converts 0..15 into '0'..'9','A'..'F'
; ---------------------------------------------------------------------------
PRINT_HEX_BYTE_HL:
        LD A,(HL)             ; 03A9  7E
PRINT_HEX_BYTE:
        PUSH BC               ; 03AA  C5
        LD B,A                ; 03AB  47
        AND $F0               ; 03AC  E6 F0
        RLCA                  ; 03AE  07
        RLCA                  ; 03AF  07
        RLCA                  ; 03B0  07
        RLCA                  ; 03B1  07
        CALL L03B9            ; 03B2  CD B9 03
        LD A,B                ; 03B5  78
        AND $0F               ; 03B6  E6 0F
        POP BC                ; 03B8  C1
L03B9:
        CP $0A                ; 03B9  FE 0A
        JR C,L03BF            ; 03BB  38 02
        SUB $39               ; 03BD  D6 39
L03BF:
        ADD A,$30             ; 03BF  C6 30
        LD (DE),A             ; 03C1  12
        INC DE                ; 03C2  13
        RET                   ; 03C3  C9
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
PAD_TO_NEXT_LINE:
        EX (SP),HL            ; 03C4  E3           preserve caller HL via return-address swap (shared epilogue pattern)
        PUSH AF               ; 03C5  F5           save AF (A used for column check / clobbered by output)
L03C6:
        LD A,E                ; 03C6  7B           A = current column (low byte of cursor)
        AND $3F               ; 03C7  E6 3F        mask to 0..63 (column within 64-char row)
        JR Z,L03DB            ; 03C9  28 10        if already at col 0, exit via epilogue at 03DB
        RST $20               ; 03CB  E7           output SPACE at (DE), increment DE (see RST 20h)
        JR L03C6              ; 03CC  18 F8        loop until aligned
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
PRINT_INLINE:
        EX (SP),HL            ; 03CE  E3           HL <- return address (string ptr), [SP] <- old HL
        PUSH AF               ; 03CF  F5           preserve A across printing
L03D0:
        LD A,(HL)             ; 03D0  7E           fetch next byte of inline string
        INC HL                ; 03D1  23           advance pointer
        CP $1D                ; 03D2  FE 1D        terminator? (GS = 1Dh)
        JR Z,L03DB            ; 03D4  28 05        yes -> finish (return address now points past terminator)
        CALL L0082            ; 03D6  CD 82 00     output this character
        JR L03D0              ; 03D9  18 F5        loop for next byte
L03DB:
        POP AF                ; 03DB  F1           restore A
        EX (SP),HL            ; 03DC  E3           put updated HL back as return address; restore original HL
        RET                   ; 03DD  C9           returns to byte after terminator in caller stream
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
READ_HEX_WORD:
        CALL READ_HEX_BYTE    ; 03DE  CD E7 03     Read 16-bit hex word (4 digits) into HL  (HEXBYTE: read 2 hex digits -> A)
        LD H,A                ; 03E1  67
        CALL READ_HEX_BYTE    ; 03E2  CD E7 03     HEXBYTE: read 2 hex digits -> A
        LD L,A                ; 03E5  6F
        RET                   ; 03E6  C9
; -----------------------------------------------------------------------------
; 03E7  HEXBYTE_FROM_KEYPAD
;
; Reads a single byte expressed as two hexadecimal digits from the keyboard.
; Returns:
;   A = byte value (00h..FFh)
; Notes:
;   - Uses HALT+NMI keyboard delivery (see GET_KEY_SELECTOR / NMI handler).
;   - Calls HEXDIGIT (03F6) twice to obtain two nibbles (0..15),
;     shifts the first nibble left by 4, then adds the second.
;   - Used by HEXWORD (03DE) and by commands that accept 8-bit parameters.
; -----------------------------------------------------------------------------
READ_HEX_BYTE:
        CALL READ_HEX_DIGIT   ; 03E7  CD F6 03     HEXBYTE: read 2 hex digits -> A
L03EA:
        PUSH BC               ; 03EA  C5
        RLCA                  ; 03EB  07
        RLCA                  ; 03EC  07
        RLCA                  ; 03ED  07
        RLCA                  ; 03EE  07
        LD B,A                ; 03EF  47
        CALL READ_HEX_DIGIT   ; 03F0  CD F6 03
        ADD A,B               ; 03F3  80           combine low nibble with (high_nibble<<4)
        POP BC                ; 03F4  C1
        RET                   ; 03F5  C9
;
; Reads a single keyboard character end if a letter adds 6 then truncates to 4 bit binary (used as part of 03E7)
;
READ_HEX_DIGIT:
        HALT                  ; 03F6  76
L03F7:
        CP $20                ; 03F7  FE 20
        JR NC,L03FD           ; 03F9  30 02
        ADD A,$09             ; 03FB  C6 09
L03FD:
        AND $0F               ; 03FD  E6 0F
        RET                   ; 03FF  C9
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

        EXX                   ; 0400  D9
        LD HL,$1E0B           ; 0401  21 0B 1E
        LD A,(HL)             ; 0404  7E
        CP $0C                ; 0405  FE 0C
        JR NZ,L040C           ; 0407  20 03
        XOR A                 ; 0409  AF
        JR L042C              ; 040A  18 20
L040C:
        LD L,$0D              ; 040C  2E 0D
        LD D,(HL)             ; 040E  56
        INC D                 ; 040F  14
        LD L,$00              ; 0410  2E 00
        LD B,(HL)             ; 0412  46
        INC HL                ; 0413  23
L0414:
        DEC D                 ; 0414  15
        JR Z,L0424            ; 0415  28 0D
        INC HL                ; 0417  23
        LD A,(HL)             ; 0418  7E
        SLA B                 ; 0419  CB 20
        ADD A,B               ; 041B  80
        SLA B                 ; 041C  CB 20
        SLA B                 ; 041E  CB 20
        ADD A,B               ; 0420  80
        LD B,A                ; 0421  47
        JR L0414              ; 0422  18 F0
L0424:
        INC HL                ; 0424  23
        LD A,(HL)             ; 0425  7E
        CP $05                ; 0426  FE 05
        JR C,L042B            ; 0428  38 01
        INC B                 ; 042A  04
L042B:
        LD A,B                ; 042B  78
L042C:
        EXX                   ; 042C  D9
        RET                   ; 042D  C9
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
MM_SEND:
        PUSH BC               ; 042E  C5           preserve caller's BC
        LD B,A                ; 042F  47           B := A (save byte to send)
; Is MM57109 Ready?
L0430:
        IN A,($03)            ; 0430  DB 03        poll status: IN A,($03), is the MM57109 Ready?
        AND $20               ; 0432  E6 20        mask RDY bit (bit5)
        JR NZ,L0430           ; 0434  20 FA        wait for READY state, busy is indicated by RDY==1, and ready is indicated by RDY=0
; Send instruction to MM57109
        LD A,B                ; 0436  78           restore byte to send
        OUT ($60),A           ; 0437  D3 60        phase 1: OUT ($60),A
; Wait for MM57109 to show it is executing the instruction (RDY=1 when it is busy executing, ie not ready)
L0439:
        IN A,($03)            ; 0439  DB 03        poll for acknowledge: IN A,($03)
        AND $20               ; 043B  E6 20        mask RDY bit (bit5)
        JR Z,L0439            ; 043D  28 FA        wait for RDY==1 (indication that the instruction is being executed)
; Set the hold bit. This holds the MM57109 when it has completed the current instruction (ie when RDY=0)
        LD A,B                ; 043F  78           restore byte to send
        OR $80                ; 0440  F6 80        set hold bit7
        OUT ($60),A           ; 0442  D3 60        Sets HOLD
        POP BC                ; 0444  C1           Restore BC
        RET                   ; 0445  C9           RET
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
MM_SEND_INLINE:
        EX (SP),HL            ; 0446  E3
        LD A,(HL)             ; 0447  7E
        INC HL                ; 0448  23
        EX (SP),HL            ; 0449  E3
        CP $FF                ; 044A  FE FF
        RET Z                 ; 044C  C8
        CALL MM_SEND          ; 044D  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=byte)
        JR MM_SEND_INLINE     ; 0450  18 F4
;
; Jumps over next work in the program line. Used in FOR statements to miss STEP and UNTIL
;
SKIP_WORD:
        INC HL                ; 0452  23
L0453:
        INC HL                ; 0453  23
        LD A,(HL)             ; 0454  7E
        CP $20                ; 0455  FE 20
        JR NZ,L0453           ; 0457  20 FA
;
; Move to next token and BURP_EXPR_GET_TOKEN_AND_EMIT
;
L0459:
        INC HL                ; 0459  23           Move to the next char in the input
;
; 04E6 with BC protected. Repeats 042E for sequence of MM57109 instructions terminated with an FF
;
        PUSH BC               ; 045A  C5
        CALL BURP_EXPR_TERM   ; 045B  CD E6 04     BURP_EXPR_GET_TOKEN_AND_EMIT
        POP BC                ; 045E  C1
        RET                   ; 045F  C9
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
MM_OUT_X:
        EXX                   ; 0460  D9
        PUSH AF               ; 0461  F5
        LD HL,$1FF4           ; 0462  21 F4 1F
        IM 1                  ; 0465  ED 56
        EI                    ; 0467  FB           Enable interupts from MM57109 to results (if any from instruction can be sent)
        CALL MM_SEND_INLINE   ; 0468  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 046B-046D terminated by $FF
        DB $16,$2B,$FF                   ; 046B  16 2B FF  MM57109 instructions OUT*($2B)
        DI                    ; 046E  F3           Disable the interrupts again, the results should now be at $1FF4 (all 12 interrupts should have happened)
        POP AF                ; 046F  F1
        CALL BURP_CLEAR_BLOCK ; 0470  CD 14 07     by the time this is called the OUT instuction should have completed and the results will have been put in $1FF4
        LD A,L                ; 0473  7D
        AND $F0               ; 0474  E6 F0
        LD L,A                ; 0476  6F
        PUSH HL               ; 0477  E5
        ADD A,$0A             ; 0478  C6 0A
        LD L,A                ; 047A  6F
        LD DE,$1FF6           ; 047B  11 F6 1F
        EX DE,HL              ; 047E  EB
        LD A,$0B              ; 047F  3E 0B
        LD (DE),A             ; 0481  12
        INC DE                ; 0482  13
        BIT 0,(HL)            ; 0483  CB 46
        JR Z,L048A            ; 0485  28 03
        LD A,$0C              ; 0487  3E 0C
        LD (DE),A             ; 0489  12
L048A:
        INC DE                ; 048A  13
        DEC HL                ; 048B  2B
        DEC HL                ; 048C  2B
        LDI                   ; 048D  ED A0
        LDI                   ; 048F  ED A0
        LD A,E                ; 0491  7B
        AND $F0               ; 0492  E6 F0
        ADD A,$09             ; 0494  C6 09
        LD E,A                ; 0496  5F
        BIT 3,(HL)            ; 0497  CB 5E
        JR Z,L049E            ; 0499  28 03
        LD A,$0C              ; 049B  3E 0C
        LD (DE),A             ; 049D  12
L049E:
        POP DE                ; 049E  D1
        INC HL                ; 049F  23
        LD A,(HL)             ; 04A0  7E
        CPL                   ; 04A1  2F
        AND $0F               ; 04A2  E6 0F
        SUB $03               ; 04A4  D6 03
        INC HL                ; 04A6  23
        LD B,$00              ; 04A7  06 00
        LD C,A                ; 04A9  4F
        LDIR                  ; 04AA  ED B0
        CPL                   ; 04AC  2F
        ADD A,$09             ; 04AD  C6 09
        LD C,A                ; 04AF  4F
        LD A,$0A              ; 04B0  3E 0A
        LD (DE),A             ; 04B2  12
        INC DE                ; 04B3  13
        JR Z,L04B8            ; 04B4  28 02
        LDIR                  ; 04B6  ED B0
L04B8:
        EXX                   ; 04B8  D9
        RET                   ; 04B9  C9
;
; Need to annotate this
;
L04BA:
        AND $0F               ; 04BA  E6 0F
        LD C,A                ; 04BC  4F
L04BD:
        INC HL                ; 04BD  23
        LD A,(HL)             ; 04BE  7E
        CP $20                ; 04BF  FE 20
        RET Z                 ; 04C1  C8
        AND $0F               ; 04C2  E6 0F
        RLC C                 ; 04C4  CB 01
        ADD A,C               ; 04C6  81
        RLC C                 ; 04C7  CB 01
        RLC C                 ; 04C9  CB 01
        ADD A,C               ; 04CB  81
        LD C,A                ; 04CC  4F
        JR L04BD              ; 04CD  18 EE
        RST $38               ; 04CF  FF
        RST $38               ; 04D0  FF
        RST $38               ; 04D1  FF
        RST $38               ; 04D2  FF
        RST $38               ; 04D3  FF
        CALL BURP_EMIT_BLOCK  ; 04D4  CD 7B 05
        CALL MM_SEND_INLINE   ; 04D7  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 04DA-04DF terminated by $FF
        DB $3C,$01,$02,$06,$3B,$FF       ; 04DA  3C 01 02 06 3B FF  MM57109 instructions  /,1,2,3,*
        LD A,$00              ; 04E0  3E 00
        CALL MM_OUT_X         ; 04E2  CD 60 04     BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)
        RET                   ; 04E5  C9
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
BURP_EXPR_TERM:
        LD A,(HL)             ; 04E6  7E           read next byte from source line
        INC HL                ; 04E7  23
        LD C,$0F              ; 04E8  0E 0F        set up a format code 0F for 050F formatting (and possibly other routines)...
        CP $20                ; 04EA  FE 20        space?
        JR Z,BURP_EXPR_TERM   ; 04EC  28 F8        yes -> skip spaces and keep scanning
        CP $1B                ; 04EE  FE 1B
        JR C,L0545            ; 04F0  38 53        if A < 1B -> handle “small tokens” elsewhere  ; BURP_EXPR_DECODE_SMALLTOKEN_AND_EMIT_OP (tokens < $1B)
;  If token is followed by space ($20), uses $057B to emit a fixed 16-byte operand block.

; (likely variables, separators, parens, etc.)

        CP $30                ; 04F2  FE 30
        JR NC,L050F           ; 04F4  30 19        if A >= 30 -> handle ASCII/number-ish tokens elsewhere
; (likely numeric literal parsing: '0'..'9', maybe quotes, etc.)

; ---- so here: 1B <= A < 30 is a “mid-range token” fast-path ----

        CP $2D                ; 04F6  FE 2D        token 2D special-cased
        JR NZ,L04FD           ; 04F8  20 03        if not 2D, skip the special check
        CP (HL)               ; 04FA  BE           compare A (2D) with NEXT token in stream
        JR C,L050B            ; 04FB  38 0E        if 2D < (HL) -> go handle as special case
; (very likely disambiguating unary/binary '-' or function vs operator)

L04FD:
        ADD A,$0D             ; 04FD  C6 0D        map token range into MM57109 opcode space
        AND A                 ; 04FF  A7           refresh flags based on A
        JP PE,L0507           ; 0500  EA 07 05     if P/V=1 after the ADD -> take direct emit
        OR $09                ; 0503  F6 09        otherwise tweak bits...
        AND $FB               ; 0505  E6 FB        ...force bit2 clear, bits0+3 set (see below)
L0507:
        CALL MM_SEND          ; 0507  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=byte) ; emit the resulting byte to MM57109 interface
        RET                   ; 050A  C9
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
L050B:
        LD C,$0C              ; 050B  0E 0C        set mode/flag in C (0x0C) for number parsing
        LD A,(HL)             ; 050D  7E
        INC HL                ; 050E  23
; This is the entry point from the expression parser for literal numbers (A >= x30)
; C should have the mode in it...
L050F:
        EX AF,AF'             ; 050F  08           save A in AF' (token/char), switch to alternate accumulator
        PUSH DE               ; 0510  D5           preserve DE (input pointer)
        EX DE,HL              ; 0511  EB           DE <- HL (input ptr), HL will become destination buffer
        LD HL,$1E00           ; 0512  21 00 1E     HL = $1E00 (numeric literal workspace)
        LD B,$0F              ; 0515  06 0F        B = $0F (size/count for init routine)
        CALL L0720            ; 0517  CD 20 07     init/clear workspace region (likely 0x0F bytes)
        LD L,$09              ; 051A  2E 09        HL = $1E09
        LD (HL),C             ; 051C  71           store mode/flag C at $1E09
        LD L,$00              ; 051D  2E 00        HL = $1E00
        EX AF,AF'             ; 051F  08
L0520:
        AND $0F               ; 0520  E6 0F        extract low nibble (digit code)
        CP $0E                ; 0522  FE 0E
        JR NZ,L0528           ; 0524  20 02
        LD A,$0A              ; 0526  3E 0A        remap 0x0E -> 0x0A (special digit case)
L0528:
        LD (HL),A             ; 0528  77           store packed nibble/digit at workspace
        LD A,(DE)             ; 0529  1A           fetch next source byte via DE
        INC HL                ; 052A  23
        INC DE                ; 052B  13
        CP $28                ; 052C  FE 28        if byte >= $28, continue accumulating digits
        JR NC,L0520           ; 052E  30 F0
        CP $20                ; 0530  FE 20        if next byte is space, finish/emit via $0577
        JR Z,L0577            ; 0532  28 43
        LD L,$0A              ; 0534  2E 0A        write terminator/marker $0B at $1E0A
        LD (HL),$0B           ; 0536  36 0B
        INC HL                ; 0538  23
        LD A,(DE)             ; 0539  1A
        INC DE                ; 053A  13
        CP $2D                ; 053B  FE 2D        if next byte != '-' continue digit loop
        JR NZ,L0520           ; 053D  20 E1
        LD (HL),$0C           ; 053F  36 0C        write marker $0C (likely negative sign)
        INC HL                ; 0541  23
        LD A,(HL)             ; 0542  7E           reload current workspace byte (post-marker) and continue loop
        JR L0520              ; 0543  18 DB
;
; Jumped to from BURP_EXPR_GET_TOKEN_AND_EMIT function.
;
L0545:
        EX AF,AF'             ; 0545  08
        LD A,$20              ; 0546  3E 20
        CP (HL)               ; 0548  BE           peek next source byte: space ($20) means single-token form
        JR NZ,L054E           ; 0549  20 03
        EX AF,AF'             ; 054B  08           NOTE in the original scan this byte was ambiguious but it is def 08 NOTE: $08 (EX AF,AF') is far more plausible here than $0B (DEC BC) given control-flow/AF' usage.
        JR BURP_EMIT_BLOCK    ; 054C  18 2D        if single-token form, branch to $057B (build/emit fixed-width value)
L054E:
        DEC HL                ; 054E  2B
        CALL L0795            ; 054F  CD 95 07     compute 2-token dispatch code (drops into $0795): returns A = C + 2*B
        CP $20                ; 0552  FE 20        normalize dispatch code into table index: if A<20, add 20
        JR NC,L0558           ; 0554  30 02
        ADD A,$20             ; 0556  C6 20
L0558:
        CP $50                ; 0558  FE 50        if A>=50, fold range down by subtracting 10
        JR C,L055E            ; 055A  38 02
        SUB $10               ; 055C  D6 10
L055E:
        ADD A,$B4             ; 055E  C6 B4        bias into ROM table region: index += B4
        PUSH BC               ; 0560  C5
        LD C,A                ; 0561  4F
        LD B,$07              ; 0562  06 07        BC := $07xx points at opcode descriptor table in ROM
        LD A,(BC)             ; 0564  0A           A := opcode descriptor from ROM table
        POP BC                ; 0565  C1
        CP $80                ; 0566  FE 80        descriptor bit7 indicates prefix $20 should be emitted
        JR C,L0571            ; 0568  38 07        bit7 set? => emit prefix $20 first
        EX AF,AF'             ; 056A  08
        LD A,$20              ; 056B  3E 20
        CALL MM_SEND          ; 056D  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=byte)
        EX AF,AF'             ; 0570  08
L0571:
        AND $3F               ; 0571  E6 3F        opcode := descriptor & 3F (low 6 bits)
        CALL MM_SEND          ; 0573  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=byte) ; emit opcode byte to math-coprocessor interface ($042E)
        RET                   ; 0576  C9
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
L0577:
        DEC DE                ; 0577  1B           step DE back one (caller had advanced past delimiter)
        EX DE,HL              ; 0578  EB           restore HL from DE (input pointer back to HL)
        POP DE                ; 0579  D1           restore DE saved earlier (POP)
        XOR A                 ; 057A  AF           A := 0 (select default mode for $07AC)
BURP_EMIT_BLOCK:
        PUSH HL               ; 057B  E5           save HL, then call $07AC to prepare 16-byte emit source
        CALL BURP_BLOCK_ADDR  ; 057C  CD AC 07     BURP_PREPARE_16BYTE_OPERAND_BLOCK(A=selector)
        LD B,$10              ; 057F  06 10        emit 16 bytes to coprocessor stream
L0581:
        LD A,(HL)             ; 0581  7E
        INC HL                ; 0582  23
        CALL MM_SEND          ; 0583  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=(HL)) ; emit operand byte
        DJNZ L0581            ; 0586  10 F9
        POP HL                ; 0588  E1           restore HL and return
        RET                   ; 0589  C9
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
MM_SEND_TEST:
        PUSH BC               ; 058A  C5           PUSH BC (preserve)
        CALL MM_SEND          ; 058B  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=byte) ; send command/data
L058E:
        IN A,($03)            ; 058E  DB 03        poll port $03 (status + DO bits)
        LD B,A                ; 0590  47           B := raw port sample (latched for return)
        AND $60               ; 0591  E6 60        mask status bits RDY($20) and BR($40)
        JP PE,L058E           ; 0593  EA 8E 05     loop while parity-even => 0 or 2 bits set ($00 or $60); exit when $20 or $40
        CP $30                ; 0596  FE 30        if masked value >= $30, it's $40 (BR) (since $60 would not exit)
        JR NC,L059E           ; 0598  30 04
        LD A,$3F              ; 059A  3E 3F        else it is $20 (RDY): Output a NOP instruction
        OUT ($60),A           ; 059C  D3 60        Output a NOP instruction ...
L059E:
        IN A,($03)            ; 059E  DB 03        wait for RDY to deassert (bit5==0)
        AND $20               ; 05A0  E6 20
        JR NZ,L059E           ; 05A2  20 FA
        LD A,B                ; 05A4  78           A := latched raw port value
        AND $40               ; 05A5  E6 40        keep only bit6 (BR/test/status)
        POP BC                ; 05A7  C1           POP BC
        RET                   ; 05A8  C9           RET with A=$00 or $40 (Z/NZ)
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

L05A9:
        PUSH HL               ; 05A9  E5
        PUSH DE               ; 05AA  D5
        CALL BURP_BLOCK_ADDR  ; 05AB  CD AC 07     HL <- base of selected 16-byte operand block, BURP_PREPARE_16BYTE_OPERAND_BLOCK(A=selector)
        PUSH HL               ; 05AE  E5           save base pointer
        LD DE,$1E00           ; 05AF  11 00 1E     DE = numeric formatting workspace
        LD A,L                ; 05B2  7D
        ADD A,$09             ; 05B3  C6 09
        LD L,A                ; 05B5  6F           HL = block + 9
        CALL L07B7            ; 05B6  CD B7 07     transfer workspace<->block at offset +9
        POP HL                ; 05B9  E1           restore block base
        LD B,$09              ; 05BA  06 09
L05BC:
        CALL L07B7            ; 05BC  CD B7 07     transfer 9 bytes (loop)
        DJNZ L05BC            ; 05BF  10 FB
        INC HL                ; 05C1  23           skip (field boundary)
        LD B,$06              ; 05C2  06 06
L05C4:
        CALL L07B7            ; 05C4  CD B7 07     transfer 6 bytes (loop)
        DJNZ L05C4            ; 05C7  10 FB
        EX DE,HL              ; 05C9  EB           HL now indexes workspace record, DE holds block pointer
; --- normalise decimal point / leading digit structure ---

        LD L,$0C              ; 05CA  2E 0C
        LD A,(HL)             ; 05CC  7E
        CP $30                ; 05CD  FE 30        ASCII '0'?
        JR NZ,L0627           ; 05CF  20 56        if not '0', skip leading-zero fixups
        DEC L                 ; 05D1  2D           L=0B
        LD A,(HL)             ; 05D2  7E
        CP $A0                ; 05D3  FE A0        A0 = filler/blank marker?
        INC HL                ; 05D5  23
        INC HL                ; 05D6  23           advance to L=0D
        LD A,(HL)             ; 05D7  7E
        JR NZ,L05F1           ; 05D8  20 17        branch based on field content pattern
        CP $38                ; 05DA  FE 38        ASCII '8' boundary check (digit range test)
        JR NC,L0627           ; 05DC  30 49        if >= '8', bail to decimal scan
; Case A: shift digits left and insert decimal point near front
        LD L,$03              ; 05DE  2E 03
        AND $0F               ; 05E0  E6 0F        digit count nibble?
        JR Z,L061E            ; 05E2  28 3A        if 0, skip to A0-fill
        LD B,A                ; 05E4  47
L05E5:
        LD A,(HL)             ; 05E5  7E
        DEC HL                ; 05E6  2B
        LD (HL),A             ; 05E7  77           shift bytes left by one
        INC HL                ; 05E8  23
        INC HL                ; 05E9  23
        DJNZ L05E5            ; 05EA  10 F9
        DEC HL                ; 05EC  2B
        LD (HL),$2E           ; 05ED  36 2E        write '.' (decimal point)
        JR L061E              ; 05EF  18 2D        continue with A0-fill
; Case B: alternative shift/decimal arrangement
L05F1:
        CP $34                ; 05F1  FE 34        ASCII '4' boundary
        JR NC,L0627           ; 05F3  30 32
        AND $0F               ; 05F5  E6 0F
        JR Z,L061E            ; 05F7  28 25
        LD B,A                ; 05F9  47
        LD L,$01              ; 05FA  2E 01
        LD A,(HL)             ; 05FC  7E
        LD (HL),$2E           ; 05FD  36 2E        place '.'
        INC HL                ; 05FF  23
        LD (HL),A             ; 0600  77           shift digit right
L0601:
        LD L,$08              ; 0601  2E 08
L0603:
        LD A,(HL)             ; 0603  7E
        INC HL                ; 0604  23
        LD (HL),A             ; 0605  77
        DEC HL                ; 0606  2B
        DEC HL                ; 0607  2B
        LD A,L                ; 0608  7D
        CP $00                ; 0609  FE 00
        JR NZ,L0603           ; 060B  20 F6
        DJNZ L0601            ; 060D  10 F2
        LD L,$01              ; 060F  2E 01
        LD (HL),$30           ; 0611  36 30        force leading '0'
        INC HL                ; 0613  23
L0614:
        INC HL                ; 0614  23
        LD A,(HL)             ; 0615  7E
        CP $2E                ; 0616  FE 2E
        JR NZ,L061E           ; 0618  20 04
        LD (HL),$30           ; 061A  36 30        replace '.' adjacency with '0'
        JR L0614              ; 061C  18 F6
; Fill a region with A0 (blank marker)
L061E:
        LD L,$0A              ; 061E  2E 0A
        LD B,$05              ; 0620  06 05
L0622:
        LD (HL),$A0           ; 0622  36 A0
        INC HL                ; 0624  23
        DJNZ L0622            ; 0625  10 FB
; --- scan backward to decimal point '.' ---
L0627:
        LD A,$2E              ; 0627  3E 2E
L0629:
        DEC L                 ; 0629  2D
        CP (HL)               ; 062A  BE
        JR NZ,L0629           ; 062B  20 FC        loop until '.' found
; restore DE and recover an index nibble from next char
        POP DE                ; 062D  D1
        EX (SP),HL            ; 062E  E3
        INC HL                ; 062F  23
        LD A,(HL)             ; 0630  7E
        CP $30                ; 0631  FE 30
        JR NC,L0638           ; 0633  30 03
        DEC HL                ; 0635  2B
        JR L063D              ; 0636  18 05
L0638:
        AND $0F               ; 0638  E6 0F
        LD ($1FE0),A          ; 063A  32 E0 1F     store digit nibble
L063D:
        EX (SP),HL            ; 063D  E3
; compute placement / rounding target index based on $1FE0 + L
        LD A,($1FE0)          ; 063E  3A E0 1F
        ADD A,L               ; 0641  85
        CP $09                ; 0642  FE 09
        JR NC,L0682           ; 0644  30 3C        if too large, skip rounding/pad path
        LD L,A                ; 0646  6F
        INC HL                ; 0647  23
        PUSH HL               ; 0648  E5           save rounding position
        LD A,(HL)             ; 0649  7E
        CP $35                ; 064A  FE 35        >= '5' ?
        JR C,L0678            ; 064C  38 2A        if < '5', no rounding increment
; rounding: walk left, skip '.', increment digit with carry
L064E:
        DEC L                 ; 064E  2D
        LD A,L                ; 064F  7D
        CP $01                ; 0650  FE 01
        LD A,(HL)             ; 0652  7E
        JR Z,L0666            ; 0653  28 11
        CP $2E                ; 0655  FE 2E
        JR Z,L064E            ; 0657  28 F5        skip '.' while carrying
        LD A,(HL)             ; 0659  7E
        CP $39                ; 065A  FE 39
        JR Z,L0661            ; 065C  28 03        if '9', wrap to '0' and keep carrying
L065E:
        INC (HL)              ; 065E  34           increment digit
        JR L0678              ; 065F  18 17        (byte here should be 18, not 1B) NOTE: $18 (JR) is strongly preferred over $1B; this is a forward jump over the carry/rounding block.
L0661:
        LD (HL),$30           ; 0661  36 30
        LD A,(HL)             ; 0663  7E
        JR L064E              ; 0664  18 E8
; carry reached left boundary: create leading '1' and shift decimal right
L0666:
        CP $39                ; 0666  FE 39
        JR NZ,L065E           ; 0668  20 F4
        LD (HL),$31           ; 066A  36 31
        LD A,$2E              ; 066C  3E 2E
L066E:
        INC L                 ; 066E  2C
        CP (HL)               ; 066F  BE
        JR NZ,L066E           ; 0670  20 FC
        INC HL                ; 0672  23
        LD (HL),A             ; 0673  77
        DEC HL                ; 0674  2B
        LD (HL),$30           ; 0675  36 30
        NOP                   ; 0677  00
; pad with spaces to fixed width
L0678:
        POP HL                ; 0678  E1
        LD A,$0A              ; 0679  3E 0A
        SUB L                 ; 067B  95
        LD B,A                ; 067C  47
L067D:
        LD (HL),$20           ; 067D  36 20        ASCII space
        INC HL                ; 067F  23
        DJNZ L067D            ; 0680  10 FB
; emit up to 10 chars to output buffer (DE), stop on space
L0682:
        LD L,$00              ; 0682  2E 00
        LD B,$0A              ; 0684  06 0A
L0686:
        LD A,(HL)             ; 0686  7E
        CP $20                ; 0687  FE 20
        JR Z,L0690            ; 0689  28 05
        LD (DE),A             ; 068B  12
        INC DE                ; 068C  13
        INC HL                ; 068D  23
        DJNZ L0686            ; 068E  10 F6
; output padding/separators depending on next source character and remaining width
L0690:
        EX (SP),HL            ; 0690  E3
        INC HL                ; 0691  23
        LD A,(HL)             ; 0692  7E
        CP $2C                ; 0693  FE 2C        comma?
        NOP                   ; 0695  00
        EX (SP),HL            ; 0696  E3
        JR Z,L06AA            ; 0697  28 11
        XOR A                 ; 0699  AF
        CP B                  ; 069A  B8
        JR Z,L06A0            ; 069B  28 03
L069D:
        RST $20               ; 069D  E7           emit filler (likely space)
        DJNZ L069D            ; 069E  10 FD
L06A0:
        LD L,$0A              ; 06A0  2E 0A
        LD A,(HL)             ; 06A2  7E
        CP $05                ; 06A3  FE 05
        JR Z,L06AA            ; 06A5  28 03
        RST $20               ; 06A7  E7
        RST $20               ; 06A8  E7
        RST $20               ; 06A9  E7
; optional 3-byte suffix if record[+2A] == 05
L06AA:
        LD L,$0A              ; 06AA  2E 0A        buffer[0A] again: 05 ('E') means scientific notation. Was read as 2A, which never found the E, so exponents weren't printed; corrected to 0A (same test as 06A0).
        LD A,(HL)             ; 06AC  7E
        CP $05                ; 06AD  FE 05
        JR NZ,L06B9           ; 06AF  20 08
        LD B,$03              ; 06B1  06 03
L06B3:
        INC HL                ; 06B3  23
        LD A,(HL)             ; 06B4  7E
        LD (DE),A             ; 06B5  12
        INC DE                ; 06B6  13
        DJNZ L06B3            ; 06B7  10 FA
L06B9:
        POP HL                ; 06B9  E1
        RET                   ; 06BA  C9
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
;   - 06AA: 'LD L,$0A' (was transcribed as 2A): it tests buffer[0A] for 05 ('E') like 06A0, then copies the
;     exponent sign and digits after it. With 2A the exponent of a number in scientific notation was never printed.
; -----------------------------------------------------------------------------
L06BB:
        PUSH HL               ; 06BB  E5
        CALL BURP_CLEAR_BLOCK ; 06BC  CD 14 07
        LD BC,$090A           ; 06BF  01 0A 09
        HALT                  ; 06C2  76
        CP $2D                ; 06C3  FE 2D
        JR NZ,L06CF           ; 06C5  20 08
        LD A,L                ; 06C7  7D
        AND $F9               ; 06C8  E6 F9
        LD L,A                ; 06CA  6F
        LD A,$0C              ; 06CB  3E 0C
        LD (HL),A             ; 06CD  77
        HALT                  ; 06CE  76
L06CF:
        EX AF,AF'             ; 06CF  08
        LD A,L                ; 06D0  7D
        AND $F0               ; 06D1  E6 F0
        LD L,A                ; 06D3  6F
        EX AF,AF'             ; 06D4  08
L06D5:
        CP $28                ; 06D5  FE 28
        JR C,L06EF            ; 06D7  38 16
        CP $2E                ; 06D9  FE 2E
        JR NZ,L06E0           ; 06DB  20 03
        LD A,C                ; 06DD  79
        LD C,$00              ; 06DE  0E 00
L06E0:
        AND $0F               ; 06E0  E6 0F
        LD (HL),A             ; 06E2  77
        INC HL                ; 06E3  23
L06E4:
        HALT                  ; 06E4  76
        DJNZ L06D5            ; 06E5  10 EE
        LD B,$01              ; 06E7  06 01
        CP $30                ; 06E9  FE 30
        JR NC,L06E4           ; 06EB  30 F7
        JR L06F0              ; 06ED  18 01
L06EF:
        LD (HL),C             ; 06EF  71
L06F0:
        CP $20                ; 06F0  FE 20
        JR Z,L0712            ; 06F2  28 1E
        LD A,L                ; 06F4  7D
        AND $F0               ; 06F5  E6 F0
        ADD A,$0A             ; 06F7  C6 0A
        LD L,A                ; 06F9  6F
        LD (HL),$0B           ; 06FA  36 0B
        INC HL                ; 06FC  23
L06FD:
        LD B,$02              ; 06FD  06 02
L06FF:
        HALT                  ; 06FF  76
        CP $2D                ; 0700  FE 2D
        JR NZ,L0709           ; 0702  20 05
        LD A,$0C              ; 0704  3E 0C
        LD (HL),A             ; 0706  77
        JR L06FD              ; 0707  18 F4
L0709:
        INC HL                ; 0709  23
        NOP                   ; 070A  00
        AND $0F               ; 070B  E6 0F
        LD (HL),A             ; 070D  77
        NOP                   ; 070E  00
        DJNZ L06FF            ; 070F  10 EE
        RST $20               ; 0711  E7
L0712:
        POP HL                ; 0712  E1
        RET                   ; 0713  C9
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
BURP_CLEAR_BLOCK:
        CALL BURP_BLOCK_ADDR  ; 0714  CD AC 07     HL <- base of selected 16-byte block ($1Exx/$1Fxx),BURP_PREPARE_16BYTE_OPERAND_BLOCK(A=selector)
        LD B,$09              ; 0717  06 09        clear first 9 bytes
        XOR A                 ; 0719  AF           A=00
L071A:
        LD (HL),A             ; 071A  77
        INC HL                ; 071B  23
        DJNZ L071A            ; 071C  10 FC
        LD B,$06              ; 071E  06 06        fill next 6 bytes with 0F
;
; Fill region with count stored in B, with 0F, terminate with 3F
;
L0720:
        LD A,$0F              ; 0720  3E 0F
L0722:
        LD (HL),A             ; 0722  77
        INC HL                ; 0723  23
        DJNZ L0722            ; 0724  10 FC
        LD (HL),$3F           ; 0726  36 3F        record[+0F] = 3F (terminator/default)
        RET                   ; 0728  C9
;
; ## BURP_WAIT_COMMAND ($0729)
; Command token is returned in A.
; LOAD = 1C
; LIST = 2C
; RUN  = 32
; DEL  = 14
; ADD  = 06
; MOD  = 1E
; DUMP = 18
;
BURP_READ_COMMAND:
        HALT                  ; 0729  76           Waiting for First keystroke of BURP command
        LD B,A                ; 072A  47           keypress stored in B
        HALT                  ; 072B  76           waiting for second keystroke of BURP command
L072C:
        LD C,A                ; 072C  4F           keypress stored in C
        HALT                  ; 072D  76           waiting for third and further keystroke of BURP command until space
        CP $20                ; 072E  FE 20
        JR NZ,L072C           ; 0730  20 FA
        LD A,C                ; 0732  79           Command token is 2nd char + 1st char + 1st char
        ADD A,B               ; 0733  80
        ADD A,B               ; 0734  80
        RET                   ; 0735  C9
;
; ------------------------------------------------------------
; MON:PARSE_DECIMAL_BYTE  ($0736)
;
; Reads decimal digits from keyboard until SPACE.
; Returns value (0–255) in A.
;
; Behaviour:
;   - First digit becomes initial value
;   - Subsequent digits: value = value * 10 + digit
;   - Terminates on SPACE
;
; Uses:  A, B, C
; Preserves: none
; ------------------------------------------------------------
BURP_READ_NUMBER:
        HALT                  ; 0736  76
        AND $0F               ; 0737  E6 0F
L0739:
        LD C,A                ; 0739  4F
        HALT                  ; 073A  76
        CP $20                ; 073B  FE 20
        RET Z                 ; 073D  C8           Return on SPACE being pressed..
        AND $0F               ; 073E  E6 0F
        LD B,A                ; 0740  47
        LD A,C                ; 0741  79
        RLCA                  ; 0742  07
        LD C,A                ; 0743  4F
        RLCA                  ; 0744  07
        RLCA                  ; 0745  07
        ADD A,C               ; 0746  81
        ADD A,B               ; 0747  80
        JR L0739              ; 0748  18 EF        loop for next keypress
;
;
;
; ------------------------------------------------------------
; $074A  MON:PUT_U8_AS_DEC3_AT_DE
; Convert A (0..255) to 3 ASCII decimal digits (hundreds,tens,ones)
; and store at (DE)..(DE+2). Always emits leading zeros.
; Advances DE by 3. Preserves BC.
;
L074A:
        PUSH BC               ; 074A  C5
; Hundreds digit accumulator starts at '0'
        LD B,$30              ; 074B  06 30        B = '0' (hundreds)
; while A >= 100: A -= 100, B++
L074D:
        CP $64                ; 074D  FE 64        compare A with 100
        JR C,L0756            ; 074F  38 05        if A < 100, done hundreds loop
        INC B                 ; 0751  04           hundreds++
        SUB $64               ; 0752  D6 64        A -= 100
        JR L074D              ; 0754  18 F7
; Tens digit accumulator starts at '0'
L0756:
        LD C,$30              ; 0756  0E 30        C = '0' (tens)
; while A >= 10: A -= 10, C++
L0758:
        CP $0A                ; 0758  FE 0A        compare A with 10
        JR C,L0761            ; 075A  38 05        if A < 10, done tens loop
        INC C                 ; 075C  0C           tens++
        SUB $0A               ; 075D  D6 0A        A -= 10
        JR L0758              ; 075F  18 F7
; Ones digit: convert 0..9 to '0'..'9'
L0761:
        ADD A,$30             ; 0761  C6 30        A = ones ASCII
; Store "B C A" to *(DE), using HL as the store pointer
        EX DE,HL              ; 0763  EB           HL = DE (dest), DE = old HL
        LD (HL),B             ; 0764  70           write hundreds
        INC HL                ; 0765  23
        LD (HL),C             ; 0766  71           write tens
        INC HL                ; 0767  23
        LD (HL),A             ; 0768  77           write ones
        INC HL                ; 0769  23
        EX DE,HL              ; 076A  EB           DE = DE+3 (advanced), HL restored
        POP BC                ; 076B  C1
        RET                   ; 076C  C9
; ------------------------------------------------------------

L076D:
        PUSH BC               ; 076D  C5
        LD BC,$3030           ; 076E  01 30 30
L0771:
        CP $64                ; 0771  FE 64
        JR C,L077A            ; 0773  38 05
        SUB $64               ; 0775  D6 64
        INC B                 ; 0777  04
        JR L0771              ; 0778  18 F7
L077A:
        CP $0A                ; 077A  FE 0A
        JR C,L0783            ; 077C  38 05
        SUB $0A               ; 077E  D6 0A
        INC C                 ; 0780  0C
        JR L077A              ; 0781  18 F7
L0783:
        PUSH AF               ; 0783  F5
        LD A,B                ; 0784  78
        CALL L02A5            ; 0785  CD A5 02     MON: CP A,$1B
        LD A,C                ; 0788  79
        CALL L02A5            ; 0789  CD A5 02     MON: CP A,$1B
        POP AF                ; 078C  F1
        ADD A,$30             ; 078D  C6 30
        CALL L02A5            ; 078F  CD A5 02     MON: CP A,$1B
        POP BC                ; 0792  C1
        RET                   ; 0793  C9
; 0794: BURP_DECODE_LINE_OPCODE
; HL -> byte after line number
; Returns A = statement dispatch code
;
; Gets the 1st char of text and the last char before a space and makes a uniq token from it.

BURP_LINE_TOKEN:
        INC HL                ; 0794  23           move past the line number byte
L0795:
        LD B,(HL)             ; 0795  46           load next token into B
        INC HL                ; 0796  23           move to next token on line
L0797:
        LD C,(HL)             ; 0797  4E           move token into C
        INC HL                ; 0798  23           move to next token
        LD A,(HL)             ; 0799  7E           move token into A
        CP $20                ; 079A  FE 20        is it a space
        JR NZ,L0797           ; 079C  20 F9        loop until it is a space
        LD A,C                ; 079E  79           C holds last char and b the 1st char
        ADD A,B               ; 079F  80           make a uniq token for the word
        ADD A,B               ; 07A0  80
        RET                   ; 07A1  C9           Return
        DB $17,$12,$09,$14,$05,$10,$12,$09; 07A2  17 12 09 14 05 10 12 09  keywords "WRITE" and "PRINT" in the 5-bit letter codes (W=17h R=12h I=09h T=14h E=05h P=10h N=0Eh)
        DB $0E,$14                       ; 07AA  0E 14
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
BURP_BLOCK_ADDR:
        AND A                 ; 07AC  A7           clear carry; set flags from A (selector)
        LD H,$1E              ; 07AD  26 1E        H := $1E (base page $1E00)
        RLA                   ; 07AF  17           shift selector left 1 (1/4): builds offset*16; carry tracks original bit4 after 4 shifts
        RLA                   ; 07B0  17           shift left (2/4)
        RLA                   ; 07B1  17           shift left (3/4)
        RLA                   ; 07B2  17           shift left (4/4)
        LD L,A                ; 07B3  6F           L := A (low byte = (selector<<4) & $F0)
        RET NC                ; 07B4  D0           if carry==0 (original bit4=0), return with HL in $1E00 page
        INC H                 ; 07B5  24           else select $1F00 page
        RET                   ; 07B6  C9           return
L07B7:
        LD A,(HL)             ; 07B7  7E
        CP $0B                ; 07B8  FE 0B
        JR NZ,L07BE           ; 07BA  20 02
        LD A,$D5              ; 07BC  3E D5
L07BE:
        CP $0A                ; 07BE  FE 0A
        JR NZ,L07C4           ; 07C0  20 02
        LD A,$FE              ; 07C2  3E FE
L07C4:
        CP $0F                ; 07C4  FE 0F
        JR NZ,L07CA           ; 07C6  20 02
        LD A,$70              ; 07C8  3E 70
L07CA:
        CP $0C                ; 07CA  FE 0C
        JR NZ,L07D0           ; 07CC  20 02
        LD A,$FD              ; 07CE  3E FD
L07D0:
        ADD A,$30             ; 07D0  C6 30
        LD (DE),A             ; 07D2  12
        INC DE                ; 07D3  13
        INC HL                ; 07D4  23
        RET                   ; 07D5  C9
        LD SP,$3F0C           ; 07D6  31 0C 3F
        CCF                   ; 07D9  3F
        DEC (HL)              ; 07DA  35
        SCF                   ; 07DB  37
        INC L                 ; 07DC  2C
        DEC C                 ; 07DD  0D
        CCF                   ; 07DE  3F
        CCF                   ; 07DF  3F
        DEC E                 ; 07E0  1D
        INC E                 ; 07E1  1C
        CCF                   ; 07E2  3F
        LD ($3F23),HL         ; 07E3  22 23 3F
        CCF                   ; 07E6  3F
        AND L                 ; 07E7  A5
        INC H                 ; 07E8  24
        CCF                   ; 07E9  3F
        LD H,$33              ; 07EA  26 33
        INC (HL)              ; 07EC  34
        DEC H                 ; 07ED  25
        DEC L                 ; 07EE  2D
        CPL                   ; 07EF  2F
        DEC HL                ; 07F0  2B
        DEC DE                ; 07F1  1B
        LD HL,$3236           ; 07F2  21 36 32
        CCF                   ; 07F5  3F
        CCF                   ; 07F6  3F
        AND H                 ; 07F7  A4
        CCF                   ; 07F8  3F
        AND (HL)              ; 07F9  A6
        CCF                   ; 07FA  3F
        CCF                   ; 07FB  3F
        CCF                   ; 07FC  3F
        JR NC,$0837           ; 07FD  30 38
        RET P                 ; 07FF  F0
; ## BURP_ENTRY ($0800)

BURP_ENTRY:
        LD SP,$1FDF           ; 0800  31 DF 1F
        LD DE,$8000           ; 0803  11 00 80
        CALL PRINT_INLINE     ; 0806  CD CE 03     MON: EX (SP),HL;  HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0809-080F terminated by $1D
        DB $20,$02,$15,$12,$10,$20,$1D   ; 0809  20 02 15 12 10 20 1D  " BURP "
        RST $20               ; 0810  E7
        RST $20               ; 0811  E7
        PUSH DE               ; 0812  D5
        CALL PAD_TO_NEXT_LINE ; 0813  CD C4 03
        POP DE                ; 0816  D1
        LD A,$04              ; 0817  3E 04
        LD ($1FE0),A          ; 0819  32 E0 1F
        LD E,$08              ; 081C  1E 08
        LD A,$40              ; 081E  3E 40
        CALL INLINE_DELAY_1B  ; 0820  CD 36 03     MON: EX (SP),HL;  HL = return address (points to inline delay count byte) [MON:INLINE_DELAY_1B]
        DB $10                           ; 0823  10  delay count for INLINE_DELAY_1B (the CALL above)
        LD A,$3F              ; 0824  3E 3F
        OUT ($60),A           ; 0826  D3 60
        IM 1                  ; 0828  ED 56
        CALL INLINE_DELAY_1B  ; 082A  CD 36 03     MON: EX (SP),HL;  HL = return address (points to inline delay count byte) [MON:INLINE_DELAY_1B]
        SUB B                 ; 082D  90           delay count for INLINE_DELAY_1B (the CALL above)
        LD A,$BF              ; 082E  3E BF
        OUT ($60),A           ; 0830  D3 60
        CALL MM_SEND_INLINE   ; 0832  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
        DB $2F,$22,$FF                   ; 0835  2F 22 FF  MM57109 instructions MCLR,TOGM,  Inline data for CALL $0446: bytes 0835-0837 terminated by $FF
;
; Main BURP wait for command and process loop!
;
        CALL BURP_READ_COMMAND; 0838  CD 29 07     BURP_WAIT_COMMAND , DEL(14),MOD(1E),ADD(06),LOAD(1C),LIST(2C),DUMP(18),RUN(32)
        CP $14                ; 083B  FE 14        DEL command?
        JR NZ,L08BE           ; 083D  20 7F        check
;
; DEL command
;
        RST $20               ; 083F  E7
        CALL BURP_READ_NUMBER ; 0840  CD 36 07     PARSE_DECIMAL_BYTE from input
        LD HL,$0C00           ; 0843  21 00 0C     Start of program space is at 0C00
L0846:
        LD A,(HL)             ; 0846  7E
L0847:
        CP $C0                ; 0847  FE C0        is it end of program marker
        JR Z,BURP_ENTRY       ; 0849  28 B5        Back to entry point ..
        INC HL                ; 084B  23           move forward a byte
        CP $ED                ; 084C  FE ED        is it start of line marker
        JR NZ,L0846           ; 084E  20 F6        loop until it is a start of line
        LD A,(HL)             ; 0850  7E           get the line number
        CP C                  ; 0851  B9           is it the line number we want to delete
        JR NZ,L0847           ; 0852  20 F3        no, loop again
        DEC HL                ; 0854  2B           Yes we are at the line to delete - backup to start of line marker.
        DEC HL                ; 0855  2B
        PUSH HL               ; 0856  E5           save the position on the stack
        POP DE                ; 0857  D1           Move it into DE
L0858:
        INC DE                ; 0858  13           DE now points to line number of line to be deleted.
        LD A,(DE)             ; 0859  1A
        CP $1F                ; 085A  FE 1F        Is End of Line marker (1st time through should be start of line marker ED)
        JR NZ,L0858           ; 085C  20 FA        Loop until it is
L085E:
        LD A,(DE)             ; 085E  1A           Load end of line marker into A?
        LD (HL),A             ; 085F  77
        INC HL                ; 0860  23
        INC DE                ; 0861  13
        LD A,D                ; 0862  7A
        CP $1E                ; 0863  FE 1E        ??
        JR NZ,L085E           ; 0865  20 F7        if D != 1E, loop back and copy another byte, this is just copying up to an upper addr limit of 1E00 which may or may not be OK.
L0867:
        LD C,$01              ; 0867  0E 01
;
; Clear the screen and LIST the program ??
;
L0869:
        CALL CLEAR_SCREEN     ; 0869  CD 93 03     CLEAR_SCREEN_8040_87FF
        LD DE,$8040           ; 086C  11 40 80
        DEC C                 ; 086F  0D
L0870:
        INC C                 ; 0870  0C
        JR NZ,L0878           ; 0871  20 05
        CALL PRINT_HEX_WORD_HL; 0873  CD 9F 03     MON: LD A,H;  [MON:PRINT_HEX_WORD_HL]
L0876:
        JR BURP_ENTRY         ; 0876  18 88
L0878:
        LD HL,$0C00           ; 0878  21 00 0C
L087B:
        LD A,(HL)             ; 087B  7E
        CP $C0                ; 087C  FE C0        End of program marker
        JR Z,L0870            ; 087E  28 F0
L0880:
        CP $ED                ; 0880  FE ED        start of line marker?
        INC HL                ; 0882  23
        JR NZ,L087B           ; 0883  20 F6
        LD A,(HL)             ; 0885  7E
        CP C                  ; 0886  B9           I think C should hold the line no we are deleting but it ended up with 1 in it?
        JR NZ,L0880           ; 0887  20 F7        Loop until we dinf the right line
        CALL L074A            ; 0889  CD 4A 07     PUT_U8_AS_DEC3_AT_DE - Convert A (0..255) to 3 ASCII decimal digits (hundreds,tens,ones), outputs the line number in LIST command.
        RST $20               ; 088C  E7
        LD A,D                ; 088D  7A
;
; 88 Command ??
;
        CP $88                ; 088E  FE 88
        JR NZ,L08A8           ; 0890  20 16
        CALL PRINT_INLINE     ; 0892  CD CE 03     MON: EX (SP),HL;  HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0895-08A4 terminated by $1D
        DB $0C,$09,$13,$14,$20,$09,$0E,$03; 0895  0C 09 13 14 20 09 0E 03  "LIST INCOMPLETE"
        DB $0F,$0D,$10,$0C,$05,$14,$05,$1D; 089D  0F 0D 10 0C 05 14 05 1D
        HALT                  ; 08A5  76
        JR L0869              ; 08A6  18 C1
;
; ???
;
L08A8:
        INC HL                ; 08A8  23
        LD A,(HL)             ; 08A9  7E
        CP $C0                ; 08AA  FE C0
        JR Z,L0870            ; 08AC  28 C2
        LD (DE),A             ; 08AE  12
        INC DE                ; 08AF  13
        CP $1F                ; 08B0  FE 1F
        JR NZ,L08A8           ; 08B2  20 F4
        CALL PAD_TO_NEXT_LINE ; 08B4  CD C4 03
        LD A,D                ; 08B7  7A
        CP $1E                ; 08B8  FE 1E
        JR NZ,L0870           ; 08BA  20 B4
L08BC:
        JR L0876              ; 08BC  18 B8
;
; Clear screen, and then check for MOD,ADD,LOAD,LIST,DUMP,RUN commands each in turn.
; If no matching command, it just loops forever until user presses a key causing it to back to monitor
;
L08BE:
        PUSH AF               ; 08BE  F5
        CALL CLEAR_SCREEN     ; 08BF  CD 93 03     MON: PUSH DE;  [MON:CLEAR_SCREEN_8040_87FF]
        POP AF                ; 08C2  F1
        CP $1E                ; 08C3  FE 1E        is  MOD command (1E)
        JR NZ,L08F3           ; 08C5  20 2C        jumop if not
;
; MOD Command (1E)
;
        LD HL,$0BFF           ; 08C7  21 FF 0B
L08CA:
        INC HL                ; 08CA  23
        LD A,(HL)             ; 08CB  7E
        CP $C0                ; 08CC  FE C0
        JR Z,L0867            ; 08CE  28 97
        CP $ED                ; 08D0  FE ED
        JR NZ,L08CA           ; 08D2  20 F6
        INC HL                ; 08D4  23
        CALL BURP_LINE_TOKEN  ; 08D5  CD 94 07
        CP $34                ; 08D8  FE 34
        JR NZ,L08E9           ; 08DA  20 0D
        LD DE,$07A6           ; 08DC  11 A6 07
L08DF:
        LD BC,$0005           ; 08DF  01 05 00
        EX DE,HL              ; 08E2  EB
        DEC DE                ; 08E3  1B
        LDDR                  ; 08E4  ED B8
        EX DE,HL              ; 08E6  EB
        JR L08CA              ; 08E7  18 E1
L08E9:
        CP $33                ; 08E9  FE 33
        JR NZ,L08CA           ; 08EB  20 DD
        LD DE,$07AB           ; 08ED  11 AB 07
        JR L08DF              ; 08F0  18 ED
        DB $0E                           ; 08F2  0E  unused: the JR above never falls through, and the code below is reached by the jump to 08F3
;
;  Test if ADD command
;
L08F3:
        CP $06                ; 08F3  FE 06        is it the ADD command
        JR NZ,L0927           ; 08F5  20 30
        LD HL,$0BFF           ; 08F7  21 FF 0B
L08FA:
        INC HL                ; 08FA  23
        LD A,(HL)             ; 08FB  7E
        CP $C0                ; 08FC  FE C0
        JR NZ,L08FA           ; 08FE  20 FA
        JR L0905              ; 0900  18 03
;
; LOAD Command
;
L0902:
        LD HL,$0C00           ; 0902  21 00 0C
L0905:
        LD DE,$8040           ; 0905  11 40 80
L0908:
        LD (HL),$ED           ; 0908  36 ED
        INC HL                ; 090A  23
        CALL BURP_READ_NUMBER ; 090B  CD 36 07     PARSE_DECIMAL_BYTE from input
        LD (HL),C             ; 090E  71
        INC HL                ; 090F  23
L0910:
        HALT                  ; 0910  76
        CP $3A                ; 0911  FE 3A
        JR Z,L0920            ; 0913  28 0B
        CALL L00D6            ; 0915  CD D6 00     MON: CP A,$1B
        LD (HL),A             ; 0918  77
        INC HL                ; 0919  23
        CP $1F                ; 091A  FE 1F
        JR Z,L0908            ; 091C  28 EA
        JR L0910              ; 091E  18 F0
L0920:
        LD (HL),$1F           ; 0920  36 1F
        INC HL                ; 0922  23
        LD (HL),$C0           ; 0923  36 C0
L0925:
        JR L08BC              ; 0925  18 95
;
; Test if LOAD Command (1C)
;
L0927:
        CP $1C                ; 0927  FE 1C
        JR Z,L0902            ; 0929  28 D7
;
; Test if LIST command
;
        CP $2C                ; 092B  FE 2C
        JR NZ,L0935           ; 092D  20 06
;
; LIST command
;
        CALL BURP_READ_NUMBER ; 092F  CD 36 07     PARSE_DECIMAL_BYTE from input
        JP L0869              ; 0932  C3 69 08
;
; Test if DUMP command (18)
;
L0935:
        CP $18                ; 0935  FE 18
        JR NZ,L0973           ; 0937  20 3A
;
; DUMP command
;
        CALL BURP_READ_NUMBER ; 0939  CD 36 07     PARSE_DECIMAL_BYTE from input
        CALL TTY_NEWLINE      ; 093C  CD F0 02     MON: LD A,$1D
        DEC C                 ; 093F  0D
L0940:
        INC C                 ; 0940  0C
        JR NZ,L0948           ; 0941  20 05
        CALL TTY_NEWLINE_HL   ; 0943  CD 7F 02     MON: CALL $02F0
        JR L0925              ; 0946  18 DD
L0948:
        LD HL,$0C00           ; 0948  21 00 0C
L094B:
        LD A,(HL)             ; 094B  7E
        CP $C0                ; 094C  FE C0
        JR Z,L0940            ; 094E  28 F0
L0950:
        CP $ED                ; 0950  FE ED
        INC HL                ; 0952  23
        JR NZ,L094B           ; 0953  20 F6
        LD A,(HL)             ; 0955  7E
        CP C                  ; 0956  B9
        JR NZ,L0950           ; 0957  20 F7
        CALL L076D            ; 0959  CD 6D 07
        CALL TTY_SPACE        ; 095C  CD EC 02     MON: LD A,$1C
L095F:
        INC HL                ; 095F  23
        LD A,(HL)             ; 0960  7E
        CP $C0                ; 0961  FE C0
        JR Z,L0940            ; 0963  28 DB
        CP $1F                ; 0965  FE 1F
        JR Z,L096E            ; 0967  28 05
        CALL L02A5            ; 0969  CD A5 02     MON: CP A,$1B
        JR L095F              ; 096C  18 F1
L096E:
        CALL TTY_NEWLINE      ; 096E  CD F0 02     MON: LD A,$1D
        JR L0940              ; 0971  18 CD
;
; Test if RUN Command (32)
;
L0973:
        CP $32                ; 0973  FE 32
        JR NZ,L0935           ; 0975  20 BE        This just loops round to test if LOAD command, possibly not right as this causes infinite loop
; but original scan checks out. So Wrong command hangs the system. And the logic on press a key
; will reset us back into the monitor at this point.
;
; RUN Command
;
        CALL BURP_READ_NUMBER ; 0977  CD 36 07     PARSE_DECIMAL_BYTE from input
        LD DE,$8040           ; 097A  11 40 80
        DEC C                 ; 097D  0D
        PUSH BC               ; 097E  C5
L097F:
        POP BC                ; 097F  C1
        INC C                 ; 0980  0C
L0981:
        PUSH BC               ; 0981  C5
; -----------------------------------------------------------------------------
;
; Main parse  loop
;
; -----------------------------------------------------------------------------
        LD HL,$0C00           ; 0982  21 00 0C     Looks like the main parse of the program. 0C00 is where BURP programs are loaded into.
L0985:
        LD A,(HL)             ; 0985  7E           Get next char in program... Look for end of program of start of line markers
        CP $C0                ; 0986  FE C0        C0 is the end of program marker
        JR Z,L097F            ; 0988  28 F5        Jump here if its all over
L098A:
        CP $ED                ; 098A  FE ED        is it the start of line marker
        INC HL                ; 098C  23           move onto next char
        JR NZ,L0985           ; 098D  20 F6        if not start of line marker or end of program, loop
        LD A,(HL)             ; 098F  7E           Get the line number
        CP C                  ; 0990  B9           C holds the line we are interested in
        JR NZ,L098A           ; 0991  20 F7        if its not loop until we find the right line.
        CALL BURP_LINE_TOKEN  ; 0993  CD 94 07     We are at the right line, parse the opcode BURP_DECODE_LINE_OPCODE A returns the code.
;
; Test if INPUT token
;
        CP $26                ; 0996  FE 26        token $26: parse numeric format specifier (CALL $06BB on following selector byte)
        JR NZ,L09AE           ; 0998  20 14
; ------------------------------------------------------------
; Execute INPUT token
; ------------------------------------------------------------
        CALL PAD_TO_NEXT_LINE ; 099A  CD C4 03
        INC HL                ; 099D  23
L099E:
        LD A,(HL)             ; 099E  7E
        CALL L06BB            ; 099F  CD BB 06
L09A2:
        INC HL                ; 09A2  23
        LD A,(HL)             ; 09A3  7E
        CP $20                ; 09A4  FE 20
        JR Z,L09A2            ; 09A6  28 FA
        CP $1F                ; 09A8  FE 1F
        JR NZ,L099E           ; 09AA  20 F2
        JR L097F              ; 09AC  18 D1
;
; Test if PRINT token
;
L09AE:
        CP $34                ; 09AE  FE 34
        JR NZ,L09D4           ; 09B0  20 22
; ------------------------------------------------------------
; Execute PRINT token
; ------------------------------------------------------------
        CALL PAD_TO_NEXT_LINE ; 09B2  CD C4 03
L09B5:
        INC HL                ; 09B5  23
        LD A,(HL)             ; 09B6  7E
        CP $20                ; 09B7  FE 20
        JR Z,L09B5            ; 09B9  28 FA
        CP $1F                ; 09BB  FE 1F
        JR Z,L097F            ; 09BD  28 C0
        CP $22                ; 09BF  FE 22
        JR NZ,L09CD           ; 09C1  20 0A
L09C3:
        INC HL                ; 09C3  23
        LD A,(HL)             ; 09C4  7E
        CP $22                ; 09C5  FE 22
        JR Z,L09B5            ; 09C7  28 EC
        LD (DE),A             ; 09C9  12
        INC DE                ; 09CA  13
        JR L09C3              ; 09CB  18 F6
L09CD:
        CP $1B                ; 09CD  FE 1B
        CALL C,L05A9          ; 09CF  DC A9 05
        JR L09B5              ; 09D2  18 E1
;
; Parse token 0e
;
L09D4:
        CP $0E                ; 09D4  FE 0E
        JR NZ,L09DB           ; 09D6  20 03
        JP BURP_ENTRY         ; 09D8  C3 00 08
;
; Test if GOTO token - $
;
L09DB:
        CP $1D                ; 09DB  FE 1D
        JR NZ,L09E7           ; 09DD  20 08
; ------------------------------------------------------------
; Execute GOTO token 1D
; ------------------------------------------------------------
        INC HL                ; 09DF  23
        LD A,(HL)             ; 09E0  7E
L09E1:
        CALL L04BA            ; 09E1  CD BA 04
L09E4:
        POP HL                ; 09E4  E1
        JR L0981              ; 09E5  18 9A
;
; Test if LET token - 2C
;
L09E7:
        CP $2C                ; 09E7  FE 2C
        JR NZ,L0A00           ; 09E9  20 15
; ------------------------------------------------------------
; Execute LET token 2C
; ------------------------------------------------------------
        INC HL                ; 09EB  23
        LD B,(HL)             ; 09EC  46
        PUSH BC               ; 09ED  C5
        INC HL                ; 09EE  23
L09EF:
        INC HL                ; 09EF  23
        LD A,(HL)             ; 09F0  7E
        CP $1F                ; 09F1  FE 1F
        JR NZ,L09FB           ; 09F3  20 06
        POP AF                ; 09F5  F1
        CALL MM_OUT_X         ; 09F6  CD 60 04     BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)
L09F9:
        JR L097F              ; 09F9  18 84
L09FB:
        CALL BURP_EXPR_TERM   ; 09FB  CD E6 04
        JR L09EF              ; 09FE  18 EF
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
;
; Test if IF token - 18
;
L0A00:
        CP $18                ; 0A00  FE 18        dispatch: is IF token == $18 ?
        JR NZ,L0A3F           ; 0A02  20 3B        if not token $18, try next statement handler
; ------------------------------------------------------------
; Execute IF Token
; ------------------------------------------------------------
        INC HL                ; 0A04  23           advance to operand selector byte
        LD A,(HL)             ; 0A05  7E           A := operand-block selector
        CALL BURP_EMIT_BLOCK  ; 0A06  CD 7B 05     emit 16-byte operand/descriptor block to MM57109 stream (A selects block)
        INC HL                ; 0A09  23           advance to next token after operand selector
        LD B,(HL)             ; 0A0A  46           B := lookahead token
        INC HL                ; 0A0B  23
        LD A,(HL)             ; 0A0C  7E           A := next token/value
        PUSH BC               ; 0A0D  C5           save BC across expression emit
        CALL BURP_EXPR_TERM   ; 0A0E  CD E6 04     emit next expression token(s) to MM57109 stream (skips spaces etc.)
        POP BC                ; 0A11  C1
        LD A,B                ; 0A12  78           A := lookahead token B
        AND A                 ; 0A13  A7
        CP $3E                ; 0A14  FE 3E
        JR NZ,L0A1D           ; 0A16  20 05        if B == $3E then also emit marker $30
        LD A,$30              ; 0A18  3E 30
        CALL MM_SEND          ; 0A1A  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=$30) ; optional marker
L0A1D:
        LD A,$3A              ; 0A1D  3E 3A        emit separator/marker $3A to MM57109 stream
        CALL MM_SEND          ; 0A1F  CD 2E 04     MM57109_SEND_INSTRUCTION_IN_A(A=$3A)
        LD A,B                ; 0A22  78           choose command byte based on B ($3D ?)
        AND A                 ; 0A23  A7
        CP $3D                ; 0A24  FE 3D
        JR NZ,L0A2C           ; 0A26  20 04
        LD A,$11              ; 0A28  3E 11        if B == $3D use $11 else use $12
        JR L0A2E              ; 0A2A  18 02
L0A2C:
        LD A,$12              ; 0A2C  3E 12        Send MM57109 TXLTO*
L0A2E:
        CALL MM_SEND_TEST     ; 0A2E  CD 8A 05     send $11/$12 and wait for RDY/BR status; returns A&$40 (Z/NZ)
        JR NZ,L09F9           ; 0A31  20 C6        if status bit6 set (NZ), branch to abort/return-to-monitor path
L0A33:
        INC HL                ; 0A33  23           scan forward until reaching a token >= $30 (numeric/identifier region)
        LD A,(HL)             ; 0A34  7E
        CP $30                ; 0A35  FE 30
        JR C,L0A33            ; 0A37  38 FA        loop while token < $30
        JR L09E1              ; 0A39  18 A6        resume main execution/parse loop
L0A3B:
        JR L09F9              ; 0A3B  18 BC        abort/return-to-monitor path
L0A3D:
        JR L09E4              ; 0A3D  18 A5        alternate resume/cleanup path
;
; Test if WRITE token - 33
;
L0A3F:
        CP $33                ; 0A3F  FE 33        is WRITE token?
        JR NZ,L0A7F           ; 0A41  20 3C
; ------------------------------------------------------------
; Execute WRITE token
; ------------------------------------------------------------
        CALL TTY_NEWLINE      ; 0A43  CD F0 02     MON: LD A,$1D
        PUSH DE               ; 0A46  D5
        LD DE,$1DC0           ; 0A47  11 C0 1D
        PUSH DE               ; 0A4A  D5
L0A4B:
        INC HL                ; 0A4B  23
        LD A,(HL)             ; 0A4C  7E
        CP $20                ; 0A4D  FE 20
        JR Z,L0A4B            ; 0A4F  28 FA
        CP $1F                ; 0A51  FE 1F
        JR Z,L0A6A            ; 0A53  28 15
        CP $22                ; 0A55  FE 22
        JR NZ,L0A63           ; 0A57  20 0A
L0A59:
        INC HL                ; 0A59  23
        LD A,(HL)             ; 0A5A  7E
        CP $22                ; 0A5B  FE 22
        JR Z,L0A4B            ; 0A5D  28 EC
        LD (DE),A             ; 0A5F  12
        INC DE                ; 0A60  13
        JR L0A59              ; 0A61  18 F6
L0A63:
        CP $1B                ; 0A63  FE 1B
        CALL C,L05A9          ; 0A65  DC A9 05
        JR L0A4B              ; 0A68  18 E1
L0A6A:
        LD A,$FF              ; 0A6A  3E FF
        LD (DE),A             ; 0A6C  12
        NOP                   ; 0A6D  00
        POP DE                ; 0A6E  D1
L0A6F:
        LD A,(DE)             ; 0A6F  1A
        CP $FF                ; 0A70  FE FF
        JR Z,L0A7C            ; 0A72  28 08
        AND $3F               ; 0A74  E6 3F
        CALL L02A5            ; 0A76  CD A5 02     MON: CP A,$1B
        INC DE                ; 0A79  13
        JR L0A6F              ; 0A7A  18 F3
L0A7C:
        POP DE                ; 0A7C  D1
L0A7D:
        JR L0A3B              ; 0A7D  18 BC
;
; Test if ERASE token - OF
;
L0A7F:
        CP $0F                ; 0A7F  FE 0F        is ERASE token ?
        JR NZ,L0A8B           ; 0A81  20 08
; ------------------------------------------------------------
; Execute ERASE token
; ------------------------------------------------------------
        LD DE,$8040           ; 0A83  11 40 80
        CALL CLEAR_SCREEN     ; 0A86  CD 93 03     MON: PUSH DE;  [MON:CLEAR_SCREEN_8040_87FF]
L0A89:
        JR L0A7D              ; 0A89  18 F2
;
; Test if TOP token
;
L0A8B:
        CP $38                ; 0A8B  FE 38        is TOP token
        JR NZ,L0A9A           ; 0A8D  20 0B
; ------------------------------------------------------------
; Execute TOP token
; ------------------------------------------------------------
        LD DE,$8040           ; 0A8F  11 40 80
        PUSH DE               ; 0A92  D5
        RST $20               ; 0A93  E7
        CALL PAD_TO_NEXT_LINE ; 0A94  CD C4 03
        POP DE                ; 0A97  D1
        JR L0A89              ; 0A98  18 EF
;
; Test if GOSUB
;
L0A9A:
        CP $10                ; 0A9A  FE 10
        JR NZ,L0AA6           ; 0A9C  20 08
; ------------------------------------------------------------
; Execute GOSUB token
; ------------------------------------------------------------
        INC HL                ; 0A9E  23
        LD A,(HL)             ; 0A9F  7E
        CALL L04BA            ; 0AA0  CD BA 04
        PUSH HL               ; 0AA3  E5
L0AA4:
        JR L0A3D              ; 0AA4  18 97
;
; Test if RETURN token
;
L0AA6:
        CP $32                ; 0AA6  FE 32
        JR NZ,L0AAE           ; 0AA8  20 04
; ------------------------------------------------------------
; Execute RETURN token
; ------------------------------------------------------------
        POP BC                ; 0AAA  C1
        NOP                   ; 0AAB  00
        JR L0A3B              ; 0AAC  18 8D
;
; Test if FOR token
;
L0AAE:
        CP $1E                ; 0AAE  FE 1E
        JR NZ,L0ADE           ; 0AB0  20 2C        not FOR -> try next statement type
;------------------------------------------------------------
; Execute FOR token
; -----------------------------------------------------------
; Parse token 1E  -- FOR
; FOR X=... STEP ... UNTIL ...
; Note the Return line number is stored in 1FE3
; BURP does not support embedded FOR loops, only a single loop
; can be active at a time.
; ------------------------------------------------------------
        POP BC                ; 0AB2  C1
        PUSH BC               ; 0AB3  C5           peek/preserve BC (interpreter state)
        INC C                 ; 0AB4  0C           C = current line number -> line after FOR
        LD A,C                ; 0AB5  79
        LD ($1FE3),A          ; 0AB6  32 E3 1F     save "loop body start line" for NEXT 1FE3 is the global address used for this.
        INC HL                ; 0AB9  23
        LD B,(HL)             ; 0ABA  46           B = loop variable token/id (e.g. 'A')
        INC HL                ; 0ABB  23
        CALL L0459            ; 0ABC  CD 59 04     parse/eval the "= <expr>" part
; (calls into expression parser at 04E6)
; Stores the value in the MM57109 X register.

        LD A,B                ; 0ABF  78
        CALL MM_OUT_X         ; 0AC0  CD 60 04     BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)
; (very likely MM57109-side "store into var B")
; Reads the value from the MM57109 X register

        CALL SKIP_WORD        ; 0AC3  CD 52 04     skip ahead to next clause delimiter (space scanning)
        LD A,$1B              ; 0AC6  3E 1B
        CALL MM_OUT_X         ; 0AC8  CD 60 04     BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)
        CALL MM_SEND_INLINE   ; 0ACB  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
        DB $30,$FF                       ; 0ACE  30 FF  MM57109 instructions  XEY
        CALL SKIP_WORD        ; 0AD0  CD 52 04     skip ahead again (toward UNTIL clause)
        CALL MM_SEND_INLINE   ; 0AD3  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
        DB $30,$3A,$30,$3C,$1C,$FF       ; 0AD6  30 3A 30 3C 1C FF  likely compiles UNTIL value + compare/jump micro-sequence,  MM57109 instructions  XEY,-,XEY,/,MS
L0ADC:
        JR L0A7D              ; 0ADC  18 9F        back to main statement dispatch loop
;
; Test if  NEXT token
;
L0ADE:
        CP $30                ; 0ADE  FE 30
        JR NZ,L0B0F           ; 0AE0  20 2D
; ------------------------------------------------------------
; Execute NEXT token
; ------------------------------------------------------------
        CALL MM_SEND_INLINE   ; 0AE2  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 0AE5-0AE6 terminated by $FF
        DB $1D,$FF                       ; 0AE5  1D FF  MR (M <-> X) Loop counter is held in memory register M
        LD A,$13              ; 0AE7  3E 13        Load the TXF* instruction into A, Branch if X < 0 MM57109 instruction
        CALL MM_SEND_TEST     ; 0AE9  CD 8A 05     MM57109_SEND_AND_WAIT_RDDY_BR(A=byte) -> A&$40, Z/NZ indicates bit6
        JR Z,L0ADC            ; 0AEC  28 EE
        INC HL                ; 0AEE  23
        LD A,(HL)             ; 0AEF  7E
        PUSH AF               ; 0AF0  F5
        CALL BURP_EMIT_BLOCK  ; 0AF1  CD 7B 05
        LD A,$1B              ; 0AF4  3E 1B
        CALL BURP_EMIT_BLOCK  ; 0AF6  CD 7B 05
        CALL MM_SEND_INLINE   ; 0AF9  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 0AFC-0AFD terminated by $FF
        DB $39,$FF                       ; 0AFC  39 FF  "<39>"
        POP AF                ; 0AFE  F1
        CALL MM_OUT_X         ; 0AFF  CD 60 04     BURP_EMIT_MM57109_OUT_INSTRUCTION_AND_WAIT(A=selector)
        CALL MM_SEND_INLINE   ; 0B02  CD 46 04     BURP_SEND_INLINE_MM57109_INSTRUCTIONS_UNTIL_FF(inline @ retaddr)
; Inline data for CALL $0446: bytes 0B05-0B08 terminated by $FF
        DB $01,$20,$3A,$FF               ; 0B05  01 20 3A FF  "A :"
        LD A,($1FE3)          ; 0B09  3A E3 1F     Get the line to loop back to, this was saved by the FOR handler.
; It holds the next line after the FOR line was on.
; NOTE only a single FOR loop can be active at a time (no embedded loops using FOR statements)
        LD C,A                ; 0B0C  4F
        JR L0AA4              ; 0B0D  18 95
;
; Parse token 24
;
L0B0F:
        CP $24                ; 0B0F  FE 24
        JR NZ,L0B14           ; 0B11  20 01
; ------------------------------------------------------------
; Execute HALT token
; ------------------------------------------------------------
        HALT                  ; 0B13  76
; ------------------------------------------------------------
; Anything else is treated as a comment and ignored I think
; ------------------------------------------------------------
L0B14:
        JR L0ADC              ; 0B14  18 C6
        LD DE,$8040           ; 0B16  11 40 80
        LD HL,$1FE4           ; 0B19  21 E4 1F
        PUSH DE               ; 0B1C  D5
        PUSH HL               ; 0B1D  E5
        LD B,$02              ; 0B1E  06 02
L0B20:
        LD A,R                ; 0B20  ED 5F
        CALL L0BAB            ; 0B22  CD AB 0B
        DJNZ L0B20            ; 0B25  10 F9
L0B27:
        EX DE,HL              ; 0B27  EB
        POP HL                ; 0B28  E1
        LD BC,$0004           ; 0B29  01 04 00
        LDIR                  ; 0B2C  ED B0
        EX DE,HL              ; 0B2E  EB
        POP DE                ; 0B2F  D1
        LD B,$02              ; 0B30  06 02
L0B32:
        CALL READ_HEX_BYTE    ; 0B32  CD E7 03     MON: CALL $03F6;  HEXBYTE: read 2 hex digits -> A
        CALL L0BAB            ; 0B35  CD AB 0B
        DJNZ L0B32            ; 0B38  10 F8
        RST $20               ; 0B3A  E7
        CALL L0BA0            ; 0B3B  CD A0 0B
L0B3E:
        LD A,(DE)             ; 0B3E  1A
        CP (HL)               ; 0B3F  BE
        JR NZ,L0B47           ; 0B40  20 05
        CPL                   ; 0B42  2F
        LD (DE),A             ; 0B43  12
        LD (HL),$EE           ; 0B44  36 EE
        INC C                 ; 0B46  0C
L0B47:
        INC DE                ; 0B47  13
        INC HL                ; 0B48  23
        DJNZ L0B3E            ; 0B49  10 F3
        LD A,C                ; 0B4B  79
        EXX                   ; 0B4C  D9
        CP $34                ; 0B4D  FE 34
        JR Z,L0B97            ; 0B4F  28 46
        LD (DE),A             ; 0B51  12
        INC DE                ; 0B52  13
        CALL PRINT_INLINE     ; 0B53  CD CE 03     MON: EX (SP),HL;  HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0B56-0B5F terminated by $1D
        DB $20,$02,$0C,$01,$03,$0B,$13,$2C; 0B56  20 02 0C 01 03 0B 13 2C  " BLACKS, "
        DB $20,$1D                       ; 0B5E  20 1D
        CALL L0BA0            ; 0B60  CD A0 0B
        EX DE,HL              ; 0B63  EB
L0B64:
        LD A,(DE)             ; 0B64  1A
        CP $10                ; 0B65  FE 10
        JR NC,L0B77           ; 0B67  30 0E
        CP (HL)               ; 0B69  BE
        JR NZ,L0B71           ; 0B6A  20 05
        INC C                 ; 0B6C  0C
        LD (HL),$DD           ; 0B6D  36 DD
        CPL                   ; 0B6F  2F
        LD (DE),A             ; 0B70  12
L0B71:
        INC HL                ; 0B71  23
        LD A,L                ; 0B72  7D
        CP $EC                ; 0B73  FE EC
        JR NZ,L0B64           ; 0B75  20 ED
L0B77:
        INC DE                ; 0B77  13
        LD L,$E8              ; 0B78  2E E8
        DJNZ L0B64            ; 0B7A  10 E8
        LD A,C                ; 0B7C  79
        EXX                   ; 0B7D  D9
        LD (DE),A             ; 0B7E  12
        INC DE                ; 0B7F  13
        CALL PRINT_INLINE     ; 0B80  CD CE 03     MON: EX (SP),HL;  HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0B83-0B8A terminated by $1D
        DB $20,$17,$08,$09,$14,$05,$13,$1D; 0B83  20 17 08 09 14 05 13 1D  " WHITES"
        CALL PAD_TO_NEXT_LINE ; 0B8B  CD C4 03
        LD HL,$1FE4           ; 0B8E  21 E4 1F
        PUSH DE               ; 0B91  D5
        PUSH HL               ; 0B92  E5
        LD L,$E8              ; 0B93  2E E8
        JR L0B27              ; 0B95  18 90
L0B97:
        CALL PRINT_INLINE     ; 0B97  CD CE 03     MON: EX (SP),HL;  HL <- return address (string ptr), [SP] <- old HL [MON:STR_PRINT_HL_AT_RETADDR]
; Inline data for CALL $03CE (MON:STR_PRINT_HL_AT_RETADDR): bytes 0B9A-0B9E terminated by $1D
        DB $19,$05,$13,$21,$1D           ; 0B9A  19 05 13 21 1D  "YES!"
        RST $00               ; 0B9F  C7
L0BA0:
        EXX                   ; 0BA0  D9
        LD BC,$0430           ; 0BA1  01 30 04
        LD DE,$1FE8           ; 0BA4  11 E8 1F
        LD HL,$1FEC           ; 0BA7  21 EC 1F
        RET                   ; 0BAA  C9
L0BAB:
        AND $77               ; 0BAB  E6 77
        LD (HL),A             ; 0BAD  77
        XOR A                 ; 0BAE  AF
        RRD                   ; 0BAF  ED 67
        INC HL                ; 0BB1  23
        LD (HL),A             ; 0BB2  77
        INC HL                ; 0BB3  23
        RET                   ; 0BB4  C9
        DB $ED,$05                       ; 0BB5  ED 05  not a documented instruction
        LD B,$0F              ; 0BB7  06 0F
        LD (DE),A             ; 0BB9  12
        JR NZ,L0BBD           ; 0BBA  20 01
        DEC A                 ; 0BBC  3D
L0BBD:
        LD SP,$1320           ; 0BBD  31 20 13
        INC D                 ; 0BC0  14
        DEC B                 ; 0BC1  05
        DJNZ L0BE4            ; 0BC2  10 20
        LD SP,$1520           ; 0BC4  31 20 15
        LD C,$14              ; 0BC7  0E 14
        ADD HL,BC             ; 0BC9  09
        DB $0C,$20                       ; 0BCA  0C 20
        LD ($2035),A          ; 0BCC  32 35 20
        RRA                   ; 0BCF  1F
        DB $ED,$06                       ; 0BD0  ED 06  not a documented instruction
        INC C                 ; 0BD2  0C
        DEC B                 ; 0BD3  05
        INC D                 ; 0BD4  14
        JR NZ,L0BE3           ; 0BD5  20 0C
        DEC A                 ; 0BD7  3D
        LD BC,$0C20           ; 0BD8  01 20 0C
        RRCA                  ; 0BDB  0F
        RLCA                  ; 0BDC  07
        JR NZ,$0BFE           ; 0BDD  20 1F
        DB $ED,$07                       ; 0BDF  ED 07  not a documented instruction
        DJNZ $0BF5            ; 0BE1  10 12
L0BE3:
        ADD HL,BC             ; 0BE3  09
L0BE4:
        DB $0E,$14                       ; 0BE4  0E 14
        JR NZ,$0BE9           ; 0BE6  20 01
        JR NC,$0C0A           ; 0BE8  30 20
        INC C                 ; 0BEA  0C
        JR C,$0C0D            ; 0BEB  38 20
        RRA                   ; 0BED  1F
        DB $ED,$08                       ; 0BEE  ED 08  not a documented instruction
        LD C,$05              ; 0BF0  0E 05
        JR $0C08              ; 0BF2  18 14
        JR NZ,$0BF7           ; 0BF4  20 01
        JR NZ,$0C17           ; 0BF6  20 1F
        DB $ED,$09                       ; 0BF8  ED 09  not a documented instruction
        DEC B                 ; 0BFA  05
        LD C,$04              ; 0BFB  0E 04
        JR NZ,$0C1E           ; 0BFD  20 1F
        RET NZ                ; 0BFF  C0
