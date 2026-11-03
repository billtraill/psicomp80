; The animal game, which learns.  TREE is a question with a yes
; tree and a no tree, or an animal.  There is no READ, so you
; answer by calling functions: (PLAY) asks the first question,
; then (YES) or (NO).  If it guesses wrong, teach it with
; (ITS 'DOG '(DOES IT BARK)): the animal and a question that is
; yes for it and no for the animal it guessed.
(SETQ TREE '((DOES IT HAVE FUR) CAT FISH))
(DEFUN PLAY () (SETQ NODE TREE) (SETQ PATH NIL) (ASK))
(DEFUN ASK ()
  (COND ((ATOM NODE) (LIST 'IS 'IT 'A NODE)) (T (CAR NODE))))
(DEFUN YES () (COND ((ATOM NODE) '(I WIN)) (T (DOWN 'Y (CADR NODE)))))
(DEFUN NO ()
  (COND ((ATOM NODE) '(WHAT IS IT))
        (T (DOWN 'N (CADDR NODE)))))
(DEFUN DOWN (D N) (SETQ PATH (CONS D PATH)) (SETQ NODE N) (ASK))
(DEFUN REV (L A) (COND (L (REV (CDR L) (CONS (CAR L) A))) (T A)))
; the tree with the leaf at the end of path P replaced by NEW
(DEFUN GROW (TR P NEW)
  (COND ((NULL P) NEW)
        ((EQ (CAR P) 'Y)
         (LIST (CAR TR) (GROW (CADR TR) (CDR P) NEW) (CADDR TR)))
        (T (LIST (CAR TR) (CADR TR) (GROW (CADDR TR) (CDR P) NEW)))))
(DEFUN ITS (A Q)
  (SETQ TREE (GROW TREE (REV PATH NIL) (LIST Q A NODE))))
