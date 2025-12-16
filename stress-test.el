;;; stress-test.el --- Stress test with complex notebook -*- lexical-binding: t; -*-

;;; Commentary:
;; Test parsing of a real, complex Wolfram notebook with Dynamic content

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)

(defvar stress-test-notebook "/Users/juangonzalez/Scratch/JuanWeeklyReports.nb"
  "Path to the complex test notebook.")

(defun stress-test--count-lines (file)
  "Count lines in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (count-lines (point-min) (point-max))))

(defun stress-test--count-cell-starts (file)
  "Count Cell[ occurrences in FILE."
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^Cell\\[" nil t)
        (setq count (1+ count)))
      count)))

(defun stress-test-analyze-structure ()
  "Analyze the structure of the complex notebook."
  (message "\n=== Analyzing Complex Notebook Structure ===\n")
  
  (unless (file-exists-p stress-test-notebook)
    (error "Test notebook not found: %s" stress-test-notebook))
  
  (let ((lines (stress-test--count-lines stress-test-notebook))
        (cell-starts (stress-test--count-cell-starts stress-test-notebook)))
    
    (message "File: %s" stress-test-notebook)
    (message "Lines: %d" lines)
    (message "Cell entries: %d" cell-starts)
    (message "Average lines per cell: %.1f" (/ (float lines) cell-starts))
    
    ;; Check for complex structures
    (with-temp-buffer
      (insert-file-contents stress-test-notebook)
      (goto-char (point-min))
      
      (let ((has-cellgroupdata (re-search-forward "CellGroupData" nil t))
            (has-boxdata (progn (goto-char (point-min)) 
                               (re-search-forward "BoxData" nil t)))
            (has-dynamic (progn (goto-char (point-min))
                               (re-search-forward "Dynamic" nil t)))
            (has-rowbox (progn (goto-char (point-min))
                              (re-search-forward "RowBox" nil t)))
            (has-expression-uuid (progn (goto-char (point-min))
                                       (re-search-forward "ExpressionUUID" nil t))))
        
        (message "\nComplex structures found:")
        (message "  CellGroupData: %s" (if has-cellgroupdata "YES" "NO"))
        (message "  BoxData: %s" (if has-boxdata "YES" "NO"))
        (message "  Dynamic: %s" (if has-dynamic "YES" "NO"))
        (message "  RowBox: %s" (if has-rowbox "YES" "NO"))
        (message "  ExpressionUUID: %s" (if has-expression-uuid "YES" "NO"))))))

(defun stress-test-parse-attempt ()
  "Attempt to parse the complex notebook."
  (message "\n=== Attempting to Parse Complex Notebook ===\n")
  
  (condition-case err
      (let ((start-time (current-time)))
        (message "Parsing...")
        (let ((cells (wolfram-nb--parse-notebook stress-test-notebook)))
          (let ((elapsed (float-time (time-subtract (current-time) start-time))))
            (message "✓ Parsed successfully!")
            (message "  Cells parsed: %d" (length cells))
            (message "  Time: %.2f seconds" elapsed)
            (message "  Rate: %.0f cells/sec" (/ (length cells) elapsed))
            
            ;; Analyze cell types
            (let ((cell-types (make-hash-table :test 'equal)))
              (dolist (cell cells)
                (let ((style (plist-get cell :style)))
                  (puthash style (1+ (gethash style cell-types 0)) cell-types)))
              
              (message "\nCell types found:")
              (maphash (lambda (style count)
                        (message "  %s: %d" style count))
                      cell-types))
            
            ;; Show sample cells
            (message "\nSample cells (first 3):")
            (dotimes (i (min 3 (length cells)))
              (let* ((cell (nth i cells))
                     (style (plist-get cell :style))
                     (content (plist-get cell :content))
                     (preview (if (> (length content) 60)
                                 (concat (substring content 0 60) "...")
                               content)))
                (message "  [%d] %s: %s" i style preview)))
            
            cells)))
    (error
     (message "✗ Parse failed: %s" (error-message-string err))
     nil)))

(defun stress-test-conversion ()
  "Test converting the parsed notebook to org format."
  (message "\n=== Testing Org Conversion ===\n")
  
  (condition-case err
      (let* ((cells (wolfram-nb--parse-notebook stress-test-notebook))
             (start-time (current-time))
             (org-text (wolfram-nb--cells-to-org cells))
             (elapsed (float-time (time-subtract (current-time) start-time))))
        
        (message "✓ Conversion successful!")
        (message "  Output length: %d characters" (length org-text))
        (message "  Time: %.2f seconds" elapsed)
        
        ;; Save to file for inspection
        (let ((output-file "/tmp/stress-test-output.org"))
          (with-temp-file output-file
            (insert org-text))
          (message "  Saved to: %s" output-file))
        
        ;; Show preview
        (message "\nOrg output preview (first 500 chars):")
        (message "%s..." (substring org-text 0 (min 500 (length org-text))))
        
        t)
    (error
     (message "✗ Conversion failed: %s" (error-message-string err))
     nil)))

(defun stress-test-roundtrip ()
  "Test roundtrip conversion."
  (message "\n=== Testing Roundtrip Conversion ===\n")
  
  (condition-case err
      (let* ((cells1 (wolfram-nb--parse-notebook stress-test-notebook))
             (org-text (wolfram-nb--cells-to-org cells1))
             (cells2 (wolfram-nb--org-to-cells org-text))
             (nb-text (wolfram-nb--cells-to-notebook cells2)))
        
        (message "✓ Roundtrip successful!")
        (message "  Original cells: %d" (length cells1))
        (message "  Final cells: %d" (length cells2))
        (message "  Retention rate: %.1f%%" 
                 (* 100.0 (/ (float (length cells2)) (length cells1))))
        
        ;; Save for comparison
        (with-temp-file "/tmp/stress-test-roundtrip.nb"
          (insert nb-text))
        (message "  Saved to: /tmp/stress-test-roundtrip.nb")
        
        t)
    (error
     (message "✗ Roundtrip failed: %s" (error-message-string err))
     nil)))

(defun run-stress-tests ()
  "Run all stress tests."
  (message "╔════════════════════════════════════════════════════════╗")
  (message "║          Wolfram NB Mode - Stress Test               ║")
  (message "╚════════════════════════════════════════════════════════╝")
  
  (stress-test-analyze-structure)
  (sit-for 1)
  
  (let ((parse-ok (stress-test-parse-attempt)))
    (when parse-ok
      (sit-for 1)
      (stress-test-conversion)
      (sit-for 1)
      (stress-test-roundtrip)))
  
  (message "\n╔════════════════════════════════════════════════════════╗")
  (message "║            Stress Test Complete                       ║")
  (message "╚════════════════════════════════════════════════════════╝"))

;; Run tests
(run-stress-tests)

(provide 'stress-test)
;;; stress-test.el ends here
