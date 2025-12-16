;;; test-mode.el --- Test script for wolfram-nb-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Test basic functionality of wolfram-nb-mode

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defun test-parse-notebook ()
  "Test parsing a notebook file."
  (message "Testing notebook parsing...")
  (let ((cells (wolfram-nb--parse-notebook "test.nb")))
    (message "Parsed %d cells" (length cells))
    (dolist (cell cells)
      (message "  Cell: style=%s, content=%s"
               (plist-get cell :style)
               (substring (plist-get cell :content) 0 (min 30 (length (plist-get cell :content))))))
    (if (> (length cells) 0)
        (message "✓ Parse test PASSED")
      (error "✗ Parse test FAILED"))))

(defun test-cell-to-org ()
  "Test converting cells to org format."
  (message "\nTesting cell to org conversion...")
  (let* ((test-cells (list
                      (list :content "Test Section" :style "Section")
                      (list :content "Some text here" :style "Text")
                      (list :content "• List item" :style "Item")
                      (list :content "x = 5" :style "Code")))
         (org-text (wolfram-nb--cells-to-org test-cells)))
    (message "Generated org text:\n%s" org-text)
    (if (and (string-match-p "\\* Test Section" org-text)
             (string-match-p "Some text here" org-text)
             (string-match-p "- List item" org-text)
             (string-match-p "begin_src wolfram" org-text))
        (message "✓ Cell-to-org test PASSED")
      (error "✗ Cell-to-org test FAILED"))))

(defun test-org-to-cells ()
  "Test converting org format to cells."
  (message "\nTesting org to cells conversion...")
  (let* ((org-text "* My Section\n\nSome text\n\n- Item one\n- Item two\n\n#+begin_src wolfram\nPlot[x^2, {x, 0, 1}]\n#+end_src\n")
         (cells (wolfram-nb--org-to-cells org-text)))
    (message "Generated %d cells" (length cells))
    (dolist (cell cells)
      (message "  %s" cell))
    (if (> (length cells) 0)
        (message "✓ Org-to-cells test PASSED")
      (error "✗ Org-to-cells test FAILED"))))

(defun test-roundtrip ()
  "Test roundtrip: notebook -> org -> cells -> notebook."
  (message "\nTesting roundtrip conversion...")
  (let* ((cells1 (wolfram-nb--parse-notebook "test.nb"))
         (org-text (wolfram-nb--cells-to-org cells1))
         (cells2 (wolfram-nb--org-to-cells org-text))
         (notebook-text (wolfram-nb--cells-to-notebook cells2)))
    (message "Original cells: %d" (length cells1))
    (message "Final cells: %d" (length cells2))
    (message "Final notebook preview:\n%s" 
             (substring notebook-text 0 (min 500 (length notebook-text))))
    (if (and (> (length cells2) 0)
             (string-match-p "Notebook\\[{" notebook-text))
        (message "✓ Roundtrip test PASSED")
      (error "✗ Roundtrip test FAILED"))))

(defun test-escape-unescape ()
  "Test string escaping and unescaping."
  (message "\nTesting escape/unescape...")
  (let* ((original "Test \"quoted\" with\\backslash and\nnewline")
         (escaped (wolfram-nb--escape-string original))
         (unescaped (wolfram-nb--unescape-string escaped)))
    (message "Original:   %S" original)
    (message "Escaped:    %S" escaped)
    (message "Unescaped:  %S" unescaped)
    (if (string= original unescaped)
        (message "✓ Escape/unescape test PASSED")
      (error "✗ Escape/unescape test FAILED: %S != %S" original unescaped))))

(defun run-all-tests ()
  "Run all tests."
  (message "=== Running wolfram-nb-mode tests ===\n")
  (condition-case err
      (progn
        (test-escape-unescape)
        (test-parse-notebook)
        (test-cell-to-org)
        (test-org-to-cells)
        (test-roundtrip)
        (message "\n=== ALL TESTS PASSED ==="))
    (error
     (message "\n=== TEST FAILED: %s ===" (error-message-string err))
     (kill-emacs 1))))

;; Run tests
(run-all-tests)

(provide 'test-mode)
;;; test-mode.el ends here
