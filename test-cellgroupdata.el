;;; test-cellgroupdata.el --- Test CellGroupData unwrapping -*- lexical-binding: t; -*-

;;; Commentary:
;; Test the CellGroupData unwrapping functionality

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defun test-cellgroupdata-complex-notebook ()
  "Test parsing complex notebook with CellGroupData."
  (message "╔════════════════════════════════════════════════════════╗")
  (message "║       CellGroupData Unwrapping - Full Test           ║")
  (message "╚════════════════════════════════════════════════════════╝\n")
  
  (let ((file "/Users/juangonzalez/Scratch/JuanWeeklyReports.nb")
        (success t))
    
    (unless (file-exists-p file)
      (error "Test file not found: %s" file))
    
    ;; Test 1: Parse the notebook
    (message "Test 1: Parsing complex notebook...")
    (condition-case err
        (let ((start-time (current-time))
              (cells (wolfram-nb--parse-notebook file)))
          (let ((elapsed (float-time (time-subtract (current-time) start-time))))
            (message "  ✓ Parsed %d cells in %.2f seconds" (length cells) elapsed)
            (when (< (length cells) 500)
              (message "  ⚠ Warning: Expected more cells (got %d, typical is 600+)" 
                       (length cells))
              (setq success nil))
            
            ;; Test 2: Verify cell types
            (message "\nTest 2: Verifying cell type diversity...")
            (let ((cell-types (make-hash-table :test 'equal)))
              (dolist (cell cells)
                (puthash (plist-get cell :style) t cell-types))
              (let ((type-count (hash-table-count cell-types)))
                (if (>= type-count 10)
                    (message "  ✓ Found %d different cell types" type-count)
                  (message "  ✗ Only found %d cell types (expected 10+)" type-count)
                  (setq success nil))))
            
            ;; Test 3: Convert to org-mode
            (message "\nTest 3: Converting to org-mode...")
            (condition-case err
                (let ((start-time (current-time))
                      (org-text (wolfram-nb--cells-to-org cells)))
                  (let ((elapsed (float-time (time-subtract (current-time) start-time))))
                    (message "  ✓ Converted to org in %.2f seconds" elapsed)
                    (message "    Output length: %d characters" (length org-text))
                    
                    ;; Save to file
                    (let ((output-file "/tmp/juanweekly-converted.org"))
                      (with-temp-file output-file
                        (insert org-text))
                      (message "    Saved to: %s" output-file))
                    
                    ;; Show structure
                    (let ((sections (length (split-string org-text "^\\* " t)))
                          (subsections (length (split-string org-text "^\\*\\* " t)))
                          (code-blocks (length (split-string org-text "#+begin_src" t))))
                      (message "\n  Org structure:")
                      (message "    Sections: ~%d" sections)
                      (message "    Subsections: ~%d" subsections)
                      (message "    Code blocks: %d" code-blocks))))
              (error
               (message "  ✗ Conversion failed: %s" (error-message-string err))
               (setq success nil)))
            
            ;; Test 4: Check for Chapter/Section/Title hierarchy
            (message "\nTest 4: Checking document hierarchy...")
            (let ((has-title nil)
                  (has-chapter nil)
                  (has-section nil)
                  (has-subsection nil))
              (dolist (cell cells)
                (let ((style (plist-get cell :style)))
                  (when (string= style "Title") (setq has-title t))
                  (when (string= style "Chapter") (setq has-chapter t))
                  (when (string= style "Section") (setq has-section t))
                  (when (string= style "Subsection") (setq has-subsection t))))
              
              (if has-title
                  (message "  ✓ Has Title")
                (message "  ✗ Missing Title"))
              (if has-chapter
                  (message "  ✓ Has Chapters")
                (message "  - No Chapters (optional)"))
              (if has-section
                  (message "  ✓ Has Sections")
                (message "  ✗ Missing Sections")
                (setq success nil))
              (if has-subsection
                  (message "  ✓ Has Subsections")
                (message "  ✗ Missing Subsections")
                (setq success nil)))))
      (error
       (message "  ✗ Parse failed: %s" (error-message-string err))
       (setq success nil)))
    
    ;; Final result
    (message "\n╔════════════════════════════════════════════════════════╗")
    (if success
        (message "║              ✓ ALL TESTS PASSED                       ║")
      (message "║              ⚠ SOME TESTS HAD WARNINGS                ║"))
    (message "╚════════════════════════════════════════════════════════╝")
    
    success))

;; Run the test
(test-cellgroupdata-complex-notebook)

(provide 'test-cellgroupdata)
;;; test-cellgroupdata.el ends here
