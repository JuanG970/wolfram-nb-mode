;;; integration-test.el --- Integration test for wolfram-nb-mode -*- lexical-binding: t; -*-

;;; Commentary:
;; Full integration test simulating real usage

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defun integration-test ()
  "Run a full integration test."
  (message "\n=== Wolfram NB Mode Integration Test ===\n")
  
  ;; Test 1: Create a new notebook
  (message "Test 1: Creating a new notebook...")
  (let ((test-file "/tmp/integration-test.nb"))
    
    ;; Create org content
    (with-temp-buffer
      (insert "* Test Notebook\n\n")
      (insert "This is a test of the complete workflow.\n\n")
      (insert "** Features\n\n")
      (insert "Testing the following:\n\n")
      (insert "- Creating notebooks\n")
      (insert "- Editing content\n")
      (insert "- Saving to .nb format\n\n")
      (insert "** Code Example\n\n")
      (insert "#+begin_src wolfram\n")
      (insert "sum[a_, b_] := a + b\n")
      (insert "sum[5, 3]\n")
      (insert "#+end_src\n\n")
      (insert "* Conclusion\n\n")
      (insert "If you can read this in Mathematica, it works!\n")
      
      ;; Convert to cells and save
      (let* ((org-text (buffer-string))
             (cells (wolfram-nb--org-to-cells org-text))
             (nb-text (wolfram-nb--cells-to-notebook cells)))
        (with-temp-file test-file
          (insert nb-text))
        (message "  Created %s with %d cells" test-file (length cells))))
    
    ;; Test 2: Read it back
    (message "\nTest 2: Reading the notebook back...")
    (let* ((cells (wolfram-nb--parse-notebook test-file))
           (org-text (wolfram-nb--cells-to-org cells)))
      (message "  Read back %d cells" (length cells))
      (message "  Org representation (first 200 chars):\n%s..." 
               (substring org-text 0 (min 200 (length org-text)))))
    
    ;; Test 3: Modify and save
    (message "\nTest 3: Modifying and saving...")
    (let* ((cells (wolfram-nb--parse-notebook test-file))
           (org-text (wolfram-nb--cells-to-org cells))
           (modified-org (concat org-text "\n** New Section\n\nAdded dynamically!\n")))
      (let* ((new-cells (wolfram-nb--org-to-cells modified-org))
             (new-nb (wolfram-nb--cells-to-notebook new-cells)))
        (with-temp-file test-file
          (insert new-nb))
        (message "  Modified notebook now has %d cells (was %d)" 
                 (length new-cells) (length cells))))
    
    ;; Test 4: Verify modification
    (message "\nTest 4: Verifying modification...")
    (let ((final-cells (wolfram-nb--parse-notebook test-file)))
      (message "  Final cell count: %d" (length final-cells))
      (message "  Last cell: %S" (car (last final-cells))))
    
    ;; Test 5: Check file contents
    (message "\nTest 5: Checking saved file format...")
    (with-temp-buffer
      (insert-file-contents test-file)
      (let ((content (buffer-string)))
        (if (and (string-match-p "^Notebook\\[{" content)
                 (string-match-p "Cell\\[" content)
                 (string-match-p "}\\]$" content))
            (message "  ✓ File format is valid")
          (error "  ✗ Invalid file format"))))
    
    (message "\n=== Integration Test Complete ===")
    (message "Generated test file: %s" test-file)
    (message "\nYou can open this file in Mathematica to verify!")
    
    ;; Display the final notebook
    (message "\n=== Final Notebook Content ===")
    (with-temp-buffer
      (insert-file-contents test-file)
      (message "%s" (buffer-string)))))

;; Run the test
(condition-case err
    (progn
      (integration-test)
      (message "\n✓ ALL INTEGRATION TESTS PASSED"))
  (error
   (message "\n✗ INTEGRATION TEST FAILED: %s" (error-message-string err))
   (kill-emacs 1)))

(provide 'integration-test)
;;; integration-test.el ends here
