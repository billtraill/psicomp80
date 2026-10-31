; The Towers of Hanoi: move N discs from peg FROM to peg TO,
; using peg VIA, one disc at a time and never a bigger disc
; on a smaller one.
(DEFUN HANOI (N FROM TO VIA)
  (COND ((EQ N 0) NIL)
        (T (HANOI (- N 1) FROM VIA TO)
           (PRINT (LIST 'MOVE 'DISC N 'FROM FROM 'TO TO))
           (HANOI (- N 1) VIA TO FROM))))
