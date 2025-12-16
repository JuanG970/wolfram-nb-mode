;;; integration-test.el --- Integration test for wolfram-nb-mode using ERT -*- lexical-binding: t; -*-

;;; Commentary:
;; Full integration test simulating real usage

;;; Code:

(require 'ert)
(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defvar integration-test-file "/tmp/integration-test.nb"
  "Test file for integration tests.")

;;; Helper Functions

(defun integration-test--create-org-content ()
  "Create sample org content for testing."
  (concat "* Test Notebook\n\n"
          "This is a test of the complete workflow.\n\n"
          "** Features\n\n"
          "Testing the following:\n\n"
          "- Creating notebooks\n"
          "- Editing content\n"
          "- Saving to .nb format\n\n"
          "** Code Example\n\n"
          "#+begin_src wolfram\n"
          "sum[a_, b_] := a + b\n"
          "sum[5, 3]\n"
          "#+end_src\n\n"
          "* Conclusion\n\n"
          "If you can read this in Mathematica, it works!\n"))

;;; Integration Tests

(ert-deftest integration-test-create-notebook ()
  "Test creating a new notebook from org content."
  (let* ((org-text (integration-test--create-org-content))
         (cells (wolfram-nb--org-to-cells org-text))
         (nb-text (wolfram-nb--cells-to-notebook cells)))
    (should (> (length cells) 0))
    (should (stringp nb-text))
    (should (string-match-p "Notebook\\[{" nb-text))
    ;; Save to file
    (with-temp-file integration-test-file
      (insert nb-text))))

(ert-deftest integration-test-read-notebook ()
  "Test reading a notebook file back."
  ;; First create the notebook
  (let* ((org-text (integration-test--create-org-content))
         (cells (wolfram-nb--org-to-cells org-text))
         (nb-text (wolfram-nb--cells-to-notebook cells)))
    (with-temp-file integration-test-file
      (insert nb-text)))
  
  ;; Now read it back
  (let* ((cells (wolfram-nb--parse-notebook integration-test-file))
         (org-text (wolfram-nb--cells-to-org cells)))
    (should (> (length cells) 0))
    (should (stringp org-text))
    (should (> (length org-text) 0))))

(ert-deftest integration-test-modify-notebook ()
  "Test modifying and saving a notebook."
  ;; Create initial notebook
  (let* ((org-text (integration-test--create-org-content))
         (cells (wolfram-nb--org-to-cells org-text))
         (nb-text (wolfram-nb--cells-to-notebook cells)))
    (with-temp-file integration-test-file
      (insert nb-text)))
  
  ;; Read, modify, and save
  (let* ((cells (wolfram-nb--parse-notebook integration-test-file))
         (org-text (wolfram-nb--cells-to-org cells))
         (modified-org (concat org-text "\n** New Section\n\nAdded dynamically!\n"))
         (new-cells (wolfram-nb--org-to-cells modified-org))
         (new-nb (wolfram-nb--cells-to-notebook new-cells)))
    (should (> (length new-cells) (length cells)))
    (with-temp-file integration-test-file
      (insert new-nb))))

(ert-deftest integration-test-verify-modification ()
  "Test verifying a modified notebook."
  ;; Create and modify notebook
  (let* ((org-text (integration-test--create-org-content))
         (cells (wolfram-nb--org-to-cells org-text))
         (nb-text (wolfram-nb--cells-to-notebook cells)))
    (with-temp-file integration-test-file
      (insert nb-text)))
  
  (let* ((cells (wolfram-nb--parse-notebook integration-test-file))
         (org-text (wolfram-nb--cells-to-org cells))
         (modified-org (concat org-text "\n** New Section\n\nAdded dynamically!\n"))
         (new-cells (wolfram-nb--org-to-cells modified-org))
         (new-nb (wolfram-nb--cells-to-notebook new-cells)))
    (with-temp-file integration-test-file
      (insert new-nb)))
  
  ;; Verify
  (let ((final-cells (wolfram-nb--parse-notebook integration-test-file)))
    (should (> (length final-cells) 0))
    (should (listp final-cells))))

(ert-deftest integration-test-file-format ()
  "Test that saved files have correct .nb format."
  ;; Create notebook
  (let* ((org-text (integration-test--create-org-content))
         (cells (wolfram-nb--org-to-cells org-text))
         (nb-text (wolfram-nb--cells-to-notebook cells)))
    (with-temp-file integration-test-file
      (insert nb-text)))
  
  ;; Check format
  (with-temp-buffer
    (insert-file-contents integration-test-file)
    (let ((content (buffer-string)))
      (should (string-match-p "^Notebook\\[{" content))
      (should (string-match-p "Cell\\[" content))
      (should (string-match-p "}\\]$" content)))))

(ert-deftest integration-test-roundtrip-fidelity ()
  "Test that org -> nb -> org roundtrip preserves content."
  (let* ((original-org (integration-test--create-org-content))
         (cells1 (wolfram-nb--org-to-cells original-org))
         (nb-text (wolfram-nb--cells-to-notebook cells1))
         (cells2 (wolfram-nb--parse-notebook 
                  (with-temp-file integration-test-file
                    (insert nb-text)
                    integration-test-file)))
         (final-org (wolfram-nb--cells-to-org cells2)))
    ;; Should have similar number of cells
    (should (= (length cells1) (length cells2)))
    ;; Should contain key phrases
    (should (string-match-p "Test Notebook" final-org))
    (should (string-match-p "Features" final-org))
    (should (string-match-p "Conclusion" final-org))))

(provide 'integration-test)
;;; integration-test.el ends here
