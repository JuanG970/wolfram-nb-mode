;;; integration-test.el --- Integration tests for wolfram-nb-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; End-to-end workflow tests: create, read, modify, save, roundtrip.

;;; Code:

(require 'ert)
(require 'cl-lib)
(add-to-list 'load-path
             (file-name-directory
              (directory-file-name
               (file-name-directory (or load-file-name buffer-file-name default-directory)))))
(require 'wolfram-nb-mode)

(defvar integration-test--file nil
  "Temp file for current test.")

(defun integration-test--setup ()
  "Create a temporary .nb file path."
  (setq integration-test--file (make-temp-file "wolfram-nb-integ" nil ".nb")))

(defun integration-test--teardown ()
  "Clean up temp file."
  (when (and integration-test--file (file-exists-p integration-test--file))
    (delete-file integration-test--file)))

(defun integration-test--sample-org ()
  "Return sample Org content covering all cell types."
  (concat "#+TITLE: Integration Test\n\n"
          "* Chapter One\n\n"
          "This is paragraph text.\n\n"
          "** Features\n\n"
          "Testing the workflow:\n\n"
          "- Creating notebooks\n"
          "- Editing content\n"
          "- Saving to .nb format\n\n"
          "*** Subsection\n\n"
          "**** Subsubsection\n\n"
          "** Code Example\n\n"
          "#+begin_src wolfram\n"
          "f[x_] := x^2\n"
          "f[5]\n"
          "#+end_src\n\n"
          "#+begin_example\n25\n#+end_example\n\n"
          "* Conclusion\n\n"
          "Done!\n"))

;;; Tests

(ert-deftest integration-test-create-from-org ()
  "Create a notebook from Org content and verify Cell structure."
  (integration-test--setup)
  (unwind-protect
      (let* ((org-text (integration-test--sample-org))
             (cells (wolfram-nb--org-to-cells org-text))
             (nb (wolfram-nb--cells-to-notebook cells)))
        (should (> (length cells) 8))
        (should (string-match-p "Notebook\\[{" nb))
        (should (cl-some (lambda (c) (string-match-p "\"Title\"" c)) cells))
        (should (cl-some (lambda (c) (string-match-p "\"Chapter\"" c)) cells))
        (should (cl-some (lambda (c) (string-match-p "\"Section\"" c)) cells))
        (should (cl-some (lambda (c) (string-match-p "\"Input\"" c)) cells))
        (with-temp-file integration-test--file (insert nb)))
    (integration-test--teardown)))

(ert-deftest integration-test-read-back ()
  "Write a notebook, read it back, verify cells."
  (integration-test--setup)
  (unwind-protect
      (let* ((cells (wolfram-nb--org-to-cells (integration-test--sample-org)))
             (nb (wolfram-nb--cells-to-notebook cells)))
        (with-temp-file integration-test--file (insert nb))
        (let ((cells2 (wolfram-nb--parse-notebook integration-test--file)))
          (should (= (length cells) (length cells2)))
          (should (wolfram-nb-cell-p (car cells2)))))
    (integration-test--teardown)))

(ert-deftest integration-test-modify-and-save ()
  "Read notebook, add content, save, verify more cells."
  (integration-test--setup)
  (unwind-protect
      (progn
        (let* ((cells (wolfram-nb--org-to-cells (integration-test--sample-org)))
               (nb (wolfram-nb--cells-to-notebook cells)))
          (with-temp-file integration-test--file (insert nb)))
        (let* ((cells1 (wolfram-nb--parse-notebook integration-test--file))
               (org (wolfram-nb--cells-to-org cells1))
               (org2 (concat org "\n*** Added Section\n\nNew text.\n"))
               (cells2 (wolfram-nb--org-to-cells org2))
               (nb2 (wolfram-nb--cells-to-notebook cells2)))
          (with-temp-file integration-test--file (insert nb2))
          (should (> (length cells2) (length cells1)))))
    (integration-test--teardown)))

(ert-deftest integration-test-file-format-valid ()
  "Saved .nb file has valid Notebook[{...}] structure."
  (integration-test--setup)
  (unwind-protect
      (let* ((cells (wolfram-nb--org-to-cells (integration-test--sample-org)))
             (nb (wolfram-nb--cells-to-notebook cells)))
        (with-temp-file integration-test--file (insert nb))
        (with-temp-buffer
          (insert-file-contents integration-test--file)
          (let ((content (buffer-string)))
            (should (string-match-p "\\`Notebook\\[{" content))
            (should (string-match-p "Cell\\[" content))
            (should (string-match-p "}\\]" content)))))
    (integration-test--teardown)))

(ert-deftest integration-test-roundtrip-fidelity ()
  "org -> nb -> org roundtrip preserves key content."
  (integration-test--setup)
  (unwind-protect
      (let* ((orig-org (integration-test--sample-org))
             (cells1 (wolfram-nb--org-to-cells orig-org))
             (nb (wolfram-nb--cells-to-notebook cells1)))
        (with-temp-file integration-test--file (insert nb))
        (let* ((cells2 (wolfram-nb--parse-notebook integration-test--file))
               (org2 (wolfram-nb--cells-to-org cells2)))
          (should (= (length cells1) (length cells2)))
          (should (string-match-p "Integration Test" org2))
          (should (string-match-p "Features" org2))
          (should (string-match-p "Conclusion" org2))))
    (integration-test--teardown)))

(ert-deftest integration-test-all-cell-types-roundtrip ()
  "Every supported style survives roundtrip."
  (integration-test--setup)
  (unwind-protect
      (let* ((cells (wolfram-nb--org-to-cells (integration-test--sample-org)))
             (nb (wolfram-nb--cells-to-notebook cells)))
        (with-temp-file integration-test--file (insert nb))
        (let* ((cells2 (wolfram-nb--parse-notebook integration-test--file))
               (styles (mapcar #'wolfram-nb-cell-style cells2)))
          (should (member "Title" styles))
          (should (member "Chapter" styles))
          (should (member "Section" styles))
          (should (member "Subsection" styles))
          (should (member "Subsubsection" styles))
          (should (member "Text" styles))
          (should (member "Item" styles))
          (should (member "Input" styles))
          (should (member "Output" styles))))
    (integration-test--teardown)))

(ert-deftest integration-test-empty-notebook ()
  "Empty notebook roundtrips."
  (integration-test--setup)
  (unwind-protect
      (progn
        (with-temp-file integration-test--file
          (insert "Notebook[{\n}]\n"))
        (should (= (length (wolfram-nb--parse-notebook integration-test--file)) 0)))
    (integration-test--teardown)))

(ert-deftest integration-test-buffer-workflow ()
  "Simulate complete buffer workflow: open, edit, save, reopen."
  (integration-test--setup)
  (unwind-protect
      (let* ((cells (wolfram-nb--org-to-cells (integration-test--sample-org)))
             (nb (wolfram-nb--cells-to-notebook cells)))
        (with-temp-file integration-test--file (insert nb))
        ;; Simulate wolfram-nb-open in a buffer
        (with-temp-buffer
          (wolfram-nb-mode)
          (let ((opened-cells (wolfram-nb--parse-notebook integration-test--file)))
            (insert (wolfram-nb--cells-to-org opened-cells))
            (setq wolfram-nb--original-file integration-test--file
                  wolfram-nb--cell-count (length opened-cells))
            ;; Append content
            (goto-char (point-max))
            (insert "\n** Dynamically Added\n\nRuntime content.\n")
            ;; Save
            (wolfram-nb-save)
            ;; Verify
            (let ((final (wolfram-nb--parse-notebook integration-test--file)))
              (should (> (length final) (length opened-cells)))))))
    (integration-test--teardown)))

(ert-deftest integration-test-notebook-options-preserved ()
  "Notebook-level options survive roundtrip."
  (integration-test--setup)
  (unwind-protect
      (progn
        (with-temp-file integration-test--file
          (insert "Notebook[{\nCell[\"Hello\", \"Text\"]\n},\n"
                  "FrontEndVersion->\"14.0\",\n"
                  "StyleDefinitions->\"Default.nb\"]\n"))
        (with-temp-buffer
          (wolfram-nb-mode)
          (let ((cells (wolfram-nb--parse-notebook integration-test--file)))
            (should (= (length cells) 1))
            ;; notebook-options should be set
            (should (and wolfram-nb--notebook-options
                         (string-match-p "FrontEndVersion"
                                         wolfram-nb--notebook-options))))))
    (integration-test--teardown)))

(provide 'integration-test)
;;; integration-test.el ends here
