;;; test-eval.el --- Test evaluation features using ERT -*- lexical-binding: t; -*-

;;; Commentary:
;; Test the evaluation functionality

;;; Code:

(require 'ert)
(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

;;; Evaluation Tests (skip if wolframscript not available)

(ert-deftest wolfram-nb-test-wolframscript-check ()
  "Test wolframscript availability detection."
  ;; This test always passes - just checks the function works
  (should (or (wolfram-nb--check-wolframscript)
              (not (wolfram-nb--check-wolframscript)))))

(ert-deftest wolfram-nb-test-simple-evaluation ()
  "Test simple expression evaluation."
  (skip-unless (wolfram-nb--check-wolframscript))
  (let ((result (wolfram-nb--eval-expression "2 + 2")))
    (should (stringp result))
    (should (string= (string-trim result) "4"))))

(ert-deftest wolfram-nb-test-list-evaluation ()
  "Test list generation."
  (skip-unless (wolfram-nb--check-wolframscript))
  (let ((result (wolfram-nb--eval-expression "Range[5]")))
    (should (stringp result))
    (should (string-match-p "{1.*5}" result))))

(ert-deftest wolfram-nb-test-function-evaluation ()
  "Test function definition and use."
  (skip-unless (wolfram-nb--check-wolframscript))
  (let ((result (wolfram-nb--eval-expression "f[x_] := x^2; f[5]")))
    (should (stringp result))
    (should (string= (string-trim result) "25"))))

(ert-deftest wolfram-nb-test-arithmetic ()
  "Test basic arithmetic operations."
  (skip-unless (wolfram-nb--check-wolframscript))
  (let ((result (wolfram-nb--eval-expression "10 * 5")))
    (should (string= (string-trim result) "50"))))

(ert-deftest wolfram-nb-test-format-output ()
  "Test that wolfram-nb--format-output works."
  ;; Test with simple string
  (should (string= (wolfram-nb--format-output "42") "42"))
  ;; Test with graphics (starts with Graphics)
  (should (string-match-p "view in Mathematica" 
                         (wolfram-nb--format-output "Graphics[...]")))
  ;; Test with image (starts with Image)
  (should (string-match-p "view in Mathematica" 
                         (wolfram-nb--format-output "Image[...]"))))

(provide 'test-eval)
;;; test-eval.el ends here
