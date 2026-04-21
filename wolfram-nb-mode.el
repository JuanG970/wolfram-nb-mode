;;; wolfram-nb-mode.el --- Edit Wolfram Notebook files as Org-mode -*- lexical-binding: t; -*-

;; Copyright (C) 2025 Juan Gonzalez

;; Author: Juan Gonzalez <juan.angel19@hotmail.com>
;; Version: 0.6.0
;; Package-Requires: ((emacs "26.1"))
;; Keywords: wolfram, mathematica, notebook, org
;; URL: https://github.com/juang970/wolfram-nb-mode

;; This file is not part of GNU Emacs.

;; Permission is hereby granted, free of charge, to any person obtaining
;; a copy of this software and associated documentation files (the
;; "Software"), to deal in the Software without restriction, including
;; without limitation the rights to use, copy, modify, merge, publish,
;; distribute, sublicense, and/or sell copies of the Software, and to
;; permit persons to whom the Software is furnished to do so, subject to
;; the following conditions:
;;
;; The above copyright notice and this permission notice shall be
;; included in all copies or substantial portions of the Software.

;;; Commentary:

;; wolfram-nb-mode provides a bidirectional translation layer between
;; Wolfram Language Notebook (.nb) files and Org-mode.  It parses the
;; Cell[...] structure of notebooks into an Org buffer for editing,
;; and serializes changes back to valid Notebook format.
;;
;; Features:
;; - Parse Notebook[{...}] files into Org-mode structure
;; - Full cell hierarchy: Title, Chapter, Section, Subsection, Text, Item
;; - CellGroupData recursive unwrapping
;; - BoxData extraction (pulls actual code from Input cells)
;; - Code evaluation via wolframscript (sync and async)
;; - HTTP session evaluation via persistent Wolfram kernel
;; - Session endpoint stored in #+WOLFRAM_SESSION: org keyword
;; - TaggingRules roundtrip for session persistence in .nb files
;; - Native org-babel integration (C-c C-c in src blocks)
;; - Imenu support for cell-based navigation
;; - Notebook metadata preservation across roundtrips
;;
;; Quick start:
;;   M-x wolfram-nb-open RET notebook.nb RET
;;   Edit as Org-mode, save with C-x C-s
;;
;; Cell type mapping:
;;   Title           -> #+TITLE:
;;   Chapter         -> * heading
;;   Section         -> ** heading
;;   Subsection      -> *** heading
;;   Subsubsection   -> **** heading
;;   Text            -> paragraph
;;   Item/Subitem    -> - list item
;;   Code/Input      -> #+begin_src wolfram ... #+end_src
;;   Output          -> #+begin_example ... #+end_example

;;; Code:

