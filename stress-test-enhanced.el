;;; stress-test-enhanced.el --- Stress test with enhanced parser -*- lexical-binding: t; -*-

;;; Commentary:
;; Test the enhanced parser with the complex notebook

;;; Code:

(add-to-list 'load-path default-directory)
(require 'wolfram-nb-mode)
(require 'wolfram-nb-parser-enhanced)

(defvar stress-test-notebook "/Users/juangonzalez/Scratch/JuanWeeklyReports.nb"
  "Path to the complex test notebook.")

(defun stress-test-enhanced-parse ()
  "Test the enhanced parser on the complex notebook."
  (message "╔════════════════════════════════════════════════════════╗")
  (message "║     Enhanced Parser - Stress Test                    ║")
  (message "╚════════════════════════════════════════════════════════╝\n")
  
  (unless (file-exists-p stress-test-notebook)
    (error "Test notebook not found: %s" stress-test-notebook))
  
  (message "File: %s\n" stress-test-notebook)
  
  (condition-case err
      (let ((start-time (current-time)))
        (message "Parsing with enhanced parser...")
        (let ((cells (wolfram-nb-enhanced-parse-notebook stress-test-notebook)))
          (let ((elapsed (float-time (time-subtract (current-time) start-time))))
            
            (message "\n✓ Parse successful!")
            (message "  Cells extracted: %d" (length cells))
            (message "  Time: %.2f seconds" elapsed)
            (message "  Rate: %.0f cells/sec" (/ (length cells) (max elapsed 0.001)))
            
            ;; Analyze cell types
            (let ((cell-types (make-hash-table :test 'equal)))
              (dolist (cell cells)
                (let ((style (plist-get cell :style)))
                  (puthash style (1+ (gethash style cell-types 0)) cell-types)))
              
              (message "\nCell types distribution:")
              (let ((sorted-types '()))
                (maphash (lambda (style count)
                          (push (cons style count) sorted-types))
                        cell-types)
                (setq sorted-types (sort sorted-types 
                                        (lambda (a b) (> (cdr a) (cdr b)))))
                (dolist (entry sorted-types)
                  (message "  %-20s: %4d" (car entry) (cdr entry)))))
            
            ;; Show sample cells
            (message "\nSample cells (first 5):")
            (dotimes (i (min 5 (length cells)))
              (let* ((cell (nth i cells))
                     (style (plist-get cell :style))
                     (content (plist-get cell :content))
                     (metadata (plist-get cell :metadata))
                     (preview (if (> (length content) 50)
                                 (concat (substring content 0 50) "...")
                               content)))
                (message "  [%d] %s: %s%s" 
                         i 
                         style 
                         preview
                         (if metadata 
                             (format " (uuid: ...%s)" 
                                    (substring (cdr (assoc 'uuid metadata)) -8))
                           ""))))
            
            cells)))
    (error
     (message "\n✗ Parse failed: %s" (error-message-string err))
     nil)))

(defun stress-test-enhanced-conversion ()
  "Test converting the parsed notebook with enhanced parser."
  (message "\n\n╔════════════════════════════════════════════════════════╗")
  (message "║     Testing Org Conversion                           ║")
  (message "╚════════════════════════════════════════════════════════╝\n")
  
  (condition-case err
      (let* ((cells (wolfram-nb-enhanced-parse-notebook stress-test-notebook))
             (start-time (current-time))
             (org-text (wolfram-nb--cells-to-org cells))
             (elapsed (float-time (time-subtract (current-time) start-time))))
        
        (message "✓ Conversion successful!")
        (message "  Input cells: %d" (length cells))
        (message "  Output length: %d characters" (length org-text))
        (message "  Time: %.2f seconds" elapsed)
        
        ;; Count org elements
        (let ((sections (length (split-string org-text "^\\* " t)))
              (subsections (length (split-string org-text "^\\*\\* " t)))
              (code-blocks (length (split-string org-text "#+begin_src" t))))
          (message "\nOrg structure:")
          (message "  Sections: ~%d" sections)
          (message "  Subsections: ~%d" subsections)
          (message "  Code blocks: %d" code-blocks))
        
        ;; Save for inspection
        (let ((output-file "/tmp/stress-test-enhanced.org"))
          (with-temp-file output-file
            (insert org-text))
          (message "\n  Saved to: %s" output-file))
        
        ;; Show preview
        (message "\nOrg output preview (first 800 chars):")
        (message "───────────────────────────────────────")
        (message "%s" (substring org-text 0 (min 800 (length org-text))))
        (message "───────────────────────────────────────")
        
        t)
    (error
     (message "\n✗ Conversion failed: %s" (error-message-string err))
     nil)))

(defun run-enhanced-stress-test ()
  "Run the enhanced stress test."
  (let ((cells (stress-test-enhanced-parse)))
    (when cells
      (stress-test-enhanced-conversion)))
  
  (message "\n╔════════════════════════════════════════════════════════╗")
  (message "║          Enhanced Stress Test Complete               ║")
  (message "╚════════════════════════════════════════════════════════╝"))

;; Run the test
(run-enhanced-stress-test)

(provide 'stress-test-enhanced)
;;; stress-test-enhanced.el ends here
