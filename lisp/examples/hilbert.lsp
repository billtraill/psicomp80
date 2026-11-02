; The Hilbert curve, 16 x 16 points.  LISP can only print
; a line at a time, so it works out each point's distance
; along the curve, and joins two neighbours when their
; distances differ by 1.
; D is the distance of point X,Y: S is the size of the
; quarter being looked at, 8 then 4, 2 and 1.  Each step
; picks a quarter, adds the points in the quarters before
; it, and turns X,Y round to that quarter's way up.
(DEFUN D (S X Y N)
  (COND ((EQ S 0) N)
        (T (QUARTER (REM (/ X S) 2) (REM (/ Y S) 2)))))
(DEFUN QUARTER (RX RY)
  (COND ((EQ RY 1) (D (/ S 2) X Y (+ N (* (* S S) (+ RX 1)))))
        ((EQ RX 1) (D (/ S 2) (- 15 Y) (- 15 X) (+ N (* (* S S) 3))))
        (T (D (/ S 2) Y X N))))
; The distances of row Y, from point X to the end.
(DEFUN DROW (X Y)
  (COND ((EQ X 16) NIL)
        (T (CONS (D 8 X Y 0) (DROW (+ X 1) Y)))))
(DEFUN NEXT (A B) (OR (EQ (- A B) 1) (EQ (- B A) 1)))
; Two characters per point, four cells to a character:
; the point, the line right in the cell beside it and the
; next character, and the line down in the cell below.
; Graphics character 128 + TL + 2TR + 4BR + 8BL.
(DEFUN LINE (A B)
  (COND (A (POINT (AND (CDR A) (NEXT (CAR A) (CADR A)))
                  (AND B (NEXT (CAR A) (CAR B))))
           (LINE (CDR A) (CDR B)))))
(DEFUN POINT (H V)
  (TYO (+ 129 (+ (COND (H 2) (T 0)) (COND (V 8) (T 0)))))
  (TYO (COND (H 131) (T 32))))
; Call FN on each number from LO up to HI - 1, halving the
; range each time so the recursion stays shallow.
(DEFUN FROM (LO HI FN)
  (COND ((< (- HI LO) 2) (COND ((< LO HI) (FN LO))))
        (T (FROM LO (/ (+ LO HI) 2) FN)
           (FROM (/ (+ LO HI) 2) HI FN))))
; Each row needs the distances of the row below it too.
(DEFUN ROW (Y)
  (SETQ BELOW (COND ((< Y 15) (DROW 0 (+ Y 1)))))
  (LINE HERE BELOW)
  (TERPRI)
  (SETQ HERE BELOW))
(DEFUN HILBERT ()
  (SETQ HERE (DROW 0 0))
  (FROM 0 16 ROW))
