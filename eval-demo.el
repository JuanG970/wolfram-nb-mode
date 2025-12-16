;;; eval-demo.el --- Interactive evaluation demo -*- lexical-binding: t; -*-

;;; Commentary:
;; Demonstrates the evaluation features of wolfram-nb-mode

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defun eval-demo ()
  "Run an interactive evaluation demo."
  (interactive)
  
  (unless (wolfram-nb--check-wolframscript)
    (error "This demo requires wolframscript. Install from: https://www.wolfram.com/engine/"))
  
  (message "\n╔════════════════════════════════════════════════════════╗")
  (message "║       Wolfram NB Mode - Evaluation Demo              ║")
  (message "╚════════════════════════════════════════════════════════╝\n")
  
  ;; Demo 1: Simple arithmetic
  (message "Demo 1: Simple Arithmetic")
  (message "  Expression: 2 + 2")
  (let ((result (wolfram-nb--eval-expression "2 + 2")))
    (message "  Result: %s" result))
  (sit-for 1)
  
  ;; Demo 2: Function definition
  (message "\nDemo 2: Function Definition")
  (message "  Expression: f[x_] := x^2 + 1; f[10]")
  (let ((result (wolfram-nb--eval-expression "f[x_] := x^2 + 1; f[10]")))
    (message "  Result: %s" result))
  (sit-for 1)
  
  ;; Demo 3: List operations
  (message "\nDemo 3: List Operations")
  (message "  Expression: Total[Range[100]]")
  (let ((result (wolfram-nb--eval-expression "Total[Range[100]]")))
    (message "  Result: %s" result))
  (sit-for 1)
  
  ;; Demo 4: Symbolic math
  (message "\nDemo 4: Symbolic Mathematics")
  (message "  Expression: Expand[(x + y)^2]")
  (let ((result (wolfram-nb--eval-expression "Expand[(x + y)^2]")))
    (message "  Result: %s" result))
  (sit-for 1)
  
  ;; Demo 5: Opening notebook with evaluation
  (message "\n╔════════════════════════════════════════════════════════╗")
  (message "║         Opening eval-demo.nb...                       ║")
  (message "╚════════════════════════════════════════════════════════╝\n")
  
  (wolfram-nb-open "eval-demo.nb")
  
  (message "\nDemo complete!")
  (message "\nYou can now:")
  (message "  - Move to a source block")
  (message "  - Press C-c C-c to evaluate it")
  (message "  - Press C-c C-b to evaluate all blocks")
  (message "  - Press C-c C-k to clear all outputs")
  (message "  - Press C-x C-s to save"))

;; Run demo if not in batch mode
(when (not noninteractive)
  (eval-demo))

(provide 'eval-demo)
;;; eval-demo.el ends here
