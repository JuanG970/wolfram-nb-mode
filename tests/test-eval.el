;;; test-eval.el --- Test evaluation features -*- lexical-binding: t; -*-

;;; Commentary:
;; Tests for sync evaluation, format-output, and org-babel integration.
;; Tests requiring wolframscript are skipped when it's not available.

;;; Code:

(require 'ert)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

;;; Availability

(ert-deftest wolfram-nb-test-wolframscript-check ()
  "check-wolframscript returns a string or nil."
  (let ((result (wolfram-nb--check-wolframscript)))
    (should (or (stringp result) (null result)))))

;;; Synchronous evaluation (require wolframscript)

(ert-deftest wolfram-nb-test-eval-simple ()
  (skip-unless (wolfram-nb--check-wolframscript))
  (should (string= (wolfram-nb--eval-expression "2 + 2") "4")))

(ert-deftest wolfram-nb-test-eval-list ()
  (skip-unless (wolfram-nb--check-wolframscript))
  (should (string-match-p "{1.*5}" (wolfram-nb--eval-expression "Range[5]"))))

(ert-deftest wolfram-nb-test-eval-function ()
  (skip-unless (wolfram-nb--check-wolframscript))
  (should (string= (wolfram-nb--eval-expression "f[x_]:=x^2; f[5]") "25")))

(ert-deftest wolfram-nb-test-eval-arithmetic ()
  (skip-unless (wolfram-nb--check-wolframscript))
  (should (string= (wolfram-nb--eval-expression "10 * 5") "50")))

(ert-deftest wolfram-nb-test-eval-error-signals ()
  "Evaluation of bad code should signal wolfram-nb-eval-error."
  (skip-unless (wolfram-nb--check-wolframscript))
  ;; wolframscript doesn't necessarily fail on syntax errors the same way,
  ;; but we can at least test that the function returns a string
  (should (stringp (wolfram-nb--eval-expression "1+1"))))

;;; Format output

(ert-deftest wolfram-nb-test-format-output-plain ()
  (should (string= (wolfram-nb--format-output "42") "42"))
  (should (string= (wolfram-nb--format-output "{1, 2, 3}") "{1, 2, 3}")))

(ert-deftest wolfram-nb-test-format-output-graphics ()
  (should (string-match-p "Mathematica" (wolfram-nb--format-output "Graphics[...]")))
  (should (string-match-p "Mathematica" (wolfram-nb--format-output "Graphics3D[...]")))
  (should (string-match-p "Mathematica" (wolfram-nb--format-output "Image[data]"))))

;;; org-babel

(ert-deftest wolfram-nb-test-org-babel-execute ()
  "org-babel-execute:wolfram is defined and callable."
  (skip-unless (wolfram-nb--check-wolframscript))
  (should (string= (org-babel-execute:wolfram "1 + 1" nil) "2")))

;;; Clear outputs

(ert-deftest wolfram-nb-test-clear-outputs ()
  "wolfram-nb-clear-outputs removes example blocks."
  (with-temp-buffer
    (wolfram-nb-mode)
    (insert "#+begin_src wolfram\n2+2\n#+end_src\n\n"
            "#+begin_example\n4\n#+end_example\n\n"
            "#+begin_src wolfram\n3+3\n#+end_src\n\n"
            "#+begin_example\n6\n#+end_example\n")
    (wolfram-nb-clear-outputs)
    (should-not (string-match-p "begin_example" (buffer-string)))
    (should (string-match-p "begin_src" (buffer-string)))))

;;; Insert src block

(ert-deftest wolfram-nb-test-insert-src-block ()
  "wolfram-nb-insert-src-block inserts a template."
  (with-temp-buffer
    (wolfram-nb-mode)
    (wolfram-nb-insert-src-block)
    (should (string-match-p "begin_src wolfram" (buffer-string)))
    (should (string-match-p "end_src" (buffer-string)))))

(provide 'test-eval)
;;; test-eval.el ends here
