; Permutations and the power set.  (PERMS '(A B C)) is the six
; orders of A, B and C; (POWER '(A B C)) is the eight lists that
; can be made by leaving some of them out.
(DEFUN APP (A B) (COND ((NULL A) B) (T (CONS (CAR A) (APP (CDR A) B)))))
(DEFUN DEL (X L)
  (COND ((NULL L) NIL) ((EQ X (CAR L)) (CDR L))
        (T (CONS (CAR L) (DEL X (CDR L))))))
; X put on the front of each list in LS
(DEFUN PUT (X LS)
  (COND ((NULL LS) NIL) (T (CONS (CONS X (CAR LS)) (PUT X (CDR LS))))))
; each element first, followed by each order of the rest
(DEFUN PERMS (L) (COND ((NULL L) '(NIL)) (T (EACH L))))
(DEFUN EACH (XS)
  (COND ((NULL XS) NIL)
        (T (APP (PUT (CAR XS) (PERMS (DEL (CAR XS) L)))
                (EACH (CDR XS))))))
; the subsets with the first element, then those without it
(DEFUN POWER (L) (COND ((NULL L) '(NIL)) (T (TWO (CAR L) (POWER (CDR L))))))
(DEFUN TWO (X P) (APP (PUT X P) P))
(DEFUN LENGTH (L) (COND ((NULL L) 0) (T (+ 1 (LENGTH (CDR L))))))
