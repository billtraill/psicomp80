; Unification, and a taste of Prolog.  A variable is a list
; (? X).  (UNIFY A B '(T)) finds values for the variables that
; make A and B the same: it gives (T (VAR VALUE) ...), or NIL if
; there are none.  QUERY proves goals from the facts and rules in
; DB, depth first, and prints every answer.
(DEFUN VARP (X) (AND (NULL (ATOM X)) (EQ (CAR X) '?)))
(DEFUN EQUAL (A B)
  (COND ((ATOM A) (EQ A B)) ((ATOM B) NIL)
        ((EQUAL (CAR A) (CAR B)) (EQUAL (CDR A) (CDR B)))))
(DEFUN LOOK (X L)
  (COND ((NULL L) NIL) ((EQUAL X (CAR (CAR L))) (CAR L))
        (T (LOOK X (CDR L)))))
; follow a variable through the bindings in S
(DEFUN WALK (X S) (COND ((VARP X) (WALK1 X (LOOK X (CDR S)) S)) (T X)))
(DEFUN WALK1 (X B S) (COND (B (WALK (CADR B) S)) (T X)))
(DEFUN UNIFY (A B S) (COND (S (UNI (WALK A S) (WALK B S) S))))
(DEFUN UNI (A B S)
  (COND ((EQUAL A B) S)
        ((VARP A) (CONS T (CONS (LIST A B) (CDR S))))
        ((VARP B) (CONS T (CONS (LIST B A) (CDR S))))
        ((OR (ATOM A) (ATOM B)) NIL)
        (T (UNIFY (CDR A) (CDR B) (UNIFY (CAR A) (CAR B) S)))))
; X with every bound variable replaced by its value
(DEFUN SUBST (X S) (FULL (WALK X S) S))
(DEFUN FULL (X S)
  (COND ((OR (ATOM X) (VARP X)) X)
        (T (CONS (SUBST (CAR X) S) (SUBST (CDR X) S)))))
; each clause is (HEAD GOAL ...); a fact has no goals
(SETQ DB '(((PARENT TOM BOB)) ((PARENT TOM LIZ))
  ((PARENT BOB ANN)) ((PARENT BOB PAT)) ((PARENT PAT JIM))
  ((GRAND (? X) (? Z)) (PARENT (? X) (? Y)) (PARENT (? Y) (? Z)))))
(DEFUN APP (A B) (COND (A (CONS (CAR A) (APP (CDR A) B))) (T B)))
; a clause's variables, renamed for depth N: (? X) is (? X N)
(DEFUN RN (X)
  (COND ((ATOM X) X) ((VARP X) (LIST '? (CADR X) N))
        (T (CONS (RN (CAR X)) (RN (CDR X))))))
(DEFUN PROVE (GS S N)
  (COND ((NULL GS) (PRINT (SUBST Q S))) (T (TRYC DB))))
(DEFUN TRYC (CL)
  (COND (CL (STEP (RN (CAR CL))) (TRYC (CDR CL)))))
(DEFUN STEP (C) (MORE (UNIFY (CAR GS) (CAR C) S) (APP (CDR C) (CDR GS))))
(DEFUN MORE (S2 G2) (COND (S2 (PROVE G2 S2 (+ N 1)))))
(DEFUN QUERY (Q) (PROVE Q '(T) 0) 'DONE)
