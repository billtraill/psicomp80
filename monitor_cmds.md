| Command | Description |
|---------|-------------|
| ALPH | Produces an alphanumeric test pattern on the v.d.u. |
| ALT XXXXYY | Changes the contents of location XXXX to YY. Having accepted the alteration, the computer lists out from the previous LIST command starting address. Normally, a LIST of the area in which the alteration is to take place will have beencarried out immediately prior to using ALT. and so the altered byte will change to its correct contents on the v.d.u. screen as well as in the memory. After an alteration, the computer does not return to the commandstate, but waits for any further alterations, typed in as XXXXYY and so on. To return to the commands tate, type FS or press RESET. |
| COR XXXX YYYY AA BB | Scans XXXX to YYYY-1 inclusive and alters any AA to BB |
| FILL XXXX | If less than 256 bytes are to be programmed into an e.p.r.o.m. sector, and the other must be left blank for later additions to the e.p.r.o.ms contents, or, if you wish to add this later bit to an already partly filled e.p.r.o.m., FFs must be present at the byteswhich are not to beprogrammed. This can be achieved by using the extra command FIL.. XXXX, which will fill from XXXX to the next YY00 with FFs. either before toadlng Into the p.r.o.m. area. or. after loading, to maskoff the other unused bytes up to 1CFF. This command also makes programs easier to study on the v.d.u. as it can be used to mask off the rubbish following a program.|
| FIND XX YY | Finds the consecutive bytes XX YY and lists the addresses at which they occur |
| LIST XXXX | Lists the contents of the memory from address XXXX upto a full v.d.u. screen. |
| LOAD XXXX | Loads hexadecimal data at XXXX. using the same display format as in list. Toload ASCII directly, type a [ and to return type a ] after which, the computer gives the next byte's address and continues to load hexadecimal data. To leave LOAD, type @which gives a full listing of what has just been loaded, or press RESET or the FS key to regain command. |
| MOV XXXXYYYYZZZZ | Moves the block XXXX to YYYY-1 inclusive to the area of memory beginning with the address ZZZZ. |
| PRINT XXXX | Lists from XXXX on the second output device |
| PROM | Used in conjunction with the e.p.r.o.m. programmer, this programs the block of data at 1 COO to 1 CFF inclusive into the sector of the 2708 selected on the programmer. |
| READ XXXX | Reads from tape into memory, starting at location XXXX. READ must, be terminated by pressing any key. once the tape has been read in. |
| RUN XXXX | Runs from address XXXX. |
| TAPE XXXXYYYY | Records, on tape, a short leader of stop bits, followed by the data at locations XXXX to YYYY-1 inclusive and a short trailer of stop bits. |

Notes
1. Takecare when using MOV. `MOV 1DOO 1E00 1CFF` will work, and move the block 1D00 to 1DFF
inclusive, forward one byte in memory, but `MOV 1DOO 1E00 1D01` will copy 1DOO into 1D01
then 1D01 into 1D02 etc., leaving you with a block of identical characters and your original data lost.
While this can sometimes be useful for filling out a block with a particular byte, to do this properly requires a MOV of the block to a separate, vacant, area and then a MOV to 1DO1
2. The PROM commandtakes about 40s to program the e.p.r.o.m. sector completely, and during
this time the computer is fully occupied.
3. If less than 256 bytes are to be programmed into an e.p.r.o.m. sector, and the other must be left blank for later additions to the e.p.r.o.ms contents, or, if you wish to add this later bit to an already partly filled e.p.r.o.m., FFs must be present at the byteswhich are not to beprogrammed. This can be achieved by using the extra command FIL XXXX, which will fill from XXXX to the next YY00 with FFs. either before loading Into the p.r.o.m. area. or after loading, to maskoff the other unused bytes up to 1CFF. This command also makes programs easier to study on the v.d.u. as it can be used to mask off the rubbish following a program.
4. When loading ASCII, do not try to include a ] in the string of characters as it will terminate your ASCII mode of loading. Also, do not type in anyfurther [ as these will be used in a future adaption to graphics, whose firmware is already in the 2708. Ordinary parentheses, (and) are quite acceptable to the computer.
