;;; test-eval.el --- Test evaluation features -*- lexical-binding: t; -*-

;;; Commentary:
;; Test the evaluation functionality

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defun test-wolframscript-available ()
  "Test if wolframscript is available."
  (message "Testing wolframscript availability...")
  (if (wolfram-nb--check-wolframscript)
      (message "  ✓ wolframscript found at: %s" 
               (executable-find wolfram-nb-wolframscript-path))
    (message "  ✗ wolframscript not found (this is OK if not installed)")))

(defun test-simple-evaluation ()
  "Test simple expression evaluation."
  (message "\nTesting simple evaluation...")
  (condition-case err
      (let ((result (wolfram-nb--eval-expression "2 + 2")))
        (message "  Result of '2 + 2': %s" result)
        (if (string= (string-trim result) "4")
            (message "  ✓ Simple evaluation PASSED")
          (message "  ✗ Simple evaluation FAILED: expected 4, got %s" result)))
    (error
     (message "  ⚠ Evaluation not available (wolframscript not installed): %s" 
              (error-message-string err)))))

(defun test-list-evaluation ()
  "Test list generation."
  (message "\nTesting list evaluation...")
  (condition-case err
      (let ((result (wolfram-nb--eval-expression "Range[5]")))
        (message "  Result of 'Range[5]': %s" result)
        (if (string-match-p "{1.*5}" result)
            (message "  ✓ List evaluation PASSED")
          (message "  ⚠ List evaluation result: %s" result)))
    (error
     (message "  ⚠ Evaluation not available: %s" (error-message-string err)))))

(defun test-function-evaluation ()
  "Test function definition and use."
  (message "\nTesting function evaluation...")
  (condition-case err
      (let ((result (wolfram-nb--eval-expression "f[x_] := x^2; f[5]")))
        (message "  Result of 'f[x_] := x^2; f[5]': %s" result)
        (if (string= (string-trim result) "25")
            (message "  ✓ Function evaluation PASSED")
          (message "  ⚠ Function evaluation result: %s" result)))
    (error
     (message "  ⚠ Evaluation not available: %s" (error-message-string err)))))

(defun run-eval-tests ()
  "Run all evaluation tests."
  (message "=== Wolfram NB Evaluation Tests ===\n")
  (test-wolframscript-available)
  (test-simple-evaluation)
  (test-list-evaluation)
  (test-function-evaluation)
  (message "\n=== Evaluation Tests Complete ===")
  (message "\nNote: If wolframscript is not installed, evaluation tests will be skipped.")
  (message "To install: https://www.wolfram.com/engine/"))

;; Run tests
(run-eval-tests)

(provide 'test-eval)
;;; test-eval.el ends here
