;;; stress-test-robust.el --- Stress test with robust parser -*- lexical-binding: t; -*-

;;; Commentary:
;; Test the robust parser with the complex notebook

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)
(require 'wolfram-nb-parser-robust)

(defvar stress-test-notebook "/Users/juangonzalez/Scratch/JuanWeeklyReports.nb")

(defun run-robust-stress-test (&optional max-cells)
  "Run stress test with robust parser, limiting to MAX-CELLS."
  (setq max-cells (or max-cells 1000))  ; Default limit for testing
  
  (message "╔════════════════════════════════════════════════════════╗")
  (message "║     Robust Parser - Stress Test                      ║")
  (message "╚════════════════════════════════════════════════════════╝\n")
  
  (message "File: %s" stress-test-notebook)
  (message "Max cells to extract: %d\n" max-cells)
  
  (condition-case err
      (let ((start-time (current-time))
            (cells (wolfram-nb-robust-parse-notebook stress-test-notebook max-cells)))
        
        (let ((elapsed (float-time (time-subtract (current-time) start-time))))
          (message "\n✓ Parse successful!")
          (message "  Cells extracted: %d" (length cells))
          (message "  Time: %.2f seconds" elapsed)
          (message "  Rate: %.0f cells/sec" (/ (length cells) (max elapsed 0.001)))
          
          ;; Analyze cell types
          (let ((cell-types (make-hash-table :test 'equal))
                (cell-type-breakdown (make-hash-table :test 'equal)))
            (dolist (cell cells)
              (let ((style (plist-get cell :style))
                    (type (plist-get cell :type)))
                (puthash style (1+ (gethash style cell-types 0)) cell-types)
                (puthash type (1+ (gethash type cell-type-breakdown 0)) cell-type-breakdown)))
            
            (message "\nCell styles (top 10):")
            (let ((sorted-types '()))
              (maphash (lambda (style count)
                        (push (cons style count) sorted-types))
                      cell-types)
              (setq sorted-types (sort sorted-types 
                                      (lambda (a b) (> (cdr a) (cdr b)))))
              (dotimes (i (min 10 (length sorted-types)))
                (let ((entry (nth i sorted-types)))
                  (message "  %-25s: %4d" (car entry) (cdr entry)))))
            
            (message "\nCell type breakdown:")
            (maphash (lambda (type count)
                      (message "  %-15s: %4d" type count))
                    cell-type-breakdown))
          
          ;; Show samples
          (message "\nSample cells (first 8):")
          (dotimes (i (min 8 (length cells)))
            (let* ((cell (nth i cells))
                   (style (plist-get cell :style))
                   (type (plist-get cell :type))
                   (content (plist-get cell :content))
                   (preview (if (> (length content) 60)
                               (concat (substring content 0 60) "...")
                             content)))
              (message "  [%d] %-15s (%-10s): %s" 
                       i style type preview)))
          
          ;; Test conversion
          (message "\nTesting org conversion...")
          (let ((start-time (current-time))
                (org-text (wolfram-nb--cells-to-org cells)))
            (let ((elapsed (float-time (time-subtract (current-time) start-time))))
              (message "  ✓ Conversion successful!")
              (message "    Output: %d characters" (length org-text))
              (message "    Time: %.2f seconds" elapsed)
              
              ;; Save to file
              (let ((output-file "/tmp/stress-test-robust.org"))
                (with-temp-file output-file
                  (insert org-text))
                (message "    Saved to: %s" output-file))
              
              ;; Show preview
              (message "\n  Org preview (first 500 chars):")
              (message "  ───────────────────────────────────")
              (message "%s" (substring org-text 0 (min 500 (length org-text))))
              (message "  ───────────────────────────────────")))
          
          cells))
    (error
     (message "\n✗ Test failed: %s" (error-message-string err))
     nil))
  
  (message "\n╔════════════════════════════════════════════════════════╗")
  (message "║          Robust Stress Test Complete                 ║")
  (message "╚════════════════════════════════════════════════════════╝"))

;; Run with limit
(run-robust-stress-test 1000)

(provide 'stress-test-robust)
;;; stress-test-robust.el ends here
