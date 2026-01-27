To switch to BURP make sure in READY state (press ESC to do a RESET), then type the RS character (on mac shift CMD ^).

Table 5 lists the BURP statements, and
able 6 gives the mathematical expres-
sions for LET statements. With the
computer in the READYstate, type
```
MOV 0BB5 OCOO OCOO
```
and then change to the high level
language by pressing RS on the key-
board. The word READY will then be
replaced by BURP.The RS key types in
RUN. 0800, and initiates the high level
system. The low level MOV command
movesthe sample program in r.o.m. out
into the r/w.m., where it can be
examined by typing
```
LIST 5
```
which gives
```
005 FORA=1 STEP 1 UNTIL 25—
006 LETL=A LOG—
007 PRINTA0L8-
008 NEXTA-
009 END—
OC4A
```
The dash shows where a line ends and
virtually every term, including the last
on each line, is followed by a space. The
address 0C4A gives the upper limit of
the program storage currently in use,
and from 0C00 up to 1DC0 is available.
Nowtype
```
RUN 5
```
The computer should print the common
logarithms of the numbers 1 to 25.
When it has finished, the computer is
ready for a command, indicated when-
ever BURP is the only word on the top
line. Type
```
DEL 6
```
and the program will list out with line
number 6 deleted. Note that the end
address is now 0C3B, i.e. when lines are
deleted, the computer reworks the
remaining lines back towards the start
of the memory space. This makes best
use of the memory and stops the build
up of rubbish within the memory which
would slow down the program execu-
tion. Next,
```
ADD
6 LET L=A ROOT
```
After typing the colon the word ADD
will disappear, i.e. you are back in com-
mand. Thecolon is necessary at the end
of an ADD or a LOAD because it inserts
the hex byte CO at the end of the pro-
gram block. This code tells the com-
puter where to stop and go back from,
when it is scanning through the
memory. Now,
```
RUN 5
```
which will list out the square roots of
the numbers 1 to 25. Then,
```
DEL 6
ADD
6 LET L=A EX
RUN 5
```
This program lists the natural anti-logs,
e^x of the numbers 1 to 25, and will show
how the display switches over to scien-
tific notation, the last result being
72004907x10^10 Although mathemati-
cally correct, these are rather crude
presentations ofthe results. Type
```
ADD
4 PRINT " X EXP X”
RUN 4
```
which adds a heading above each of the
columns, or,
```
DEL 7
ADD
7 PRINT “THE NATURAL .ANTI-LOG OF” AO, “ IS”L4
RUN 5
```
which gives a different display format,
see Table 7. Note that the comma after
AO suppressed the characters after the
decimal point, rather than leaving a
large gap. L4 means L, printed to 4
decimal figures, although without the
compaction ofthe scientific results that
a comma would bring. Try
```
DEL 7
ADD
7 PRINT “THE NATURAL ANTI-LOG OF”AO “ IS”L4,
RUN 5
```
to see the difference. If you make a
mistake in these exercises, just termin-
ate the line with a RETURN and type it
in again. It is important, as already
explained, that the LOAD and ADD
commands are only left with a colon,
do not be tempted to do so with an RS. If
you have corrected a line in this way,
when back in the command state, delete
that line, and the computer will erase
the first line it comes to with that
number and then re-list with the
second version in the correct place.
Naturally, if you have mis-typed a line
twice or more, this deleting procedure
must be repeated until the correct line
appears in place. The running of a pro-
gram may be halted at any time by
pressing any key on the keyboard, but
as this returns the computer to the
low-level, READY state, follow it with
an RS for BURP.

| Statement | Description |
|-----------|-------------|
|INPUT A B etc | Inputs and assigns one or more variables. |
|LET X=A SIN SQ etc | Assigns the value computed in the expression following the = sign to X.|
|IF X=Y THEN 50 | If the condition (which may be <’, = or >) is met.then go to-line 50. Otherwise, continue.|
|FOR X=1 STEP B UNTIL C | X takes the value 1 the lines up to the line NEXT X are then executed. X is then increased by B and the lines executed again, and this continues until X is greater or equal to C. at which point the computer carries on|
| NEXT X | through the line NEXT Xto the next one|
| GOSUB 200|Goes to line 200 and executes from there until the line RETURN is found, and then returns|
|RETURN |to the line following GOSUB. GOSUBs may appear within GOSUB blocks|
|HALT | Halts execution until any key is pressed.|
|TOP | Clears, and resets the PRINT position to. the top line of the display area.|
|ERASE | As TOP. but it clears the whole display area.|
|END| Stops execution and returns to the commandstate.|
|GO 25 or GOTO 25 |Executes from line 25|
|WRITE|As PRINT for the second output device.|
|PRINT| see next lines/ In prints, the following may appear|
|An|A. printed with n figures after the decimal point and then spaces for the blanked characters, 13 in all. For less than an 8 digit mantissa, the last figure is rounded if necessary |
|A|A. printed with the same number of figures after the decimal point as the previously printed variable or if it is the first one to be printed, to four figures. This four can be altered in r.o.m. location 0818 by programming 01 to 07 in place of the 04 |
|An |As An  but with the blanked figures completely suppressed and. if the number is in scientific notation, with the exponent and exponent sign against the mantisa |
|A |As A. but with the suppression described above|

Summarising, without the comma, printed figures always occupy 13 screen locations and thus columns of results will be tabulated no matter what the magnitude of the number. With the comma, alphanumeric data (see below) and variables may be printed in the same line without large gaps appearing.

| Statement | Description |
|-----------|-------------|
|"PRINTED TEXT"|Prints the actual characters within the quotes. implying that quotes must not appear in the string of characters|

It is not possible to have a second (or subsequent) FOR  NEXT block within a FOR  NEXT block, because the single on-chip memory in the MM57109 is used as a loop counter in conjunction with the NEXTl ine. These loops, if required, can be set up using for example, in place of the FOR line given.


```
20 LET X = 1       -replaces the FOR
21
22                 - lines within FOR and NEXT
23
24 LET X=X B +
25 IF X<C THEN 21  -replaces the NEXT
```