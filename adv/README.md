# COMP80 QUEST

An adventure engine with its own little language, written for the PSI
COMP80 in the 2 KB of ROM (0400–0BFF) where BURP was. The monitor is
unchanged. RS at READY enters it; the top line shows QUEST. You type a world
in a line at a time, then `PLAY` it.

    sh adv/build.sh      # adv.bin and ../psicomp80_adv.rom

`adv.asm` uses 1992 of the 2048 bytes.

## The world

Each line starts with one of five words:

| Line | |
|---|---|
| `ROOM name description` | a room. The first ROOM typed is where the game starts. |
| `EXIT room direction room [IF flag]` | a way from one room to another, usable only while the flag is set if it has `IF flag` |
| `OBJ name room description` | something that can be carried |
| `FIX name room description` | something that can't |
| `ON verb [noun] [IF condition AND condition …] THEN action; action …` | a rule |

Conditions are `HAVE obj` (carried), `HERE obj` (carried or in this room),
`AT room`, a flag's name (true once `SET`), and `NOT` in front of any of them.

Actions, separated by `;`:

| Action | |
|---|---|
| `SAY text` | prints the text, up to the `;` or the end of the line |
| `SET flag` | sets a flag; flags start unset |
| `MOVE obj room` | puts an object in a room; `ME` means carried, and a word that is no room's name takes it out of the game |
| `GO room` | moves the player there and describes it |
| `SCORE n` | adds n to the score |
| `WIN`, `DIE` | ends the game, showing the score |
| `LOOK` | describes the room again |

Words are matched by their first 4 letters, as in the adventures of the
1970s. A one-letter direction or verb in the world matches any word that
starts with that letter, so `EXIT HALL N KITCHEN` is taken by N, NORTH or
GO NORTH. An object that starts in no room (`OBJ KEY NOWHERE …`) can be
brought in later with `MOVE`.

Other commands: `PLAY`, `LIST` (the world as typed), `UNDO` (forgets the
last line) and `NEW`. Any other line gets `WHAT?`. A line can be up to 150
characters. The world survives a reset: RS comes back to it.

## Playing

A command is a verb and a noun. QUEST tries, in order:

1. the rules for the verb: the first whose noun matches (or that has none)
   and whose conditions hold runs, and nothing else happens;
2. the built-in verbs: `LOOK` (`L`), `INVENTORY` (`I`), `TAKE` (`GET`),
   `DROP`, `SCORE` and `QUIT`, which goes back to typing the world;
3. the exits from the room.

`GO` is dropped (GO NORTH is NORTH). Otherwise it says NO WAY for a one-letter
word and WHAT? for anything else. Rules come first, so a rule can stop a
built-in verb: `ON D IF AT MILL AND NOT LIT THEN SAY IT IS TOO DARK.` A
second rule for the same verb, without conditions, is the "otherwise".

Each room is described with what is in it (`YOU SEE …`) and its usable exits.
Descriptions wrap at word boundaries.

## How it works

The world is kept as it was typed, each line ending in Return, from 0C04 to
the end of the text (at most 1BFF, about 4 KB). PLAY makes a table of the
objects, each the line it is on and where it is now: a pointer to a room's
name in the text, or 0 when carried. The flags are a table of pointers to
their names. Rooms, exits and rules are read from the text as they are
needed, so the text itself never changes, and LIST still shows what was
typed. The current room is just a pointer to a word, and two places are the
same if their words are.

A world can have about 4 KB of text, 32 objects and 32 flags; exits and rules
are limited only by the text. The three examples are 700–1300 bytes each.

Memory:

| | |
|---|---|
| 0C00 | magic word, when the world is valid |
| 0C02 | end of the text |
| 0C04–1BFF | the world's text |
| 1C00–1C7F | objects: line, where (4 bytes each) |
| 1C80–1CBF | flags: name (2 bytes each) |
| 1D00 | input line |
| 1DA0 | cursor (1Fh at it while waiting for a line) |
| 1DA2–1DB3 | counts, state, score, the room, the words typed |
| 1F00 | top of the stack |

Keys and screen are handled as in COMP80 FORTH. `^`, `_` and `\` can't be
typed. Any key while QUEST is busy resets to the monitor; RS comes back with
the world kept (but the game in progress is lost: PLAY starts it again).

## Examples

`examples/` has three original adventures, each a file of lines to type in:

| | |
|---|---|
| `tutor.adv` | three rooms: find the crank and wind the stopped clock. TAKE CRANK, N, WIND CLOCK. |
| `lab.adv` | lost in the computer lab: open the drawer, unlock the store room (an exit with IF), fit the fuse and load the tape to bring the COMP80 back. 30 points. |
| `mill.adv` | an old watermill with a dark cellar that needs a lit lamp, a locked chest, a river not to swim in, and a score. 45 points. |

## Tests

`tests/` has one session per example, typing the world and playing it to the
win, and `basics.txt` (errors, UNDO, LIST, the built-in verbs, QUIT, DIE,
NEW). They give the same screens in `web/tools/session.js` and in MAME.
