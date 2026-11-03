; Fibonacci and Ackermann, counting the calls.  (CALLS FIB 15)
; gives the 15th Fibonacci number and how many calls FIB made;
; FAST adds its way up instead.  ACK grows so fast that only
; small arguments finish: (CALLS ACK 3 2) gives 29 after 541
; calls, but (ACK 3 3) needs the stack of the 32 KB machine.
(DEFUN FIB (N)
  (SETQ C (+ C 1))
  (COND ((< N 2) N) (T (+ (FIB (- N 1)) (FIB (- N 2))))))
(DEFUN FAST (N) (F2 N 0 1))
(DEFUN F2 (N A B)
  (SETQ C (+ C 1))
  (COND ((EQ N 0) A) (T (F2 (- N 1) B (+ A B)))))
(DEFUN ACK (M N)
  (SETQ C (+ C 1))
  (COND ((EQ M 0) (+ N 1))
        ((EQ N 0) (ACK (- M 1) 1))
        (T (ACK (- M 1) (ACK M (- N 1))))))
(DEFUN CALLS (F A B) (SETQ C 0) (LIST (F A B) 'IN C 'CALLS))
