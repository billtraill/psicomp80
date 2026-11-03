; Missionaries and cannibals.  Three of each must cross a river
; in a boat that holds two, and the cannibals must never outnumber
; the missionaries on either bank.  A state is (M C B): the
; missionaries and cannibals on the left bank, and B 1 when the
; boat is there.  SOLVE searches depth first, never going back to
; a state it has been through, and gives the states on the way.
(DEFUN EQUAL (A B)
  (COND ((ATOM A) (EQ A B)) ((ATOM B) NIL)
        ((EQUAL (CAR A) (CAR B)) (EQUAL (CDR A) (CDR B)))))
(DEFUN MEMBER (X L)
  (COND ((NULL L) NIL) ((EQUAL X (CAR L)) L) (T (MEMBER X (CDR L)))))
(DEFUN REV (L A) (COND (L (REV (CDR L) (CONS (CAR L) A))) (T A)))
(DEFUN SOLVE (S P)
  (COND ((EQUAL S '(0 0 0)) (REV P NIL))
        (T (OR (TRY 1 0) (TRY 2 0) (TRY 0 1) (TRY 0 2) (TRY 1 1)))))
; take DM missionaries and DC cannibals across from where the boat is
(DEFUN TRY (DM DC)
  (COND ((EQ (CADDR S) 1)
         (NEXT (- (CAR S) DM) (- (CADR S) DC) 0))
        (T (NEXT (+ (CAR S) DM) (+ (CADR S) DC) 1))))
(DEFUN NEXT (M C B)
  (COND ((AND (OK M C) (NULL (MEMBER (LIST M C B) P)))
         (SOLVE (LIST M C B) (CONS (LIST M C B) P)))))
(DEFUN OK (M C)
  (AND (< M 4) (< C 4) (< -1 M) (< -1 C)
       (OR (EQ M 0) (< (- C 1) M)) (OR (EQ M 3) (< (- M 1) C))))
; print a state as the two banks with the boat by one of them
(DEFUN REP (N K) (COND ((< 0 N) (TYO K) (REP (- N 1) K))))
(DEFUN BANK (M C) (REP M 77) (REP C 67) (REP (- 6 (+ M C)) 32))
(DEFUN SHOW (S)
  (BANK (CAR S) (CADR S))
  (COND ((EQ (CADDR S) 1) (PRIN1 'B=====)) (T (PRIN1 '=====B)))
  (BANK (- 3 (CAR S)) (- 3 (CADR S))) (TERPRI))
(DEFUN SHOWALL (L) (COND (L (SHOW (CAR L)) (SHOWALL (CDR L)))))
(DEFUN CROSS () (SHOWALL (SOLVE '(3 3 1) '((3 3 1)))) 'ACROSS)
