;;; wolfram-nb-parser-enhanced.el --- Enhanced parser for complex notebooks -*- lexical-binding: t; -*-

;;; Commentary:
;; Enhanced parser that handles:
;; - CellGroupData structures
;; - BoxData and complex formatting
;; - ExpressionUUID and other metadata
;; - Dynamic content (preserved as-is)

;;; Code:

(require 'wolfram-nb-mode)

;;; Enhanced Parsing for Complex Structures

(defun wolfram-nb-enhanced--extract-simple-text (cell-content)
  "Extract simple text from CELL-CONTENT, handling quotes and basic structures."
  (cond
   ;; Simple quoted string
   ((string-match "^\"\\(\\(?:[^\"\\\\]\\|\\\\.\\)*\\)\"" cell-content)
    (wolfram-nb--unescape-string (match-string 1 cell-content)))
   
   ;; BoxData or other complex structure - extract what we can
   ((string-match "BoxData\\[" cell-content)
    (wolfram-nb-enhanced--extract-from-boxdata cell-content))
   
   ;; Default: return as-is (will be code)
   (t cell-content)))

(defun wolfram-nb-enhanced--extract-from-boxdata (boxdata-str)
  "Extract readable content from BOXDATA-STR."
  ;; For now, just mark it as code content
  ;; In the future, we could parse RowBox, etc.
  (format "<BoxData content: %d chars>" (length boxdata-str)))

(defun wolfram-nb-enhanced--parse-cell-with-metadata (cell-str)
  "Parse CELL-STR which may include ExpressionUUID and other metadata.
Returns plist with :content, :style, and :metadata."
  (let ((content nil)
        (style nil)
        (metadata (list)))
    
    (cond
     ;; Pattern 1: Cell["text", "Style", ExpressionUUID->...]
     ((string-match "^Cell\\[\"\\(\\(?:[^\"\\\\]\\|\\\\.\\)*\\)\",[ \t\n]*\"\\([^\"]+\\)\"\\(.*\\)\\]$"
                    cell-str)
      (setq content (wolfram-nb--unescape-string (match-string 1 cell-str)))
      (setq style (match-string 2 cell-str))
      (let ((rest (match-string 3 cell-str)))
        (when (string-match "ExpressionUUID->\"\\([^\"]+\\)\"" rest)
          (push (cons 'uuid (match-string 1 rest)) metadata))))
     
     ;; Pattern 2: Cell[BoxData[...], "Code", ...]
     ((string-match "^Cell\\[\\(BoxData\\[.+\\)\\],[ \t\n]*\"\\([^\"]+\\)\"" cell-str)
      (setq content (match-string 1 cell-str))
      (setq style (match-string 2 cell-str)))
     
     ;; Pattern 3: Cell[CellGroupData[{...}]]
     ((string-match "^Cell\\[CellGroupData\\[" cell-str)
      ;; This is a group, we'll handle it specially
      (setq style "CellGroup")
      (setq content cell-str))
     
     ;; Default
     (t
      (setq style "Unknown")
      (setq content cell-str)))
    
    (list :content content
          :style style
          :metadata metadata)))

(defun wolfram-nb-enhanced--find-all-cells (content &optional depth)
  "Recursively find all Cell[...] structures in CONTENT.
DEPTH tracks recursion level."
  (setq depth (or depth 0))
  (when (> depth 20)
    (error "Maximum recursion depth exceeded"))
  
  (let ((cells '())
        (pos 0))
    
    (while (string-match "Cell\\[" content pos)
      (let* ((cell-start (match-beginning 0))
             (cell-end (wolfram-nb-enhanced--find-matching-bracket content cell-start)))
        
        (when cell-end
          (let* ((cell-str (substring content cell-start cell-end))
                 (parsed (wolfram-nb-enhanced--parse-cell-with-metadata cell-str)))
            
            ;; If this is a CellGroupData, recursively extract cells from it
            (if (string= (plist-get parsed :style) "CellGroup")
                (let ((inner-cells (wolfram-nb-enhanced--extract-from-cellgroup 
                                   (plist-get parsed :content) 
                                   (1+ depth))))
                  (setq cells (append cells inner-cells)))
              ;; Regular cell
              (push parsed cells))
            
            (setq pos cell-end)))))
    
    (nreverse cells)))

(defun wolfram-nb-enhanced--find-matching-bracket (str start-pos)
  "Find the position of the matching ] for the [ at START-POS in STR."
  (save-match-data
    (let ((pos (+ start-pos 5))  ; Start after "Cell["
          (depth 1)
          (in-string nil)
          (escape-next nil)
          (len (length str)))
      
      (while (and (< pos len) (> depth 0))
        (let ((char (aref str pos)))
          (cond
           (escape-next
            (setq escape-next nil))
           
           ((and (= char ?\\) in-string)
            (setq escape-next t))
           
           ((= char ?\")
            (setq in-string (not in-string)))
           
           ((and (not in-string) (= char ?\[))
            (setq depth (1+ depth)))
           
           ((and (not in-string) (= char ?\]))
            (setq depth (1- depth)))))
        
        (setq pos (1+ pos)))
      
      (if (= depth 0) pos nil))))

(defun wolfram-nb-enhanced--extract-from-cellgroup (cellgroup-str depth)
  "Extract cells from a CellGroupData structure in CELLGROUP-STR.
DEPTH is the current recursion depth."
  ;; CellGroupData[{Cell[...], Cell[...], ...}]
  ;; We need to find the {...} part and extract cells from it
  (when (string-match "CellGroupData\\[{\\(.+\\)}\\]" cellgroup-str)
    (let ((inner-content (match-string 1 cellgroup-str)))
      (wolfram-nb-enhanced--find-all-cells inner-content depth))))

(defun wolfram-nb-enhanced-parse-notebook (file)
  "Enhanced parser for complex notebooks. Parse FILE and return cells."
  (message "Using enhanced parser...")
  (with-temp-buffer
    (insert-file-contents file)
    (let ((content (buffer-string)))
      
      ;; Find the Notebook[{...}] structure
      (if (string-match "Notebook\\[{\\([[:ascii:][:nonascii:]]+\\)}\\]" content)
          (let ((notebook-content (match-string 1 content)))
            (message "Found Notebook content, extracting cells...")
            (wolfram-nb-enhanced--find-all-cells notebook-content))
        
        (error "Not a valid Notebook file")))))

;;; Integration with existing mode

(defun wolfram-nb-enhanced-open (file)
  "Open FILE using enhanced parser."
  (interactive "fOpen Wolfram Notebook (enhanced): ")
  (let ((cells (wolfram-nb-enhanced-parse-notebook file))
        (org-text-buffer (generate-new-buffer 
                          (format "*wolfram-nb: %s*" 
                                  (file-name-nondirectory file)))))
    (with-current-buffer org-text-buffer
      (wolfram-nb-mode)
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (wolfram-nb--cells-to-org cells))
        (goto-char (point-min))
        (set-buffer-modified-p nil))
      (setq wolfram-nb--cells cells
            wolfram-nb--original-file file
            wolfram-nb--modified nil))
    (switch-to-buffer org-text-buffer)
    (message "Opened with enhanced parser: %d cells" (length cells))))

(provide 'wolfram-nb-parser-enhanced)
;;; wolfram-nb-parser-enhanced.el ends here