(require 'cl-lib)
(require 'org)
(require 'org-element)
(require 'url-http)

;;;; Custom error types

(define-error 'wolfram-nb-error "Wolfram notebook error")
(define-error 'wolfram-nb-parse-error "Wolfram notebook parse error" 'wolfram-nb-error)
(define-error 'wolfram-nb-eval-error "Wolfram evaluation error" 'wolfram-nb-error)

;;;; Constants

(defconst wolfram-nb-headline-styles
  '(("Chapter" . 1)
    ("Section" . 2)
    ("Subsection" . 3)
    ("Subsubsection" . 4))
  "Alist mapping Wolfram Cell styles to Org headline levels.")

(defconst wolfram-nb-list-styles
  '(("Item" . 1)
    ("Subitem" . 2)
    ("Subsubitem" . 3))
  "Alist mapping Wolfram Cell styles to Org list levels.")

;;;; Customization

(defgroup wolfram-nb nil
  "Edit Wolfram Notebook files in Emacs."
  :group 'languages
  :prefix "wolfram-nb-")

(defcustom wolfram-nb-auto-open t
  "Whether to automatically parse .nb files when opened."
  :type 'boolean
  :group 'wolfram-nb)

(defcustom wolfram-nb-wolframscript-path "wolframscript"
  "Path to the wolframscript executable."
  :type 'string
  :group 'wolfram-nb)

(defcustom wolfram-nb-eval-timeout 30
  "Timeout in seconds for evaluating Wolfram expressions."
  :type 'integer
  :group 'wolfram-nb)

(defcustom wolfram-nb-default-session nil
  "Default session endpoint (\"host:port\") when none specified in buffer.
When nil, evaluation falls back to wolframscript."
  :type '(choice (string :tag "Endpoint (host:port)")
          (const :tag "No default session" nil))
  :group 'wolfram-nb)

(defcustom wolfram-nb-session-timeout 10
  "Timeout in seconds for HTTP session evaluation."
  :type 'integer
  :group 'wolfram-nb)

(defcustom wolfram-nb-session-path "/"
  "HTTP path for evaluation requests on the session server."
  :type 'string
  :group 'wolfram-nb)

;;;; Cell data structure

(cl-defstruct (wolfram-nb-cell (:constructor wolfram-nb-cell-create)
                               (:copier nil))
  "A single cell parsed from a Wolfram Notebook."
  (content "" :type string :documentation "Text content of the cell.")
  (style "Text" :type string :documentation "Cell style (Section, Text, Input, etc.).")
  (options nil :type list :documentation "Alist of parsed options (e.g. CellLabel).")
  (raw-options nil :type string :documentation "Raw string of all cell options (excluding leading comma)."))

;;;; Buffer-local state

(defvar-local wolfram-nb--cells nil
  "List of `wolfram-nb-cell' structs for the current notebook.")

(defvar-local wolfram-nb--original-file nil
  "Path to the .nb file backing this buffer.")

(defvar-local wolfram-nb--notebook-options nil
  "Raw notebook-level options string (FrontEndVersion, StyleDefinitions, etc.).")

(defvar-local wolfram-nb--cell-count 0
  "Number of cells in the current notebook (for mode-line).")

(defvar-local wolfram-nb--session-endpoint nil
  "Parsed session endpoint as (HOST . PORT), or nil.
Set by `wolfram-nb--refresh-session' from #+WOLFRAM_SESSION: or TaggingRules.")

(defvar-local wolfram-nb--session-raw nil
  "Raw session string from #+WOLFRAM_SESSION: or TaggingRules.")

;;;; Font-lock

(defconst wolfram-nb--builtin-functions
  '("Abs" "All" "Apart" "Append" "Apply" "Association" "AssociationMap"
    "BarChart" "Block"
    "Ceiling" "ContourPlot" "Cos" "Counts"
    "Degree" "DensityPlot" "Do" "Drop" "Dynamic" "DynamicModule" "DSolve"
    "E" "Expand" "Exp" "Export"
    "Factor" "False" "First" "Floor" "For" "Function"
    "Graphics" "Graphics3D" "GroupBy"
    "Histogram"
    "I" "If" "Image" "Infinity" "Import" "Integrate"
    "Join"
    "Keys"
    "Last" "Length" "ListLinePlot" "ListPlot" "Log" "Lookup"
    "Manipulate" "Map" "Max" "Merge" "Min" "Module"
    "NDSolve" "None" "Null"
    "Part" "Pi" "PieChart" "Plot" "Plot3D" "Plus" "Power" "Prepend" "Print"
    "Range" "ReadList" "Reverse"
    "Select" "Series" "Show" "Simplify" "Sin" "Solve" "Sort" "Sqrt"
    "StringJoin" "StringReplace" "StringSplit" "Sum" "Switch"
    "Table" "Take" "Tan" "Times" "ToString" "Total" "True"
    "Values"
    "Which" "While" "With" "WriteString")
  "Common Wolfram Language built-in functions for highlighting.")

(defvar wolfram-nb-font-lock-keywords
  `((,(regexp-opt wolfram-nb--builtin-functions 'symbols) . font-lock-builtin-face)
    ("\\b\\([A-Z][a-zA-Z0-9]*\\)\\b" . font-lock-type-face)
    ("\\b\\([a-z][a-zA-Z0-9]*\\)\\s-*\\[" 1 font-lock-function-name-face)
    ("\\b\\([a-z][a-zA-Z0-9]*\\)_+" 1 font-lock-variable-name-face)
    (,(regexp-opt '(":=" "=" "->" ":>" "/;" "/." "@@" "@@@" "/@"
                    "~~" "|" ".." "..." "&&" "||"))
     . font-lock-keyword-face)
    ("(\\*.*?\\*)" . font-lock-comment-face))
  "Font-lock keywords for Wolfram Language.")

;;;; String escaping (fast, using replace-regexp-in-string)

(defun wolfram-nb--unescape-string (str)
  "Convert escaped Mathematica string STR to Emacs Lisp string.
Handles \\\\, \\\", \\n, and \\t sequences in a single pass."
  (replace-regexp-in-string
   "\\\\\\([\\\\\"nt]\\)"
   (lambda (match)
     (pcase (aref match 1)
       (?\\  "\\")
       (?\"  "\"")
       (?n   "\n")
       (?t   "\t")
       (_    (substring match 1))))
   str nil t))

(defun wolfram-nb--escape-string (str)
  "Escape STR for inclusion in a Mathematica string literal.
Handles backslash, double-quote, newline, and tab in a single pass."
  (replace-regexp-in-string
   "[\\\\\"\n\t]"
   (lambda (match)
     (pcase (aref match 0)
       (?\\ "\\\\")
       (?\" "\\\"")
       (?\n "\\n")
       (?\t "\\t")
       (_   match)))
   str nil t))

;;;; Low-level parsing

(defun wolfram-nb--find-cell-end (start)
  "Find the end position of a Cell[...] starting at START.
Tracks bracket depth and string boundaries.
Returns the position after the closing bracket, or nil."
  (save-excursion
    (goto-char start)
    (when (looking-at "Cell\\[")
      (goto-char (match-end 0))
      (let ((depth 1)
            (in-string nil)
            (escape-next nil))
        (while (and (> depth 0) (not (eobp)))
          (let ((char (char-after)))
            (cond
             (escape-next
              (setq escape-next nil))
             ((and in-string (= char ?\\))
              (setq escape-next t))
             ((= char ?\")
              (setq in-string (not in-string)))
             ((and (not in-string) (= char ?\[))
              (setq depth (1+ depth)))
             ((and (not in-string) (= char ?\]))
              (setq depth (1- depth)))))
          (forward-char))
        (when (= depth 0)
          (point))))))

(defun wolfram-nb--is-cellgroupdata (cell-string)
  "Return non-nil if CELL-STRING is a CellGroupData wrapper."
  (string-prefix-p "Cell[CellGroupData[" cell-string))

(defun wolfram-nb--extract-head-argument (str head)
  "Extract the first argument of HEAD[...] in STR.
HEAD is a string like \"Cell\" or \"StyleBox\".
Returns the raw string content of the first argument, or nil if not found."
  (with-temp-buffer
    (insert str)
    (goto-char (point-min))
    (when (search-forward (concat head "[") nil t)
      (let ((depth 0)
            (in-string nil)
            (escape-next nil)
            (start (point))
            (end nil))
        (while (and (not (eobp)) (not end))
          (let ((char (char-after)))
            (cond
             (escape-next (setq escape-next nil))
             ((and in-string (= char ?\\)) (setq escape-next t))
             ((= char ?\") (setq in-string (not in-string)))
             ((and (not in-string) (= char ?\[)) (setq depth (1+ depth)))
             ((and (not in-string) (= char ?\]))
              (if (= depth 0)
                  (setq end (point)) ;; End of Head means end of arg if no comma
                (setq depth (1- depth))))
             ((and (not in-string) (= char ?{)) (setq depth (1+ depth)))
             ((and (not in-string) (= char ?})) (setq depth (1- depth)))
             ((and (not in-string) (= depth 0) (= char ?,))
              (setq end (point))))
            (forward-char)))
        (when end
          (buffer-substring-no-properties start end))))))

(defun wolfram-nb--extract-first-argument (cell-string)
  "Extract the first argument of Cell[...] in CELL-STRING.
Returns the raw string content of the first argument, e.g. BoxData[...]."
  (wolfram-nb--extract-head-argument cell-string "Cell"))

(defun wolfram-nb--split-args (args-string)
  "Split ARGS-STRING by top-level commas.
Returns a list of strings."
  (let ((parts '())
        (depth 0)
        (in-string nil)
        (escape-next nil)
        (start 0)
        (len (length args-string))
        (i 0))
    (while (< i len)
      (let ((char (aref args-string i)))
        (cond
         (escape-next (setq escape-next nil))
         ((and in-string (= char ?\\)) (setq escape-next t))
         ((= char ?\") (setq in-string (not in-string)))
         ((and (not in-string) (= char ?\[)) (setq depth (1+ depth)))
         ((and (not in-string) (= char ?\])) (setq depth (1- depth)))
         ((and (not in-string) (= char ?{)) (setq depth (1+ depth)))
         ((and (not in-string) (= char ?})) (setq depth (1- depth)))
         ((and (not in-string) (= depth 0) (= char ?,))
          (push (string-trim (substring args-string start i)) parts)
          (setq start (1+ i))))
        (setq i (1+ i))))
    (push (string-trim (substring args-string start)) parts)
    (nreverse parts)))

(defun wolfram-nb--parse-textdata-content (content)
  "Parse TextData CONTENT (a string inside TextData[{...}] or TextData[...]).
Handles StyleBox for Bold/Italic formatting."
  (let ((inner-content
         (if (string-prefix-p "{" content)
             (if (string-suffix-p "}" content)
                 (substring content 1 -1)
               content) ;; Should not happen if well-formed
           content)))
    (let ((parts (wolfram-nb--split-args inner-content))
          (result ""))
      (dolist (part parts)
        (cond
         ;; String literal
         ((string-prefix-p "\"" part)
          (setq result (concat result (wolfram-nb--unescape-string (substring part 1 -1)))))
         ;; StyleBox
         ((string-prefix-p "StyleBox[" part)
          (let ((text (wolfram-nb--extract-head-argument part "StyleBox"))
                (style-part (substring part (length "StyleBox["))))
            ;; Extract text from first argument (it might be a string literal)
            (let ((clean-text (if (string-prefix-p "\"" text)
                                  (wolfram-nb--unescape-string (substring text 1 -1))
                                text)))
              ;; Check for Bold/Italic in the rest of the StyleBox
              (cond
               ((string-match-p "\"Bold\"" style-part)
                (setq result (concat result "*" clean-text "*")))
               ((string-match-p "\"Italic\"" style-part)
                (setq result (concat result "/" clean-text "/")))
               (t
                (setq result (concat result clean-text)))))))
         ;; Fallback for other boxes
         (t
          (setq result (concat result part)))))
      result)))


(defun wolfram-nb--extract-boxdata-code (cell-string)
  "Extract code strings from a BoxData CELL-STRING.
If complex content (GraphicsBox, etc.) is detected, returns the raw content
string.  Otherwise pulls all string literals from RowBox structures and
joins them."
  (if (string-match-p "GraphicsBox\\|RasterBox\\|FormBox\\|GridBox" cell-string)
      (wolfram-nb--extract-first-argument cell-string)
    (let ((strings '())
          (start 0))
      (while (string-match "\"\\([^\"\\\\]*\\(?:\\\\.[^\"\\\\]*\\)*\\)\"" cell-string start)
        (let ((s (match-string 1 cell-string)))
          ;; Skip style strings and structural keywords
          (unless (or (string-match-p "^\\(Input\\|Output\\|Code\\|Section\\|Text\\|BoxData\\|RowBox\\|SuperscriptBox\\|SubscriptBox\\|FractionBox\\|SqrtBox\\)$" s)
                      (string= s ",")
                      (string= s " ")
                      (string= s ""))
            (push s strings)))
        (setq start (match-end 0)))
      (if strings
          (wolfram-nb--unescape-string
           (mapconcat #'identity (nreverse strings) ""))
        "[Complex BoxData content]"))))

(defun wolfram-nb--extract-cell-options (cell-string match-end)
  "Extract raw options string from CELL-STRING starting at MATCH-END.
Returns the options string (without leading comma) or nil."
  (let ((len (length cell-string)))
    (when (< match-end (1- len))
      (let ((rest (substring cell-string match-end (1- len)))) ;; Remove closing ]
        (when (string-match "\\`[ \t\n]*,[ \t\n]*" rest)
          (string-trim (substring rest (match-end 0))))))))

(defun wolfram-nb--parse-cell (cell-string)
  "Parse a single Cell[...] structure from CELL-STRING.
Returns a `wolfram-nb-cell' struct, or nil for CellGroupData/unparseable."
  (cond
   ;; CellGroupData wrapper — handled by extract-cells-from-group
   ((wolfram-nb--is-cellgroupdata cell-string)
    nil)

   ;; BoxData cell: Cell[BoxData[...], "Style", ...]
   ((string-match "\\`Cell\\[BoxData\\[" cell-string)
    (when (string-match "\\],[ \t\n]*\"\\([A-Z][a-zA-Z]*\\)\"" cell-string)
      (let ((style (match-string 1 cell-string))
            ;; Extract only the BoxData[...] content (first argument), not the whole cell
            (boxdata-content (wolfram-nb--extract-first-argument cell-string))
            (code nil)
            (raw-options (wolfram-nb--extract-cell-options cell-string (match-end 0))))
        ;; Now extract code from the boxdata-content, not the entire cell
        (setq code (wolfram-nb--extract-boxdata-code boxdata-content))
        (let ((options nil))
          (when (string-match "CellLabel->\"\\([^\"]*\\)\"" cell-string)
            (push (cons 'cell-label (match-string 1 cell-string)) options))
          (wolfram-nb-cell-create :content code :style style :options options :raw-options raw-options)))))

   ;; DynamicModuleBox
   ((string-match "\\`Cell\\[DynamicModuleBox\\[" cell-string)
    (wolfram-nb-cell-create :content "[Dynamic content]" :style "Output"))

   ;; TextData cell: Cell[TextData[{...}], "Style"]
   ((string-match "\\`Cell\\[TextData\\[" cell-string)
    (when (string-match "\\],[ \t\n]*\"\\([A-Z][a-zA-Z]*\\)\"" cell-string)
      (let ((style (match-string 1 cell-string))
            ;; Extract only the TextData content (the argument of TextData[...])
            (textdata-wrapper (wolfram-nb--extract-first-argument cell-string))
            (raw-options (wolfram-nb--extract-cell-options cell-string (match-end 0))))
        ;; Unwrap TextData[...] to get its argument
        (let* ((textdata-content (wolfram-nb--extract-head-argument textdata-wrapper "TextData"))
               (content (wolfram-nb--parse-textdata-content textdata-content))
               (options nil))
          (when (string-match "CellLabel->\"\\([^\"]*\\)\"" cell-string)
            (push (cons 'cell-label (match-string 1 cell-string)) options))
          (wolfram-nb-cell-create
           :content content
           :style style
           :options options
           :raw-options raw-options)))))

   ;; Simple text cell: Cell["text", "Style", ...]
   ((string-match "\\`Cell\\[\"\\(\\(?:[^\"\\\\]\\|\\\\.\\)*\\)\",[ \t\n]*\"\\([A-Z][a-zA-Z]*\\)\"" cell-string)
    (let ((content-raw (match-string 1 cell-string))
          (style (match-string 2 cell-string))
          (raw-options (wolfram-nb--extract-cell-options cell-string (match-end 0))))
      ;; Extract parsed cell options (CellLabel, etc.) if present
      (let ((options nil))
        (when (string-match "CellLabel->\"\\([^\"]*\\)\"" cell-string)
          (push (cons 'cell-label (match-string 1 cell-string)) options))
        (wolfram-nb-cell-create
         :content (wolfram-nb--unescape-string content-raw)
         :style style
         :options options
         :raw-options raw-options))))

   ;; Unknown/invalid
   (t nil)))

;;;; CellGroupData extraction

(defun wolfram-nb--extract-cells-from-group (cell-string)
  "Extract cells from a CellGroupData wrapper in CELL-STRING.
Returns a list of `wolfram-nb-cell' structs in document order."
  (with-temp-buffer
    (insert cell-string)
    (goto-char (point-min))
    (when (re-search-forward "CellGroupData\\[{" nil t)
      (let ((cells '()))
        (while (re-search-forward "Cell\\[" nil t)
          (goto-char (match-beginning 0))
          (let* ((cell-start (point))
                 (cell-end (wolfram-nb--find-cell-end cell-start)))
            (when cell-end
              (let ((inner (buffer-substring-no-properties cell-start cell-end)))
                (cond
                 ((wolfram-nb--is-cellgroupdata inner)
                  (let ((nested (wolfram-nb--extract-cells-from-group inner)))
                    (setq cells (nconc cells nested))))
                 (t
                  (let ((parsed (wolfram-nb--parse-cell inner)))
                    (when parsed
                      (setq cells (nconc cells (list parsed))))))))
              (goto-char cell-end))))
        cells))))

;;;; Notebook parsing

(defun wolfram-nb--parse-notebook (file)
  "Parse Wolfram Notebook FILE into a list of `wolfram-nb-cell' structs.
Recursively unwraps CellGroupData structures.
When called from a `wolfram-nb-mode' buffer, also sets
`wolfram-nb--notebook-options' as a side effect."
  (let ((calling-buffer (current-buffer)))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (unless (re-search-forward "Notebook\\[{" nil t)
        (signal 'wolfram-nb-parse-error (list "Not a valid Notebook file" file)))
      (let ((cells '())
            (total-cells 0))
        (while (re-search-forward "Cell\\[" nil t)
          (goto-char (match-beginning 0))
          (let* ((cell-start (point))
                 (cell-end (wolfram-nb--find-cell-end cell-start)))
            (when cell-end
              (let ((cell-str (buffer-substring-no-properties cell-start cell-end)))
                (cond
                 ((wolfram-nb--is-cellgroupdata cell-str)
                  (let ((nested (wolfram-nb--extract-cells-from-group cell-str)))
                    (setq cells (nconc cells nested))
                    (setq total-cells (+ total-cells (length nested)))))
                 (t
                  (let ((parsed (wolfram-nb--parse-cell cell-str)))
                    (when parsed
                      (setq cells (nconc cells (list parsed)))
                      (setq total-cells (1+ total-cells)))))))
              (goto-char cell-end))))
        ;; Extract notebook-level options
        (when (re-search-forward "}\\s-*," nil t)
          (let ((opts (string-trim
                       (buffer-substring-no-properties
                        (point)
                        (progn (goto-char (point-max))
                               (skip-chars-backward " \t\n")
                               (when (and (not (bobp)) (= (char-before) ?\]))
                                 (backward-char))
                               (point))))))
            (when (not (string-empty-p opts))
              (with-current-buffer calling-buffer
                (setq wolfram-nb--notebook-options opts)
                (let ((session (wolfram-nb--session-from-tagging-rules opts)))
                  (when session
                    (setq wolfram-nb--session-raw session
                          wolfram-nb--session-endpoint (wolfram-nb--parse-endpoint session))))))))
        cells))))

;;;; Cell -> Org conversion

(defun wolfram-nb--cell-to-org (cell)
  "Convert a `wolfram-nb-cell' CELL to Org-mode text."
  (let ((content (wolfram-nb-cell-content cell))
        (style (wolfram-nb-cell-style cell))
        (raw-opts (wolfram-nb-cell-raw-options cell)))
    (cond
     ;; Special Keywords
     ((string= style "Title")
      (format "#+TITLE: %s\n\n" content))
     ((string= style "Subtitle")
      (format "#+SUBTITLE: %s\n\n" content))
     
     ;; Headlines
     ((assoc style wolfram-nb-headline-styles)
      (let ((level (cdr (assoc style wolfram-nb-headline-styles))))
        (format "%s %s\n%s"
                (make-string level ?*)
                content
                (if raw-opts (format ":PROPERTIES:\n:WOLFRAM_OPTIONS: %s\n:END:\n" raw-opts) ""))))

     ;; Lists
     ((assoc style wolfram-nb-list-styles)
      (let* ((level (cdr (assoc style wolfram-nb-list-styles)))
             (indent (make-string (* (1- level) 2) ?\s)))
        (format "%s- %s\n"
                indent
                (replace-regexp-in-string "\\`[•●◦-][ \t]*" "" content))))

     ;; Paragraphs
     ((or (string= style "Text") (string= style "ItemParagraph"))
      (format "%s\n\n" content))

     ;; Code Blocks
     ((or (string= style "Code") (string= style "Input"))
      (let ((label (cdr (assoc 'cell-label (wolfram-nb-cell-options cell)))))
        (format "%s%s#+begin_src wolfram\n%s\n#+end_src\n\n"
                (if label (format "#+NAME: %s\n" label) "")
                (if raw-opts (format "#+ATTR_WOLFRAM: %s\n" raw-opts) "")
                content)))
     
     ;; Example Blocks
     ((or (string= style "Output") (string= style "Print"))
      (let ((label (cdr (assoc 'cell-label (wolfram-nb-cell-options cell)))))
        (format "%s%s#+begin_example\n%s\n#+end_example\n\n"
                (if label (format "#+NAME: %s\n" label) "")
                (if raw-opts (format "#+ATTR_WOLFRAM: %s\n" raw-opts) "")
                content)))

     ;; Fallback
     (t
      (format "# [%s] %s\n\n" style content)))))

(defun wolfram-nb--cells-to-org (cells)
  "Convert a list of `wolfram-nb-cell' CELLS to Org-mode text."
  (let ((body (mapconcat #'wolfram-nb--cell-to-org cells ""))
        (session wolfram-nb--session-raw))
    (if (and session (not (string-empty-p session)))
        (concat (format "#+WOLFRAM_SESSION: %s\n\n" session) body)
      body)))

;;;; Org -> Cell conversion

(defun wolfram-nb--make-cell-string (content style &optional raw-options)
  "Create a Cell[...] string with CONTENT and STYLE.
RAW-OPTIONS, if provided, is appended after the style.
If CONTENT looks like raw BoxData (starts with \"BoxData[\"),
it is inserted as-is without extra quotes/escaping."
  (let* ((trimmed (string-trim content))
         (final-content
          (if (string-prefix-p "BoxData[" trimmed)
              trimmed
            (concat "\"" (wolfram-nb--escape-string trimmed) "\""))))
    (if raw-options
        (format "Cell[%s, \"%s\", %s]"
                final-content
                style
                raw-options)
      (format "Cell[%s, \"%s\"]"
              final-content
              style))))

(defun wolfram-nb--org-to-cells (org-text)
  "Parse ORG-TEXT and convert to a list of Cell string representations."
  (with-temp-buffer
    (insert org-text)
    (org-mode)
    (let ((tree (org-element-parse-buffer))
          (cells '()))
      ;; #+TITLE: -> Title cell
      (org-element-map tree 'keyword
        (lambda (kw)
          (pcase (org-element-property :key kw)
            ("TITLE"
             (push (wolfram-nb--make-cell-string
                    (org-element-property :value kw) "Title") cells))
            ("SUBTITLE"
             (push (wolfram-nb--make-cell-string
                    (org-element-property :value kw) "Subtitle") cells)))))
      ;; Main content
      (org-element-map tree '(headline paragraph plain-list src-block example-block)
        (lambda (element)
          (pcase (org-element-type element)
            ('headline
             (let* ((level (org-element-property :level element))
                    (title (org-element-interpret-data
                            (org-element-property :title element)))
                    (style (or (car (rassoc level wolfram-nb-headline-styles))
                               "Section"))
                    (raw-opts (org-element-property :WOLFRAM_OPTIONS element)))
               (push (wolfram-nb--make-cell-string title style raw-opts) cells)))

            ('paragraph
             (unless (eq (org-element-type (org-element-property :parent element)) 'item)
               (let ((text (org-element-interpret-data element)))
                 (unless (string-blank-p text)
                   (push (wolfram-nb--make-cell-string text "Text") cells)))))

            ('plain-list
             (org-element-map element 'item
               (lambda (item)
                 (let* ((list-depth
                         (let ((lvl 0) (p (org-element-property :parent item)))
                           (while p
                             (when (eq (org-element-type p) 'plain-list)
                               (setq lvl (1+ lvl)))
                             (setq p (org-element-property :parent p)))
                           lvl))
                        (style (or (car (rassoc list-depth wolfram-nb-list-styles))
                                   "Item"))
                        (text (string-trim
                               (mapconcat
                                (lambda (el)
                                  (if (stringp el) el
                                    (org-element-interpret-data el)))
                                (org-element-contents item) ""))))
                   (unless (string-blank-p text)
                     (push (wolfram-nb--make-cell-string text style) cells))))))

            ('src-block
             (let* ((lang (org-element-property :language element))
                    (value (org-element-property :value element))
                    (name (org-element-property :name element))
                    (raw-opts (car (org-element-property :attr_wolfram element)))
                    (final-opts (if name
                                    (if raw-opts
                                        (format "%s, CellLabel->\"%s\"" raw-opts name)
                                      (format "CellLabel->\"%s\"" name))
                                  raw-opts)))
               (push (wolfram-nb--make-cell-string
                      value
                      (if (and lang (string= lang "wolfram")) "Input" "Code")
                      final-opts)
                     cells)))

            ('example-block
             (let* ((value (org-element-property :value element))
                    (name (org-element-property :name element))
                    (raw-opts (car (org-element-property :attr_wolfram element)))
                    (final-opts (if name
                                    (if raw-opts
                                        (format "%s, CellLabel->\"%s\"" raw-opts name)
                                      (format "CellLabel->\"%s\"" name))
                                  raw-opts)))
               (push (wolfram-nb--make-cell-string value "Output" final-opts)
                     cells))))))
      (nreverse cells))))

;;;; Notebook serialization

(defun wolfram-nb--cells-to-notebook (cells &optional options)
  "Serialize CELLS to a Notebook[{...}] string.
OPTIONS, if non-nil, is a raw string appended after the cell list.
If a session is active, injects TaggingRules into the notebook options."
  (let* ((cells-str (string-join cells ",\n"))
         (raw-opts (or options
                       (and (local-variable-p 'wolfram-nb--notebook-options)
                            wolfram-nb--notebook-options)))
         (session-raw (or (wolfram-nb--session-from-org) wolfram-nb--session-raw))
         (opts (wolfram-nb--inject-tagging-rules raw-opts session-raw)))
    (if opts
        (format "Notebook[{\n%s\n},\n%s]\n" cells-str opts)
      (format "Notebook[{\n%s\n}]\n" cells-str))))

(defun wolfram-nb--inject-tagging-rules (opts-string session)
  "Inject or update WolframNBSession TaggingRules in OPTS-STRING.
SESSION is the raw endpoint string, or nil to remove."
  (if (or (not session) (string-empty-p session))
      opts-string
    (let ((rule (format "TaggingRules -> {\"WolframNBSession\" -> \"%s\"}" session)))
      (if (and opts-string (string-match "TaggingRules" opts-string))
          (if (string-match "\"WolframNBSession\"\\s-*->\\s-*\"[^\"]*\"" opts-string)
              (replace-match (format "\"WolframNBSession\" -> \"%s\"" session) t t opts-string)
            opts-string)
        (if (and opts-string (not (string-empty-p opts-string)))
            (concat rule ",\n" opts-string)
          rule)))))

;;;; Interactive commands

;;;###autoload
(defun wolfram-nb-open (file)
  "Open Wolfram Notebook FILE and display as Org-mode."
  (interactive "fOpen Wolfram Notebook: ")
  (let ((buf (generate-new-buffer
              (format "*wolfram-nb: %s*" (file-name-nondirectory file)))))
    (with-current-buffer buf
      (wolfram-nb-mode)
      (let* ((cells (wolfram-nb--parse-notebook file))
             (inhibit-read-only t))
        (erase-buffer)
        (insert (wolfram-nb--cells-to-org cells))
        (goto-char (point-min))
        (set-buffer-modified-p nil)
        (setq wolfram-nb--cells cells
              wolfram-nb--original-file (expand-file-name file)
              wolfram-nb--cell-count (length cells))
        (wolfram-nb--refresh-session)))
    (switch-to-buffer buf)
    (with-current-buffer buf
      (message "Opened %s (%d cells)%s"
               (file-name-nondirectory file) wolfram-nb--cell-count
               (if wolfram-nb--session-raw
                   (format " [session: %s]" wolfram-nb--session-raw)
                 "")))))

(defun wolfram-nb-save ()
  "Save the current Org buffer back to .nb format.
Returns t for `write-contents-functions'."
  (interactive)
  (unless wolfram-nb--original-file
    (signal 'wolfram-nb-error '("No associated .nb file")))
  (wolfram-nb--refresh-session)
  (let* ((org-text (buffer-substring-no-properties (point-min) (point-max)))
         (cells (wolfram-nb--org-to-cells org-text))
         (notebook-text (wolfram-nb--cells-to-notebook cells)))
    (with-temp-file wolfram-nb--original-file
      (insert notebook-text))
    (setq wolfram-nb--cells nil
          wolfram-nb--cell-count (length cells))
    (set-buffer-modified-p nil)
    (force-mode-line-update)
    (message "Saved to %s (%d cells)" wolfram-nb--original-file (length cells))
    t))

(defun wolfram-nb-reparse ()
  "Reparse the current buffer and update internal cell state."
  (interactive)
  (wolfram-nb--refresh-session)
  (let* ((org-text (buffer-substring-no-properties (point-min) (point-max)))
         (cells (wolfram-nb--org-to-cells org-text)))
    (setq wolfram-nb--cells nil
          wolfram-nb--cell-count (length cells))
    (force-mode-line-update)
    (message "Reparsed: %d cells%s" (length cells)
             (if wolfram-nb--session-raw
                 (format " [session: %s]" wolfram-nb--session-raw)
               ""))))

(defun wolfram-nb-view-cells ()
  "Display raw Cell structures for the current buffer in a side window."
  (interactive)
  (let* ((org-text (buffer-substring-no-properties (point-min) (point-max)))
         (cells (wolfram-nb--org-to-cells org-text))
         (buf (get-buffer-create "*Wolfram NB Cells*")))
    (with-current-buffer buf
      (let ((inhibit-read-only t))
        (erase-buffer)
        (insert (wolfram-nb--cells-to-notebook cells))
        (goto-char (point-min)))
      (special-mode))
    (display-buffer buf)))

;;;###autoload
(defun wolfram-nb-create-new (file)
  "Create a new Wolfram Notebook at FILE."
  (interactive "FCreate Wolfram Notebook: ")
  (let ((buf (generate-new-buffer
              (format "*wolfram-nb: %s*" (file-name-nondirectory file)))))
    (with-current-buffer buf
      (wolfram-nb-mode)
      (setq wolfram-nb--original-file (expand-file-name file)
            wolfram-nb--cell-count 0)
      (insert "#+TITLE: New Notebook\n\n")
      (insert "* Introduction\n\n")
      (insert "#+begin_src wolfram\n(* Your code here *)\n#+end_src\n\n")
      (goto-char (point-min)))
    (switch-to-buffer buf)))

(defun wolfram-nb-insert-src-block ()
  "Insert a new wolfram source block at point."
  (interactive)
  (insert "\n#+begin_src wolfram\n\n#+end_src\n")
  (forward-line -2))

(defun wolfram-nb-cell-count ()
  "Display the number of cells in the current buffer."
  (interactive)
  (let* ((org-text (buffer-substring-no-properties (point-min) (point-max)))
         (cells (wolfram-nb--org-to-cells org-text)))
    (message "%d cells" (length cells))))

;;;; Session management

(defun wolfram-nb--parse-endpoint (raw)
  "Parse RAW endpoint string (\"host:port\") into (HOST . PORT).
Defaults host to \"localhost\" if only a port is given."
  (when (and raw (not (string-empty-p (string-trim raw))))
    (let* ((s (string-trim raw))
           (parts (split-string s ":" t)))
      (cond
       ((= (length parts) 1)
        (cons "localhost" (string-to-number (car parts))))
       ((>= (length parts) 2)
        (cons (car parts) (string-to-number (cadr parts))))
       (t nil)))))

(defun wolfram-nb--session-from-org ()
  "Extract session endpoint from #+WOLFRAM_SESSION: keyword in current buffer.
Returns the raw string value, or nil."
  (save-excursion
    (goto-char (point-min))
    (when (re-search-forward "^#\\+WOLFRAM_SESSION:[ \t]*\\(.+\\)$" nil t)
      (string-trim (match-string 1)))))

(defun wolfram-nb--session-from-tagging-rules (opts-string)
  "Extract session from TaggingRules in OPTS-STRING (notebook-level options).
Looks for WolframNBSession->\"endpoint\" pattern."
  (when (and opts-string
             (string-match "WolframNBSession" opts-string))
    (cond
     ((string-match "\"WolframNBSession\"\\s-*->\\s-*\"\\([^\"]+\\)\"" opts-string)
      (match-string 1 opts-string))
     ((string-match "WolframNBSession\\s-*->\\s-*\"\\([^\"]+\\)\"" opts-string)
      (match-string 1 opts-string)))))

(defun wolfram-nb--refresh-session ()
  "Refresh `wolfram-nb--session-endpoint' from buffer or defaults.
Checks #+WOLFRAM_SESSION: first, then `wolfram-nb-default-session'."
  (let ((raw (or (wolfram-nb--session-from-org)
                 wolfram-nb-default-session)))
    (setq wolfram-nb--session-raw raw
          wolfram-nb--session-endpoint (wolfram-nb--parse-endpoint raw))))

(defun wolfram-nb--session-active-p ()
  "Return non-nil if a session endpoint is configured and valid."
  (and wolfram-nb--session-endpoint
       (cdr wolfram-nb--session-endpoint)
       (> (cdr wolfram-nb--session-endpoint) 0)))

(defun wolfram-nb--session-url ()
  "Build the full URL for the session endpoint."
  (when (wolfram-nb--session-active-p)
    (format "http://%s:%d%s"
            (car wolfram-nb--session-endpoint)
            (cdr wolfram-nb--session-endpoint)
            wolfram-nb-session-path)))

;;;; Evaluation — HTTP session

(defun wolfram-nb--eval-via-session (expr)
  "Evaluate EXPR synchronously via HTTP POST to the session server.
Returns the result string."
  (let ((url (wolfram-nb--session-url))
        (url-request-method "POST")
        (url-request-data (encode-coding-string expr 'utf-8))
        (url-request-extra-headers '(("Content-Type" . "text/plain")))
        (result nil)
        (error-msg nil))
    (unless url
      (signal 'wolfram-nb-eval-error '("No session endpoint configured")))
    (let ((inhibit-message t))
      (condition-case err
          (with-current-buffer (url-retrieve-synchronously url t t wolfram-nb-session-timeout)
            (goto-char (point-min))
            (if (re-search-forward "^HTTP/1\\..+ +\\([0-9]+\\)" nil t)
                (let ((status (string-to-number (match-string 1))))
                  (if (= status 200)
                      (progn
                        (re-search-forward "^$" nil t)
                        (forward-char 1)
                        (setq result (buffer-substring-no-properties (point) (point-max)))
                        (setq result (string-trim (decode-coding-string
                                                   (encode-coding-string result 'raw-text)
                                                   'utf-8))))
                    (setq error-msg (format "HTTP %d from session" status))))
              (setq error-msg "No HTTP response from session")))
        (error (setq error-msg (format "Session error: %s" (error-message-string err))))
        (quit (setq error-msg "Session evaluation timed out")))
      (when (and (buffer-live-p (current-buffer))
                 (not (eq (current-buffer) (window-buffer))))
        (kill-buffer)))
    (if error-msg
        (signal 'wolfram-nb-eval-error (list error-msg))
      (or result ""))))

(defun wolfram-nb--eval-via-session-async (expr callback)
  "Evaluate EXPR asynchronously via HTTP POST to the session server.
Calls CALLBACK with the result string on success, or nil on error."
  (let ((url (wolfram-nb--session-url))
        (url-request-method "POST")
        (url-request-data (encode-coding-string expr 'utf-8))
        (url-request-extra-headers '(("Content-Type" . "text/plain"))))
    (unless url
      (signal 'wolfram-nb-eval-error '("No session endpoint configured")))
    (url-retrieve url
                  (lambda (status cb)
                    (let ((error-msg nil)
                          (result nil))
                      (when (plist-get status :error)
                        (setq error-msg
                              (format "Session error: %s"
                                      (error-message-string (plist-get status :error)))))
                      (unless error-msg
                        (goto-char (point-min))
                        (if (re-search-forward "^HTTP/1\\..+ +\\([0-9]+\\)" nil t)
                            (let ((http-status (string-to-number (match-string 1))))
                              (if (= http-status 200)
                                  (progn
                                    (re-search-forward "^$" nil t)
                                    (forward-char 1)
                                    (setq result (buffer-substring-no-properties (point) (point-max)))
                                    (setq result (string-trim (decode-coding-string
                                                               (encode-coding-string result 'raw-text)
                                                               'utf-8))))
                                (setq error-msg (format "HTTP %d from session" http-status))))
                          (setq error-msg "No HTTP response from session")))
                      (kill-buffer)
                      (funcall cb (if error-msg nil (or result "")) error-msg)))
                  (list callback)
                  t)))

;;;; Evaluation — synchronous

(defun wolfram-nb--check-wolframscript ()
  "Return the path to wolframscript if available, nil otherwise."
  (executable-find wolfram-nb-wolframscript-path))

(defun wolfram-nb--eval-expression (expr)
  "Evaluate EXPR synchronously via wolframscript, return result string."
  (unless (wolfram-nb--check-wolframscript)
    (signal 'wolfram-nb-eval-error
            '("wolframscript not found; install Wolfram Engine or set wolfram-nb-wolframscript-path")))
  (with-temp-buffer
    (let ((exit-code (call-process wolfram-nb-wolframscript-path
                                  nil t nil "-code" expr))
          (output nil))
      (setq output (buffer-substring-no-properties (point-min) (point-max)))
      (if (= exit-code 0)
          (string-trim output)
        (signal 'wolfram-nb-eval-error
                (list (format "Exit %d: %s" exit-code (string-trim output))))))))

(defun wolfram-nb--eval-expression-smart (expr)
  "Evaluate EXPR using session if active, otherwise wolframscript."
  (wolfram-nb--refresh-session)
  (if (wolfram-nb--session-active-p)
      (wolfram-nb--eval-via-session expr)
    (wolfram-nb--eval-expression expr)))

(defun wolfram-nb--format-output (output)
  "Format evaluation OUTPUT for display in Org."
  (if (string-match-p "\\`\\(Graphics\\|Graphics3D\\|Image\\)" output)
      (concat output "\n; Graphics output — view in Mathematica")
    output))

(defun wolfram-nb-eval-block ()
  "Evaluate the Wolfram source block at point and insert output below.
Uses session if active, otherwise wolframscript."
  (interactive)
  (save-excursion
    (let* ((element (org-element-at-point))
           (type (org-element-type element)))
      (unless (eq type 'src-block)
        (user-error "Not inside a source block"))
      (let ((lang (org-element-property :language element))
            (code (org-element-property :value element)))
        (unless (string= lang "wolfram")
          (user-error "Not a wolfram source block"))
        (message "Evaluating...")
        (condition-case err
            (let ((result (wolfram-nb--eval-expression-smart code)))
              (goto-char (org-element-property :end element))
              (when (looking-at "[ \t]*\n?#\\+begin_example")
                (let ((output-start (point)))
                  (when (re-search-forward "^#\\+end_example" nil t)
                    (forward-line)
                    (delete-region output-start (point)))))
              (insert "\n#+begin_example\n"
                      (wolfram-nb--format-output result)
                      "\n#+end_example\n")
              (message "Done."))
          (wolfram-nb-eval-error
           (message "Eval error: %s" (cadr err))))))))

(defun wolfram-nb-eval-buffer ()
  "Evaluate all Wolfram source blocks in the buffer.
Uses session if active, otherwise wolframscript."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0) (errors 0))
      (org-element-map (org-element-parse-buffer) 'src-block
        (lambda (element)
          (when (string= (org-element-property :language element) "wolfram")
            (goto-char (org-element-property :begin element))
            (condition-case _err
                (progn (wolfram-nb-eval-block)
                       (setq count (1+ count)))
              (error (setq errors (1+ errors)))))))
      (message "Evaluated %d blocks (%d errors)" count errors))))

;;;; Evaluation — asynchronous

(defvar-local wolfram-nb--async-process nil
  "Current async evaluation process, if any.")

(defun wolfram-nb-eval-block-async ()
  "Evaluate the Wolfram source block at point asynchronously.
Uses session HTTP if active, otherwise wolframscript."
  (interactive)
  (let* ((element (org-element-at-point))
         (type (org-element-type element)))
    (unless (eq type 'src-block)
      (user-error "Not inside a source block"))
    (let ((lang (org-element-property :language element))
          (code (org-element-property :value element))
          (end-marker (copy-marker (org-element-property :end element)))
          (buf (current-buffer)))
      (unless (string= lang "wolfram")
        (user-error "Not a wolfram source block"))
      (message "Evaluating (async)...")
      (wolfram-nb--refresh-session)
      (if (wolfram-nb--session-active-p)
          (wolfram-nb--eval-via-session-async
           code
           (lambda (result error-msg)
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (save-excursion
                   (goto-char end-marker)
                   (when (looking-at "[ \t]*\n?#\\+begin_example")
                     (let ((output-start (point)))
                       (when (re-search-forward "^#\\+end_example" nil t)
                         (forward-line)
                         (delete-region output-start (point)))))
                   (if error-msg
                       (message "Async eval error: %s" error-msg)
                     (insert "\n#+begin_example\n"
                             (wolfram-nb--format-output result)
                             "\n#+end_example\n")
                     (message "Async eval complete."))))
               (set-marker end-marker nil))))
        (progn
          (unless (wolfram-nb--check-wolframscript)
            (user-error "wolframscript not found"))
          (let ((proc
                 (make-process
                  :name "wolfram-eval"
                  :buffer (generate-new-buffer " *wolfram-eval*")
                  :command (list wolfram-nb-wolframscript-path "-code" code)
                  :sentinel
                  (lambda (process _event)
                    (when (memq (process-status process) '(exit signal))
                      (let ((output (with-current-buffer (process-buffer process)
                                      (string-trim (buffer-string))))
                            (exit-code (process-exit-status process)))
                        (kill-buffer (process-buffer process))
                        (when (buffer-live-p buf)
                          (with-current-buffer buf
                            (save-excursion
                              (goto-char end-marker)
                              (when (looking-at "[ \t]*\n?#\\+begin_example")
                                (let ((output-start (point)))
                                  (when (re-search-forward "^#\\+end_example" nil t)
                                    (forward-line)
                                    (delete-region output-start (point)))))
                              (if (= exit-code 0)
                                  (progn
                                    (insert "\n#+begin_example\n"
                                            (wolfram-nb--format-output output)
                                            "\n#+end_example\n")
                                    (message "Async eval complete."))
                                (message "Async eval error: %s" output))))
                          (set-marker end-marker nil))))))))
            (setq wolfram-nb--async-process proc)
            (run-at-time wolfram-nb-eval-timeout nil
                         (lambda ()
                           (when (and (processp proc) (process-live-p proc))
                             (kill-process proc)
                             (message "Evaluation timed out after %ds"
                                      wolfram-nb-eval-timeout))))))))))

;;;; org-babel integration

(declare-function wolfram-nb--eval-expression-smart "wolfram-nb-mode")

(defun org-babel-execute:wolfram (body _params)
  "Execute Wolfram Language BODY.
Uses session if active, otherwise wolframscript.
_PARAMS is the org-babel parameter alist (currently unused)."
  (wolfram-nb--eval-expression-smart body))

(defun wolfram-nb-clear-outputs ()
  "Remove all example blocks (evaluation outputs) from the buffer."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0))
      (while (re-search-forward "^#\\+begin_example\n" nil t)
        (let ((start (match-beginning 0)))
          (when (re-search-forward "^#\\+end_example\n?" nil t)
            (delete-region start (point))
            (setq count (1+ count)))))
      (message "Cleared %d output blocks" count))))

;;;; Imenu integration

(defun wolfram-nb--imenu-create-index ()
  "Create an Imenu index for the current wolfram-nb buffer.
Groups entries by cell type."
  (let ((index '())
        (heading-re "^\\(\\*+\\) \\(.+\\)$")
        (src-re "^#\\+begin_src wolfram"))
    ;; Collect headings
    (save-excursion
      (goto-char (point-min))
      (while (re-search-forward heading-re nil t)
        (let* ((stars (match-string 1))
               (title (match-string 2))
               (label (format "%s %s" stars title)))
          (push (cons label (match-beginning 0)) index))))
    ;; Collect src blocks
    (save-excursion
      (goto-char (point-min))
      (let ((n 0))
        (while (re-search-forward src-re nil t)
          (setq n (1+ n))
          (push (cons (format "Code block #%d" n) (match-beginning 0)) index))))
    (nreverse index)))

;;;; Interactive session commands

(defun wolfram-nb-set-session (endpoint)
  "Set or update the session endpoint for this buffer.
ENDPOINT should be \"host:port\" (e.g. \"localhost:6061\").
Interactively prompts for the value."
  (interactive
   (list (read-string "Session endpoint (host:port): "
                      (or wolfram-nb--session-raw
                          (format "localhost:%s"
                                  (or (and wolfram-nb-default-session
                                           (cdr (wolfram-nb--parse-endpoint wolfram-nb-default-session)))
                                      "6061"))))))
  (let ((ep endpoint))
    (setq wolfram-nb--session-raw (if (string-empty-p ep) nil ep)
          wolfram-nb--session-endpoint (wolfram-nb--parse-endpoint ep)))
  (save-excursion
    (goto-char (point-min))
    (if (re-search-forward "^#\\+WOLFRAM_SESSION:.*$" nil t)
        (if wolfram-nb--session-raw
            (replace-match (format "#+WOLFRAM_SESSION: %s" wolfram-nb--session-raw) t)
          (delete-region (line-beginning-position) (min (1+ (line-end-position)) (point-max))))
      (when wolfram-nb--session-raw
        (goto-char (point-min))
        (if (re-search-forward "^#\\+TITLE:" nil t)
            (progn (end-of-line) (insert (format "\n#+WOLFRAM_SESSION: %s" wolfram-nb--session-raw)))
          (insert (format "#+WOLFRAM_SESSION: %s\n" wolfram-nb--session-raw))))))
  (message "Session set to %s" (or wolfram-nb--session-raw "none")))

(defun wolfram-nb-session-info ()
  "Display current session status."
  (interactive)
  (wolfram-nb--refresh-session)
  (if (wolfram-nb--session-active-p)
      (message "Session: %s:%d (active)" (car wolfram-nb--session-endpoint)
               (cdr wolfram-nb--session-endpoint))
    (if wolfram-nb--session-raw
        (message "Session: %s (invalid)" wolfram-nb--session-raw)
      (if (wolfram-nb--check-wolframscript)
          (message "No session. Using wolframscript: %s" wolfram-nb-wolframscript-path)
        (message "No session and no wolframscript available.")))))

(defun wolfram-nb-session-ping ()
  "Test connectivity to the session endpoint by evaluating \"$Version\"."
  (interactive)
  (wolfram-nb--refresh-session)
  (if (not (wolfram-nb--session-active-p))
      (message "No active session to ping.")
    (message "Pinging %s:%d..." (car wolfram-nb--session-endpoint)
             (cdr wolfram-nb--session-endpoint))
    (condition-case err
        (let ((result (wolfram-nb--eval-via-session "$Version")))
          (message "Session alive: %s" result))
      (wolfram-nb-eval-error
       (message "Session ping failed: %s" (cadr err))))))

;;;; Keymap

(defvar wolfram-nb-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'wolfram-nb-eval-block)
    (define-key map (kbd "C-c C-e") #'wolfram-nb-eval-block-async)
    (define-key map (kbd "C-c C-r") #'wolfram-nb-reparse)
    (define-key map (kbd "C-c C-v") #'wolfram-nb-view-cells)
    (define-key map (kbd "C-c C-b") #'wolfram-nb-eval-buffer)
    (define-key map (kbd "C-c C-k") #'wolfram-nb-clear-outputs)
    (define-key map (kbd "C-c C-n") #'wolfram-nb-insert-src-block)
    (define-key map (kbd "C-c C-s") #'wolfram-nb-set-session)
    (define-key map (kbd "C-c C-p") #'wolfram-nb-session-ping)
    (define-key map (kbd "C-x C-s") #'wolfram-nb-save)
    map)
  "Keymap for `wolfram-nb-mode'.")

;;;; Mode definition

;;;###autoload
(define-derived-mode wolfram-nb-mode org-mode "Wolfram-NB"
  "Major mode for editing Wolfram Notebook files as Org-mode.

Parses .nb files into Org representation, maintaining the underlying
Cell[...] structure for serialization back to Notebook format.

\\{wolfram-nb-mode-map}"
  (setq-local write-contents-functions '(wolfram-nb-save))
  (setq-local imenu-create-index-function #'wolfram-nb--imenu-create-index)
  (font-lock-add-keywords nil wolfram-nb-font-lock-keywords)
  (message "Wolfram-NB mode. C-c C-c eval | C-x C-s save | C-c C-n new block | C-c C-s session"))

;;;; Auto-mode

;;;###autoload
(add-to-list 'auto-mode-alist '("\\.nb\\'" . wolfram-nb--auto-open))

(defun wolfram-nb--auto-open ()
  "Automatically open .nb files with `wolfram-nb-open'."
  (when wolfram-nb-auto-open
    (let ((file (buffer-file-name))
          (raw-buf (current-buffer)))
      (when file
        (wolfram-nb-open file)
        (when (buffer-live-p raw-buf)
          (kill-buffer raw-buf))))))

(provide 'wolfram-nb-mode)
;;; wolfram-nb-mode.el ends here
