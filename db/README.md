# COMP80 FILE

[Run FILE in the web emulator](https://billtraill.github.io/psicomp80/emulator.html#rom=db). Each example below has a ▶ link that types it in and runs it there.

A card-file database for the PSI COMP80, of the kind small computers ran for
address books and club lists. It takes BURP's place in the ROM and was
written from scratch for this machine. The monitor (0000-03FF) is unchanged,
and FILE sits in the 2 KB at 0400-0BFF where BURP was. As with BURP, you
enter it with the RS key from the monitor's READY state. It uses 2033 of the
2048 bytes.

You name the fields once, type the cards in a line each, and then list them
as a table, pick some out with WHERE, search them, sort them, and add up a
field.

## Running it

`build.sh` makes `../psicomp80_db.rom`. Once the MAME driver has it as a
BIOS option (`-bios db`), press `^` (RS) at READY. The top line changes to
COMP80 FILE, and `OK` and a `_` cursor appear. Type a command and press
Return.

## Example programs

`examples/` has three files to type in. Each starts with `NEW` and
`FIELDS`, then adds the cards:

| | |
|---|---|
| `address.db` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=dbaddress) | An address book: name, town and phone for seven people. Try `SORT BY NAME`, `LIST`, `FIND 0113` and `LIST WHERE TOWN=Y*`. |
| `records.db` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=dbrecords) | A record collection: title, artist, year, format and price. Try `SORT BY YEAR`, `LIST WHERE YEAR<1970 AND FORMAT=LP`, `SUM PRICE`, `AVG PRICE` and `SHOW 5`. |
| `club.db` [▶](https://billtraill.github.io/psicomp80/emulator.html#example=dbclub) | A club's members: name, age, year joined, fee and whether it is paid. Try `COUNT WHERE PAID=NO`, `SUM FEE WHERE PAID=NO`, `AVG AGE`, `SORT BY AGE DESC` and `DELETE WHERE PAID=NO`. |

## Keys

| Key | What it does |
|---|---|
| Return | run the line |
| `^` (RS) | rub out the last character. At any other time it restarts FILE with the cards kept. |
| Ctrl+`\` (FS) | back to the monitor |
| any key while a command runs | resets to the monitor; RS comes back with the cards kept |

## Commands

Only the first three letters of a command count, so `LIS` is `LIST`.

| Command | |
|---|---|
| `FIELDS NAME,TOWN,AGE` | names the fields, up to 8. The cards are kept, so this also renames them. |
| `ADD SMITH,LEEDS,42` | adds a card at the end. Fields are separated by commas; a card with too few gets empty ones added. |
| `LIST` | all the cards as a table: the card number, then each field in a column. The columns are as wide as the widest entry, up to 24 characters, and narrowed until the table fits in 64 columns; longer entries are cut short. |
| `LIST WHERE ...` | only the cards that match |
| `FIND TEXT` | the cards with TEXT anywhere in them, spaces and all |
| `SHOW n` | card n, a field to a line |
| `SORT BY FIELD`, `SORT BY FIELD DESC` | sorts the cards, upwards or downwards |
| `COUNT [WHERE ...]` | how many cards |
| `SUM FIELD [WHERE ...]` | adds up a field |
| `AVG FIELD [WHERE ...]` | the sum divided by the number of cards |
| `DELETE n` | deletes card n; the cards after it move up a number |
| `DELETE WHERE ...` | deletes the cards that match, and says how many |
| `NEW` | no fields and no cards |

`WHERE` takes up to four conditions, `FIELD op VALUE`, joined by `AND` or
`OR` and worked out from left to right. `op` is `=`, `<`, `>`, `<>`, `<=` or
`>=`. A value can't contain a space, and a `*` at the end of it matches any
ending, so `NAME=S*` is the names starting with S.

Two fields that are both numbers compare as numbers, and anything else
compares as text. A number may have a minus sign and up to two decimals; SUM
and AVG work in hundredths, in 32 bits, and print two decimals unless the
answer is a whole number. An empty field counts as the number 0, so it sorts
first and is counted by AVG.

Errors are `WHAT?`, `FIELD?` (no such field, or no fields yet), `NO CARD`
and `FULL`.

## Memory

| Address | |
|---|---|
| 0C00 | 0F11Eh when the file below is valid, so RS keeps it |
| 0C02 | the end of the cards |
| 0C04 | the number of fields |
| 0C05-0C3F | the field names, `NAME,TOWN,AGE` and 0Dh |
| 0C40-1BFF | the cards, a line each, as typed: the fields with commas between them and 0Dh at the end |
| 1D00 | input line |
| 1DA0 | cursor position (1Fh is shown there while waiting for a line), then the working variables, the column widths and the WHERE conditions |
| 1E00 | a card being swapped by SORT |

There are 4032 bytes for cards, about 140 cards of 28 characters. The
32 KB expansion isn't used.

As the whole file is in 0C00 up to the end of the cards, the monitor can
save it to tape: look at the word at 0C02 (`LIST 0C02`; it is stored low byte
first), then FS and `TAPE 0C00xxxx` with that address. `READ 0C00` and RS
bring it back.

## How it works

The commands are looked up in a table of three-letter names. WHERE is read
once into a list of conditions, each a field number, a mask of the outcomes
that make it true (less 1, equal 2, greater 4, so `<>` is 5 and `<=` is 3)
and a pointer to its value, which is ended in the input line itself. Each
card is then compared field by field: `pnum` reads a field as a number in
hundredths and fails if anything but a number is there, and if either side
fails the fields are compared as text.

SORT is a bubble sort that swaps cards next to each other, going through
the file until a pass swaps none. A swap copies the first card to a buffer,
moves the second down and copies the first after it, so only the two cards
move. A file already in order takes one pass; 141 cards in reverse order
take about 50 s.

Left out to fit in 2 KB: changing one field of a card (DELETE it and ADD it
again, then SORT), typing a card field by field, and a SAVE command.

## Tests

`tests/` has session files for `../web/tools/session.js` and MAME:
- `address.txt`, `records.txt`, `club.txt`: each example typed in and its
  queries run
- `basic.txt`: conditions with AND, OR, `<>`, `>=` and `*`, COUNT, SUM and
  AVG with decimals, FIND, sorting numbers, and the errors
- `wide.txt`: six fields with long entries, narrowed to fit, and a card
  with fields missing

The final screens are the same in the JS emulator and in MAME.
