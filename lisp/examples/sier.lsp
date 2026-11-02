; The Sierpinski triangle: Pascal's triangle with each
; entry taken mod 2.  Entry X of row Y is odd when every
; bit of X is also set in Y.
(DEFUN ODD (X Y)
  (COND ((EQ X 0) T)
        ((AND (EQ (REM X 2) 1) (EQ (REM Y 2) 0)) NIL)
        (T (ODD (/ X 2) (/ Y 2)))))
; Call FN on each number from LO up to HI - 1, halving the
; range each time so the recursion stays shallow.
(DEFUN FROM (LO HI FN)
  (COND ((< (- HI LO) 2) (COND ((< LO HI) (FN LO))))
        (T (FROM LO (/ (+ LO HI) 2) FN)
           (FROM (/ (+ LO HI) 2) HI FN))))
; Each entry is two characters wide, a block or blank.
(DEFUN TWO (C) (TYO C) (TYO C))
(DEFUN ENTRY (X) (TWO (COND ((ODD X Y) 143) (T 32))))
(DEFUN SP (X) (TYO 32))
(DEFUN ROW (Y)
  (FROM 0 (- 15 Y) SP)
  (FROM 0 (+ Y 1) ENTRY)
  (TERPRI))
(DEFUN SIER () (FROM 0 16 ROW))
