#!/bin/sh
# Run each LISP, FORTH and BURP test through the firmware's machine code and
# through the web emulator (web/tools/session.js), and compare the screens.
# BURP has no cursor to wait for, so its tests' #ready lines become waits.
cd "$(dirname "$0")"
R=../../..
T=$(mktemp -d)
fail=0
run() {   # rom-name rom-file test [env]
  a=$(env $4 ./session "$R/$2" "$3" 2>&1)
  b=$(cd $R && env $4 node web/tools/session.js "$1" "$3" 2>&1)
  if [ "$a" = "$b" ]; then echo "same      $5"; else echo "DIFFERENT $5"; fail=1; fi
}
for t in $R/lisp/tests/*.txt; do run lisp psicomp80_lisp.rom "$(cd $R && pwd)/lisp/tests/$(basename $t)" "" lisp/tests/$(basename $t); done
for t in $R/forth/tests/*.txt; do run forth psicomp80_forth.rom "$(cd $R && pwd)/forth/tests/$(basename $t)" NOWAIT=1 forth/tests/$(basename $t); done
for t in $R/burp/tests/*.txt; do
  sed 's/^#ready$/#wait 20/' $t > $T/$(basename $t)
  run burp psicomp80.rom $T/$(basename $t) NOWAIT=1 burp/tests/$(basename $t)
done
rm -r $T
exit $fail
