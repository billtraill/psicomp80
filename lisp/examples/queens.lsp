; The eight queens: put N queens on an N x N board with no two
; in the same row, column or diagonal.  A board is the list of
; the queens' rows, the newest column first.  N is a free
; variable in PLACE, TRY and ROW: LISP's dynamic scope finds
; QUEENS's N.
(DEFUN OK (R QS D)
  (COND ((NULL QS) T)
        ((EQ R (CAR QS)) NIL)
        ((EQ (- R (CAR QS)) D) NIL)
        ((EQ (- (CAR QS) R) D) NIL)
        (T (OK R (CDR QS) (+ D 1)))))
(DEFUN PLACE (QS K)
  (COND ((EQ K N) QS) (T (TRY 1 QS K))))
(DEFUN TRY (R QS K)
  (COND ((> R N) NIL)
        (T (OR (AND (OK R QS 1) (PLACE (CONS R QS) (+ K 1)))
               (TRY (+ R 1) QS K)))))
(DEFUN ROW (C Q)
  (COND ((> C N) (TERPRI))
        (T (TYO (COND ((EQ C Q) 81) (T 46)))
           (TYO 32)
           (ROW (+ C 1) Q))))
(DEFUN SHOW (B)
  (COND (B (ROW 1 (CAR B)) (SHOW (CDR B)))))
(DEFUN QUEENS (N)
  ((LAMBDA (B) (SHOW B) B) (PLACE NIL 0)))
