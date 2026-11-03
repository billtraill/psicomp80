; A little Eliza, the 1966 program that plays a psychotherapist.
; (TALK '(I FEEL SAD)) answers (WHY DO YOU FEEL SAD).  TALK looks
; for the first keyword of RULES in the sentence; a * in the answer
; is the rest of the sentence after the keyword, with I and YOU,
; MY and YOUR swapped.  With no keyword it says something dull.
(SETQ RULES '((FEEL (WHY DO YOU FEEL *))
  (AM (WHY ARE YOU *))
  (MOTHER (TELL ME ABOUT YOUR FAMILY))
  (BECAUSE (IS THAT THE REAL REASON))
  (YOU (WHY DO YOU THINK I *))))
(SETQ PAIRS '((I YOU) (ME YOU) (MY YOUR) (AM ARE) (YOU I) (YOUR MY)))
(SETQ DULLS '((GO ON) (I SEE) (TELL ME MORE)))
(SETQ D NIL)
(DEFUN MEMQ (X L)
  (COND ((NULL L) NIL) ((EQ X (CAR L)) L) (T (MEMQ X (CDR L)))))
; swap the pronouns in a list of words
(DEFUN SW (L) (COND (L (CONS (SW1 (CAR L) PAIRS) (SW (CDR L))))))
(DEFUN SW1 (W P)
  (COND ((NULL P) W) ((EQ W (CAR (CAR P))) (CADR (CAR P)))
        (T (SW1 W (CDR P)))))
; the answer R with * replaced by the rest of the sentence
(DEFUN FILL (R)
  (COND ((NULL R) NIL) ((EQ (CAR R) '*) (SW (CDR REST)))
        (T (CONS (CAR R) (FILL (CDR R))))))
(DEFUN TRY (RS)
  (COND ((NULL RS) (DULL))
        (T (TRY1 (MEMQ (CAR (CAR RS)) S) (CAR RS) RS))))
(DEFUN TRY1 (REST R RS)
  (COND (REST (FILL (CADR R))) (T (TRY (CDR RS)))))
(DEFUN DULL ()
  (COND ((NULL D) (SETQ D DULLS)))
  (NEXT (CAR D)))
(DEFUN NEXT (X) (SETQ D (CDR D)) X)
(DEFUN TALK (S) (TRY RULES))
