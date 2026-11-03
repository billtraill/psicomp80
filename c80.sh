#!/bin/sh
# Start the PSI COMP80 emulator straight into a program.
#   ./c80.sh [32k] <program> [extra MAME options]
# 32k runs the machine with the 32 KB memory expansion (psicomp80x), which the
# disc FORMAT command needs.
# Monitor programs, copied into memory and run (no tape load needed):
#   life plasma dump fire banner boat schmitt cover; alph and list run the
#   monitor commands; disk loads the disc software at 1D00 with
#   disk/programs.img in the drive.
# Languages: forth, lisp, basic, logo, focal, pilot, zasm, prolog, chip8, vtl,
# mouse, befunge, sheet, trac, pl0, bf, ed, db, adv and apl boot that ROM and
# enter it.
# FORTH programs from forth/examples, typed in and run: forthlife mandel
#   forthsier forthhilbert forthhanoi forthdragon forthkoch forthant
#   forthsieve forthballs forthstars snake forthmaze forthrule forthfern
#   forthchaos forthliss forthclock forthsort
# LISP programs from lisp/examples: deriv hanoi queens lispsier lisphilbert
#   eliza simp perms fib animal unify eval river roman
# The new languages' examples, typed in and run: basicguess basicprimes
#   basiclines basicworm, logoflower logospiral logotree logoflake logostars,
#   focalroots focaltemp focalinterest focalguess focalsine, pilotgreet
#   pilotquiz pilottables pilotstory pilotdraw, prologfamily prologlists
#   prologcolour prologpath; CHIP-8 programs copied to 0E00 and run:
#   c8bounce c8keys c8dodge c8kaleido.
# The Other languages' examples: vtlprimes vtlguess vtlfib vtlcircles
#   vtlchaos, mousefib mousefact mousesieve mouseguess mousecircles, befhello
#   befcount beffact befstars, sheetbudget sheetinterest sheettimes sheettemp,
#   trachello tracfact tracrev tracletter, pl0squares pl0primes pl0gcd pl0fact
#   pl0rings, bfhello bfcount bfadd bfalpha bfreverse bffib, edletter edlist
#   edsearch edview, dbaddress dbrecords dbclub, advtutor advlab advmill,
#   aplbasics aplprimes apltable aplstats aplhist aplpascal.
# ready just starts at READY.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
MAME=${MAME_DIR:-$HOME/localdev/mame}
machine=psicomp80
if [ "$1" = 32k ]; then machine=psicomp80x; shift; fi
prog=${1:-ready}; [ $# -gt 0 ] && shift
addr=1000
script=$HERE/start.lua
forth=
lisp=
curs=

case "$prog" in
  life)    bin=$HERE/life/life.bin;        typed="RUN 1000" ;;
  plasma)  bin=$HERE/plasma/plasma.bin;    typed="RUN 1000" ;;
  dump)    bin=$HERE/dump/dump.bin;        typed="RUN 1000" ;;
  fire)    bin=$HERE/fire/fire.bin;        typed="RUN 1000" ;;
  banner)  bin=$HERE/banner/banner.bin;    typed="RUN 1000" ;;
  boat)    bin=$HERE/pictures/boat.bin;    typed="RUN 1000" ;;
  schmitt) bin=$HERE/pictures/schmitt.bin; typed="RUN 1000" ;;
  cover)   bin=$HERE/pictures/cover.bin;   typed="RUN 1000" ;;
  alph)    bin=;                           typed="ALPH " ;;
  list)    bin=$HERE/life/life.bin;        typed="LIST 1000" ;;
  disk)    bin=$HERE/disk/fdos.bin;        typed="RUN 1D00"; addr=1D00
           set -- -flop "$HERE/disk/programs.img" "$@" ;;
  forth)   bin=;                           typed=
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthlife) bin=; forth=$HERE/forth/examples/life.fs; typed="1000 LIFE"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  mandel)  bin=; forth=$HERE/forth/examples/mandel.fs; typed="MANDEL"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthsier) bin=; forth=$HERE/forth/examples/sier.fs; typed="SIER"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthhilbert) bin=; forth=$HERE/forth/examples/hilbert.fs; typed="HILBERT"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthhanoi) bin=; forth=$HERE/forth/examples/hanoi.fs; typed="6 HANOI"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthdragon) bin=; forth=$HERE/forth/examples/dragon.fs; typed="DRAGON"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthkoch) bin=; forth=$HERE/forth/examples/koch.fs; typed="KOCH"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthant) bin=; forth=$HERE/forth/examples/ant.fs; typed="ANT"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthsieve) bin=; forth=$HERE/forth/examples/sieve.fs; typed="SIEVE"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthballs) bin=; forth=$HERE/forth/examples/balls.fs; typed="BALLS"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthstars) bin=; forth=$HERE/forth/examples/stars.fs; typed="STARS"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  snake)   bin=; forth=$HERE/forth/examples/snake.fs; typed="SNAKE"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthmaze) bin=; forth=$HERE/forth/examples/maze.fs; typed="MAZE"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthrule) bin=; forth=$HERE/forth/examples/rule.fs; typed="30 RULE"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthfern) bin=; forth=$HERE/forth/examples/fern.fs; typed="FERN"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthchaos) bin=; forth=$HERE/forth/examples/fern.fs; typed="CHAOS"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthliss) bin=; forth=$HERE/forth/examples/liss.fs; typed="3 2 LISS"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthclock) bin=; forth=$HERE/forth/examples/clock.fs; typed="12 00 00 CLOCK"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  forthsort) bin=; forth=$HERE/forth/examples/sort.fs; typed="SORTS"
           script=$HERE/forth/load.lua; set -- -bios forth "$@" ;;
  lisp)    bin=;                           typed=
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  deriv)   bin=; lisp=$HERE/lisp/examples/deriv.lsp
           typed="(DERIV '(+ (* 3 (EXPT X 2)) (* 2 X)) 'X)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  hanoi)   bin=; lisp=$HERE/lisp/examples/hanoi.lsp; typed="(HANOI 4 'A 'C 'B)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  queens)  bin=; lisp=$HERE/lisp/examples/queens.lsp; typed="(QUEENS 8)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  lispsier) bin=; lisp=$HERE/lisp/examples/sier.lsp; typed="(SIER)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  lisphilbert) bin=; lisp=$HERE/lisp/examples/hilbert.lsp; typed="(HILBERT)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  eliza)   bin=; lisp=$HERE/lisp/examples/eliza.lsp; typed="(TALK '(I FEEL SAD ABOUT MY JOB))"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  simp)    bin=; lisp=$HERE/lisp/examples/simp.lsp; typed="(SIMP (D '(* X X) 'X))"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  perms)   bin=; lisp=$HERE/lisp/examples/perms.lsp; typed="(PERMS '(A B C))"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  fib)     bin=; lisp=$HERE/lisp/examples/fib.lsp; typed="(CALLS FIB 15)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  animal) bin=; lisp=$HERE/lisp/examples/animal.lsp; typed="(PLAY)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  unify)  bin=; lisp=$HERE/lisp/examples/unify.lsp; typed="(QUERY '((GRAND TOM (? W))))"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  eval)   bin=; lisp=$HERE/lisp/examples/eval.lsp; typed="(EV '(APP (QUOTE (A B)) (QUOTE (C D E))) ENV)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  river)  bin=; lisp=$HERE/lisp/examples/river.lsp; typed="(CROSS)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  roman)  bin=; lisp=$HERE/lisp/examples/roman.lsp; typed="(WORDS 1987)"
           script=$HERE/lisp/load.lua; set -- -bios lisp "$@" ;;
  basic) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios basic "$@" ;;
  basicguess) bin=; forth=$HERE/basic/examples/guess.bas; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios basic "$@" ;;
  basicprimes) bin=; forth=$HERE/basic/examples/primes.bas; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios basic "$@" ;;
  basiclines) bin=; forth=$HERE/basic/examples/lines.bas; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios basic "$@" ;;
  basicworm) bin=; forth=$HERE/basic/examples/worm.bas; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios basic "$@" ;;
  logo) bin=; typed=""; curs=1A60
           script=$HERE/forth/load.lua; set -- -bios logo "$@" ;;
  logoflower) bin=; forth=$HERE/logo/examples/flower.logo; typed="FLOWER"; curs=1A60
           script=$HERE/forth/load.lua; set -- -bios logo "$@" ;;
  logospiral) bin=; forth=$HERE/logo/examples/spiral.logo; typed="SPIRAL 91"; curs=1A60
           script=$HERE/forth/load.lua; set -- -bios logo "$@" ;;
  logotree) bin=; forth=$HERE/logo/examples/tree.logo; typed="FOREST"; curs=1A60
           script=$HERE/forth/load.lua; set -- -bios logo "$@" ;;
  logoflake) bin=; forth=$HERE/logo/examples/flake.logo; typed="FLAKE 3"; curs=1A60
           script=$HERE/forth/load.lua; set -- -bios logo "$@" ;;
  logostars) bin=; forth=$HERE/logo/examples/stars.logo; typed="SKY"; curs=1A60
           script=$HERE/forth/load.lua; set -- -bios logo "$@" ;;
  focal) bin=; typed=""; curs=0C08
           script=$HERE/forth/load.lua; set -- -bios focal "$@" ;;
  focalroots) bin=; forth=$HERE/focal/examples/roots.foc; typed="GO"; curs=0C08
           script=$HERE/forth/load.lua; set -- -bios focal "$@" ;;
  focaltemp) bin=; forth=$HERE/focal/examples/temp.foc; typed="GO"; curs=0C08
           script=$HERE/forth/load.lua; set -- -bios focal "$@" ;;
  focalinterest) bin=; forth=$HERE/focal/examples/interest.foc; typed="GO"; curs=0C08
           script=$HERE/forth/load.lua; set -- -bios focal "$@" ;;
  focalguess) bin=; forth=$HERE/focal/examples/guess.foc; typed="GO"; curs=0C08
           script=$HERE/forth/load.lua; set -- -bios focal "$@" ;;
  focalsine) bin=; forth=$HERE/focal/examples/sine.foc; typed="GO"; curs=0C08
           script=$HERE/forth/load.lua; set -- -bios focal "$@" ;;
  pilot) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pilot "$@" ;;
  pilotgreet) bin=; forth=$HERE/pilot/examples/greet.pil; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pilot "$@" ;;
  pilotquiz) bin=; forth=$HERE/pilot/examples/quiz.pil; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pilot "$@" ;;
  pilottables) bin=; forth=$HERE/pilot/examples/tables.pil; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pilot "$@" ;;
  pilotstory) bin=; forth=$HERE/pilot/examples/story.pil; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pilot "$@" ;;
  pilotdraw) bin=; forth=$HERE/pilot/examples/draw.pil; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pilot "$@" ;;
  zasm) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios zasm "$@" ;;
  prolog) bin=; typed=""; curs=0C0E
           script=$HERE/forth/load.lua; set -- -bios prolog "$@" ;;
  prologfamily) bin=; forth=$HERE/prolog/examples/family.pl; typed="?- ANCESTOR(X,GUS)."; curs=0C0E
           script=$HERE/forth/load.lua; set -- -bios prolog "$@" ;;
  prologlists) bin=; forth=$HERE/prolog/examples/lists.pl; typed="?- APPEND(X,Y,[1,2,3])."; curs=0C0E
           script=$HERE/forth/load.lua; set -- -bios prolog "$@" ;;
  prologcolour) bin=; forth=$HERE/prolog/examples/colour.pl; typed="?- MAP(A,B,C,D,E)."; curs=0C0E
           script=$HERE/forth/load.lua; set -- -bios prolog "$@" ;;
  prologpath) bin=; forth=$HERE/prolog/examples/path.pl; typed="?- WAY(ARK,FORD,P)."; curs=0C0E
           script=$HERE/forth/load.lua; set -- -bios prolog "$@" ;;
  vtl) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios vtl "$@" ;;
  vtlprimes) bin=; forth=$HERE/vtl/examples/primes.vtl; typed="#=1"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios vtl "$@" ;;
  vtlguess) bin=; forth=$HERE/vtl/examples/guess.vtl; typed="#=1"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios vtl "$@" ;;
  vtlfib) bin=; forth=$HERE/vtl/examples/fib.vtl; typed="#=1"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios vtl "$@" ;;
  vtlcircles) bin=; forth=$HERE/vtl/examples/circles.vtl; typed="#=1"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios vtl "$@" ;;
  vtlchaos) bin=; forth=$HERE/vtl/examples/chaos.vtl; typed="#=1"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios vtl "$@" ;;
  mouse) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios mouse "$@" ;;
  mousefib) bin=; forth=$HERE/mouse/examples/fib.mou; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios mouse "$@" ;;
  mousefact) bin=; forth=$HERE/mouse/examples/fact.mou; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios mouse "$@" ;;
  mousesieve) bin=; forth=$HERE/mouse/examples/sieve.mou; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios mouse "$@" ;;
  mouseguess) bin=; forth=$HERE/mouse/examples/guess.mou; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios mouse "$@" ;;
  mousecircles) bin=; forth=$HERE/mouse/examples/circles.mou; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios mouse "$@" ;;
  befunge) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios befunge "$@" ;;
  befhello) bin=; forth=$HERE/befunge/examples/hello.bef; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios befunge "$@" ;;
  befcount) bin=; forth=$HERE/befunge/examples/count.bef; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios befunge "$@" ;;
  beffact) bin=; forth=$HERE/befunge/examples/fact.bef; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios befunge "$@" ;;
  befstars) bin=; forth=$HERE/befunge/examples/stars.bef; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios befunge "$@" ;;
  sheet) bin=; typed=""; curs=0C02
           script=$HERE/forth/load.lua; set -- -bios sheet "$@" ;;
  sheetbudget) bin=; forth=$HERE/sheet/examples/budget.cal; typed=""; curs=0C02
           script=$HERE/forth/load.lua; set -- -bios sheet "$@" ;;
  sheetinterest) bin=; forth=$HERE/sheet/examples/interest.cal; typed=""; curs=0C02
           script=$HERE/forth/load.lua; set -- -bios sheet "$@" ;;
  sheettimes) bin=; forth=$HERE/sheet/examples/times.cal; typed=""; curs=0C02
           script=$HERE/forth/load.lua; set -- -bios sheet "$@" ;;
  sheettemp) bin=; forth=$HERE/sheet/examples/temp.cal; typed=""; curs=0C02
           script=$HERE/forth/load.lua; set -- -bios sheet "$@" ;;
  trac) bin=; typed=""; curs=0C06
           script=$HERE/forth/load.lua; set -- -bios trac "$@" ;;
  trachello) bin=; forth=$HERE/trac/examples/hello.trac; typed=""; curs=0C06
           script=$HERE/forth/load.lua; set -- -bios trac "$@" ;;
  tracfact) bin=; forth=$HERE/trac/examples/fact.trac; typed=""; curs=0C06
           script=$HERE/forth/load.lua; set -- -bios trac "$@" ;;
  tracrev) bin=; forth=$HERE/trac/examples/rev.trac; typed=""; curs=0C06
           script=$HERE/forth/load.lua; set -- -bios trac "$@" ;;
  tracletter) bin=; forth=$HERE/trac/examples/letter.trac; typed=""; curs=0C06
           script=$HERE/forth/load.lua; set -- -bios trac "$@" ;;
  pl0) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pl0 "$@" ;;
  pl0squares) bin=; forth=$HERE/pl0/examples/squares.pl0; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pl0 "$@" ;;
  pl0primes) bin=; forth=$HERE/pl0/examples/primes.pl0; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pl0 "$@" ;;
  pl0gcd) bin=; forth=$HERE/pl0/examples/gcd.pl0; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pl0 "$@" ;;
  pl0fact) bin=; forth=$HERE/pl0/examples/fact.pl0; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pl0 "$@" ;;
  pl0rings) bin=; forth=$HERE/pl0/examples/rings.pl0; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios pl0 "$@" ;;
  bf) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  bfhello) bin=; forth=$HERE/bf/examples/hello.bf; typed="SHOW"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  bfcount) bin=; forth=$HERE/bf/examples/count.bf; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  bfadd) bin=; forth=$HERE/bf/examples/add.bf; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  bfalpha) bin=; forth=$HERE/bf/examples/alpha.bf; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  bfreverse) bin=; forth=$HERE/bf/examples/reverse.bf; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  bffib) bin=; forth=$HERE/bf/examples/fib.bf; typed="RUN"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios bf "$@" ;;
  ed) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios ed "$@" ;;
  edletter) bin=; forth=$HERE/ed/examples/letter.ed; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios ed "$@" ;;
  edlist) bin=; forth=$HERE/ed/examples/list.ed; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios ed "$@" ;;
  edsearch) bin=; forth=$HERE/ed/examples/search.ed; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios ed "$@" ;;
  edview) bin=; forth=$HERE/ed/examples/view.ed; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios ed "$@" ;;
  db) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios db "$@" ;;
  dbaddress) bin=; forth=$HERE/db/examples/address.db; typed="LIST"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios db "$@" ;;
  dbrecords) bin=; forth=$HERE/db/examples/records.db; typed="LIST"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios db "$@" ;;
  dbclub) bin=; forth=$HERE/db/examples/club.db; typed="LIST"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios db "$@" ;;
  adv) bin=; typed=""; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios adv "$@" ;;
  advtutor) bin=; forth=$HERE/adv/examples/tutor.adv; typed="PLAY"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios adv "$@" ;;
  advlab) bin=; forth=$HERE/adv/examples/lab.adv; typed="PLAY"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios adv "$@" ;;
  advmill) bin=; forth=$HERE/adv/examples/mill.adv; typed="PLAY"; curs=1DA0
           script=$HERE/forth/load.lua; set -- -bios adv "$@" ;;
  apl) bin=; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  aplbasics) bin=; forth=$HERE/apl/examples/basics.apl; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  aplprimes) bin=; forth=$HERE/apl/examples/primes.apl; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  apltable) bin=; forth=$HERE/apl/examples/table.apl; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  aplstats) bin=; forth=$HERE/apl/examples/stats.apl; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  aplhist) bin=; forth=$HERE/apl/examples/hist.apl; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  aplpascal) bin=; forth=$HERE/apl/examples/pascal.apl; typed=""; curs=0C38
           script=$HERE/forth/load.lua; set -- -bios apl "$@" ;;
  chip8)   bin=;                           typed="^"; set -- -bios chip8 "$@" ;;
  c8bounce) bin=$HERE/chip8/examples/bounce.ch8; addr=0E00; typed="^"; set -- -bios chip8 "$@" ;;
  c8keys) bin=$HERE/chip8/examples/keys.ch8; addr=0E00; typed="^"; set -- -bios chip8 "$@" ;;
  c8dodge) bin=$HERE/chip8/examples/dodge.ch8; addr=0E00; typed="^"; set -- -bios chip8 "$@" ;;
  c8kaleido) bin=$HERE/chip8/examples/kaleido.ch8; addr=0E00; typed="^"; set -- -bios chip8 "$@" ;;
  ready)   bin=;                           typed= ;;
  *) echo "usage: $0 [32k] <program> [MAME options]; the programs are listed at the top of $0" >&2; exit 1 ;;
esac

cd "$MAME"
C80_BIN=$bin C80_TYPE=$typed C80_ADDR=$addr C80_FORTH=$forth C80_LISP=$lisp C80_CURS=$curs exec ./mamed $machine -autoboot_script "$script" "$@"
