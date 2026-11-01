# The firmware's machine code (Z80, COMP80, MM57109, tape) built for the host,
# for testing against the web emulator.  make test compares every LISP and
# FORTH test's screens with web/tools/session.js.
CFLAGS = -O2 -Wall -Wextra -Wno-unused-parameter -std=c11 -D_DEFAULT_SOURCE
SRC = session.c ../src/z80.c ../src/comp80.c ../src/mm57109.c ../src/tape.c

session: $(SRC) ../src/*.h
	$(CC) $(CFLAGS) -o $@ $(SRC) -lm

test: session
	sh compare.sh

clean:
	rm -f session
