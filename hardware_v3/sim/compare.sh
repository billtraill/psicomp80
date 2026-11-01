#!/bin/sh
# Run COMP80 sessions on the logic (Verilator) and on the v2 firmware's machine
# code, and compare the screens.  Both at 4 MHz, the clock the tests were
# written for.  Pass test files to choose; by default one each of LISP, FORTH
# and BURP (BURP's #ready lines become waits, as its tests have no cursor).
cd "$(dirname "$0")"
R=../..
HOST=$R/hardware_v2/firmware/host/session
[ -x $HOST ] || make -C $R/hardware_v2/firmware/host >/dev/null
T=$(mktemp -d)
sed 's/^#ready$/#wait 20/' $R/burp/tests/sample.txt > $T/burp_sample.txt
set -- "${@:-lisp/tests/basic.txt forth/tests/basic.txt $T/burp_sample.txt}"
fail=0
for t in $*; do
  case $t in /*) f=$t ;; *) f=$R/$t ;; esac
  case $t in *lisp*) rom=psicomp80_lisp.rom; e= ;; *forth*) rom=psicomp80_forth.rom; e=NOWAIT=1 ;; *) rom=psicomp80.rom; e=NOWAIT=1 ;; esac
  env $e ./obj/Vcomp80_machine $R/$rom $f clock=4000000 > $T/hdl.txt 2>&1 &
  env $e $HOST $R/$rom $f clock=4000000 > $T/c.txt 2>&1
  wait
  if cmp -s $T/hdl.txt $T/c.txt; then echo "same      $(basename $t)"; else echo "DIFFERENT $(basename $t)"; diff $T/c.txt $T/hdl.txt | head -20; fail=1; fi
done
rm -r $T
exit $fail
