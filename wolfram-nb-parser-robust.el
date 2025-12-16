;;; wolfram-nb-parser-robust.el --- Robust parser for large notebooks -*- lexical-binding: t; -*-

;;; Commentary:
;; A more robust parser that can handle very large notebooks
;; Uses incremental parsing instead of large regex matches

;;; Code:

(require 'wolfram-nb-mode)

(defun wolfram-nb-robust--skip-to-char (char)
  "Skip forward to CHAR, respecting strings and escapes."
  (let ((in-string nil)
        (escape-next nil)
        (found nil))
    (while (and (not found) (not (eobp)))
      (let ((c (char-after)))
        (cond
         (escape-next
          (setq escape-next nil))
         ((and (= c ?\\) in-string)
          (setq escape-next t))
         ((= c ?\")
          (setq in-string (not in-string)))
         ((and (not in-string) (= c char))
          (setq found t))))
      (unless found
        (forward-char)))
    found))

(defun wolfram-nb-robust--extract-cell-at-point ()
  "Extract a Cell[...] structure starting at point.
Returns (CELL-STRING . END-POS) or nil."
  (when (looking-at "Cell\\[")
    (let ((start (point))
          (depth 0)
          (in-string nil)
          (escape-next nil))
      
      ;; Skip "Cell["
      (goto-char (+ start 5))
      (setq depth 1)
      
      (while (and (> depth 0) (not (eobp)))
        (let ((c (char-after)))
          (cond
           (escape-next
            (setq escape-next nil))
           ((and (= c ?\\) in-string)
            (setq escape-next t))
           ((= c ?\")
            (setq in-string (not in-string)))
           ((and (not in-string) (= c ?\[))
            (setq depth (1+ depth)))
           ((and (not in-string) (= c ?\]))
            (setq depth (1- depth)))))
        (forward-char))
      
      (when (= depth 0)
        (cons (buffer-substring-no-properties start (point))
              (point))))))

(defun wolfram-nb-robust--parse-simple-cell (cell-str)
  "Parse a simple Cell[\"text\", \"Style\", ...] structure."
  (when (string-match "^Cell\\[\"\\(\\(?:[^\"\\\\]\\|\\\\.\\)*\\)\",[ \t\n]*\"\\([^\"]+\\)\"" cell-str)
    (list :content (wolfram-nb--unescape-string (match-string 1 cell-str))
          :style (match-string 2 cell-str)
          :type 'simple)))

(defun wolfram-nb-robust--parse-code-cell (cell-str)
  "Parse a Cell[BoxData[...], \"Code\", ...] structure."
  (when (string-match "^Cell\\[BoxData\\[\\(.+\\)\\],[ \t\n]*\"\\([^\"]+\\)\"" cell-str)
    (list :content (format "[BoxData: %d bytes]" (length (match-string 1 cell-str)))
          :style (match-string 2 cell-str)
          :type 'boxdata
          :raw (match-string 1 cell-str))))

(defun wolfram-nb-robust--is-cellgroup (cell-str)
  "Check if CELL-STR is a CellGroupData structure."
  (string-match "^Cell\\[CellGroupData\\[" cell-str))

(defun wolfram-nb-robust--extract-cells-from-group (cell-str)
  "Extract cells from a CellGroupData structure."
  (with-temp-buffer
    (insert cell-str)
    (goto-char (point-min))
    
    ;; Skip to the opening brace after CellGroupData[
    (when (re-search-forward "CellGroupData\\[{" nil t)
      (let ((cells '())
            (start-pos (point)))
        
        (while (re-search-forward "Cell\\[" nil t)
          (goto-char (match-beginning 0))
          (let ((cell-data (wolfram-nb-robust--extract-cell-at-point)))
            (when cell-data
              (let* ((cell-str (car cell-data))
                     (parsed (or (wolfram-nb-robust--parse-simple-cell cell-str)
                                (wolfram-nb-robust--parse-code-cell cell-str)
                                (list :content (format "[Complex: %d bytes]" (length cell-str))
                                      :style "Unknown"
                                      :type 'complex))))
                (push parsed cells)))))
        
        (nreverse cells)))))

(defun wolfram-nb-robust-parse-notebook (file &optional max-cells)
  "Robustly parse FILE, extracting up to MAX-CELLS cells.
If MAX-CELLS is nil, extract all cells."
  (message "Using robust parser...")
  (with-temp-buffer
    (insert-file-contents file)
    (goto-char (point-min))
    
    ;; Find Notebook[
    (unless (re-search-forward "Notebook\\[{" nil t)
      (error "Not a valid Notebook file"))
    
    (let ((cells '())
          (count 0)
          (total-cells 0))
      
      (message "Extracting cells...")
      
      (while (and (re-search-forward "Cell\\[" nil t)
                  (or (null max-cells) (< count max-cells)))
        (goto-char (match-beginning 0))
        (let ((cell-data (wolfram-nb-robust--extract-cell-at-point)))
          (when cell-data
            (let ((cell-str (car cell-data)))
              (setq total-cells (1+ total-cells))
              
              ;; Skip CellGroupData wrappers - they don't contain content
              (unless (wolfram-nb-robust--is-cellgroup cell-str)
                (cond
                 ;; Simple cell
                 ((wolfram-nb-robust--parse-simple-cell cell-str)
                  (push (wolfram-nb-robust--parse-simple-cell cell-str) cells)
                  (setq count (1+ count)))
                 
                 ;; Code cell with BoxData
                 ((wolfram-nb-robust--parse-code-cell cell-str)
                  (push (wolfram-nb-robust--parse-code-cell cell-str) cells)
                  (setq count (1+ count)))
                 
                 ;; Unknown/complex cell
                 (t
                  (push (list :content (format "[Complex cell: %d bytes]" (length cell-str))
                             :style "Unknown"
                             :type 'complex)
                        cells)
                  (setq count (1+ count))))))
            
            (when (= (mod count 100) 0)
              (message "  Extracted %d cells..." count)))))
      
      (message "Extracted %d cells from %d Cell entries" count total-cells)
      (nreverse cells))))

(defun wolfram-nb-robust-open (file &optional max-cells)
  "Open FILE using robust parser, extracting up to MAX-CELLS cells."
  (interactive "fOpen Wolfram Notebook (robust): \nnMax cells (0 for all): ")
  (when (and (numberp max-cells) (= max-cells 0))
    (setq max-cells nil))
  
  (let ((cells (wolfram-nb-robust-parse-notebook file max-cells))
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
    (message "Opened with robust parser: %d cells" (length cells))))

(provide 'wolfram-nb-parser-robust)
;;; wolfram-nb-parser-robust.el ends here
