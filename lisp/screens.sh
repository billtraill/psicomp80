#!/bin/sh
# Make the LISP screenshots by typing sessions into the emulator (-bios lisp,
# so build the ROM and MAME first): lisp_demo.png from tests/demo.txt, and
# examples/screens/<name>.png for each example program, typed in and then
# run with the lines below.
set -e
HERE=$(cd "$(dirname "$0")" && pwd)
MAME=${MAME_DIR:-$HOME/localdev/mame}
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# shot <steps file> <png>
shot() {
  rm -rf "$TMP/snap"
  (cd "$MAME" && LISP_TEST=$1 ./mamed psicomp80 -bios lisp -video none \
    -sound none -nothrottle -seconds_to_run 900 -snapshot_directory "$TMP/snap" \
    -autoboot_script "$HERE/test_lisp.lua" > /dev/null)
  cp "$TMP/snap/psicomp80/0000.png" "$2"
  echo "$2"
}

# example <name> <line>...: type examples/<name>.lsp, then the lines
example() {
  name=$1; shift
  {
    echo '^'; echo '#wait 0.5'
    grep -v -e '^;' -e '^[[:space:]]*$' "$HERE/examples/$name.lsp" | sed 's/$/\\r/'
    for l in "$@"; do printf '%s\\r\n' "$l"; done
    echo '#ready'; echo '#snap'
  } > "$TMP/$name.txt"
  shot "$TMP/$name.txt" "$HERE/examples/screens/$name.png"
}

mkdir -p "$HERE/examples/screens"
shot "$HERE/tests/demo.txt" "$HERE/lisp_demo.png"
example deriv \
  "(DERIV '(+ (* 3 (EXPT X 2)) (* 2 X)) 'X)" \
  "(DERIV '(* X (* X X)) 'X)" \
  "(DERIV '(EXPT (+ (* 2 X) 1) 3) 'X)" \
  "(DERIV '(- (* A (EXPT X 3)) (* B X)) 'X)" \
  "(DERIV (DERIV '(EXPT X 4) 'X) 'X)"
example hanoi "(HANOI 4 'A 'C 'B)"
example queens "(QUEENS 8)"
