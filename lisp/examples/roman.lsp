; Roman numerals both ways, and numbers in words.
; (ROMAN 1987) gives (M C M L X X X V I I); NUMERAL turns such a
; list back into a number, taking away a letter that comes before
; a bigger one.  (WORDS 1987) gives (ONE THOUSAND NINE HUNDRED
; AND EIGHTY SEVEN).
(SETQ TB '((1000 M) (900 C M) (500 D) (400 C D) (100 C) (90 X C)
  (50 L) (40 X L) (10 X) (9 I X) (5 V) (4 I V) (1 I)))
(DEFUN APP (A B) (COND (A (CONS (CAR A) (APP (CDR A) B))) (T B)))
(DEFUN ROMAN (N) (RO N TB))
(DEFUN RO (N L)
  (COND ((EQ N 0) NIL) ((< N (CAR (CAR L))) (RO N (CDR L)))
        (T (APP (CDR (CAR L)) (RO (- N (CAR (CAR L))) L)))))
; the value of letter X: the entry in L that is just that letter
(DEFUN VL (X L)
  (COND ((AND (EQ X (CADR (CAR L))) (NULL (CDR (CDR (CAR L)))))
         (CAR (CAR L)))
        (T (VL X (CDR L)))))
(DEFUN NUMERAL (L)
  (COND ((NULL L) 0)
        ((AND (CDR L) (< (VL (CAR L) TB) (VL (CADR L) TB)))
         (- (NUMERAL (CDR L)) (VL (CAR L) TB)))
        (T (+ (VL (CAR L) TB) (NUMERAL (CDR L))))))
(SETQ SMALL '(ONE TWO THREE FOUR FIVE SIX SEVEN EIGHT NINE TEN
  ELEVEN TWELVE THIRTEEN FOURTEEN FIFTEEN SIXTEEN SEVENTEEN
  EIGHTEEN NINETEEN))
(SETQ TENS '(TEN TWENTY THIRTY FORTY FIFTY SIXTY SEVENTY EIGHTY
  NINETY))
(DEFUN NTH (K L) (COND ((EQ K 1) (CAR L)) (T (NTH (- K 1) (CDR L)))))
(DEFUN SM (N) (COND ((< 0 N) (LIST (NTH N SMALL)))))
; below 100, then below 1000, then the rest
(DEFUN U (N)
  (COND ((< N 20) (SM N))
        (T (CONS (NTH (/ N 10) TENS) (SM (REM N 10))))))
(DEFUN AU (N) (COND ((< 0 N) (CONS 'AND (U N)))))
(DEFUN H (N)
  (COND ((< N 100) (U N))
        (T (APP (SM (/ N 100)) (CONS 'HUNDRED (AU (REM N 100)))))))
(DEFUN R (N) (COND ((< N 100) (AU N)) (T (H N))))
(DEFUN WORDS (N)
  (COND ((EQ N 0) '(ZERO)) ((< N 1000) (H N))
        (T (APP (H (/ N 1000)) (CONS 'THOUSAND (R (REM N 1000)))))))
