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
(require 'subr-x)
(require 'org)
(require 'org-element)
(require 'url-http)
(require 'wolfram-nb-kernel)

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

(defconst wolfram-nb-numbered-list-styles
  '(("ItemNumbered" . 1)
    ("SubitemNumbered" . 2)
    ("SubsubitemNumbered" . 3))
  "Alist mapping Wolfram Cell styles to Org numbered list levels.")

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

(defcustom wolfram-nb-use-kernel t
  "Whether evaluation uses one persistent kernel per notebook buffer.
With a kernel, definitions made in one cell are visible in the next and
graphics are rendered by the kernel that produced them.  When nil, or when no
kernel can be found, every evaluation starts a fresh `wolframscript'."
  :type 'boolean
  :group 'wolfram-nb)

(defcustom wolfram-nb-rasterize-graphics t
  "Whether to asynchronously rasterize and display raw graphics cells."
  :type 'boolean
  :group 'wolfram-nb)

(defcustom wolfram-nb-fold-raw-blocks t
  "Whether to fold raw/unrecognized blocks by default."
  :type 'boolean
  :group 'wolfram-nb)

;;;; Cell data structure

(cl-defstruct (wolfram-nb-cell (:constructor wolfram-nb-cell-create)
                               (:copier nil))
  "A single cell parsed from a Wolfram Notebook."
  (content "" :type string :documentation "Text content of the cell.")
  (style "Text" :type string :documentation "Cell style (Section, Text, Input, etc.).")
  (options nil :type list :documentation "Alist of parsed options (e.g. CellLabel).")
  (raw-options nil :type string :documentation "Raw string of all cell options (excluding leading comma).")
  (boxes nil :documentation "The BoxData[...] or TextData[...] string CONTENT was derived from."))

;;;; Buffer-local state

(defvar-local wolfram-nb--cells nil
  "List of `wolfram-nb-cell' structs for the current notebook.")

(defvar-local wolfram-nb--overlays nil
  "List of active visual overlays in the current buffer.")

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

(defvar-local wolfram-nb--large-cells-cache nil
  "Buffer-local hash table mapping placeholder IDs to large cell contents.")

(defvar-local wolfram-nb--box-sources nil
  "Hash table from a cell key to (BOXES . OPTIONS) of the cell it describes.
The key joins the cell style, its ExpressionUUID, the text shown in Org and an
occurrence number.  A cell whose text is unchanged when saved is written back
with its original boxes, so the formatting of a notebook survives a visit in
Emacs.  OPTIONS matters for cells that cannot carry an attribute line in Org
(titles and list items).")

(defvar wolfram-nb--box-counts nil
  "Hash table counting how often each cell key was met in the current pass.")

(defvar-local wolfram-nb--png-cache nil
  "Buffer-local hash table mapping placeholder IDs to rendered PNG bytes.")

(defvar-local wolfram-nb--kernel nil
  "The persistent `wolfram-nb-kernel' of this notebook buffer, or nil.")

(defvar-local wolfram-nb--async-process nil
  "Current one-shot async evaluation process, if any.")

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
Handles \\\\, \\\", \\n, and \\t sequences in a single pass.
Also strips long-string markers \\< and \\> if present, and handles line continuations."
  (let* ((clean (if (string-prefix-p "\\<" str)
                    (substring str 2)
                  str))
         (clean2 (if (string-suffix-p "\\>" clean)
                     (substring clean 0 -2)
                   clean)))
    ;; Remove line continuations (backslash followed by optional whitespace and newline)
    (setq clean2 (replace-regexp-in-string "\\\\[ \t]*\n" "" clean2))
    ;; Trim leading/trailing newlines/whitespace if it was a long string
    (when (or (string-prefix-p "\\<" str) (string-suffix-p "\\>" str))
      (setq clean2 (string-trim clean2)))
    (replace-regexp-in-string
     "\\\\\\([\\\\\"nt]\\)"
     (lambda (match)
       (pcase (aref match 1)
         (?\\  "\\")
         (?\"  "\"")
         (?n   "\n")
         (?t   "\t")
         (_    (substring match 1))))
     clean2 nil t)))

(defconst wolfram-nb--character-escape-regexp
  (concat "\\\\\\(?:\\[[A-Za-z][A-Za-z0-9]*\\]"      ; \[Alpha]
          "\\|:[0-9A-Fa-f]\\{4\\}\\|\\.[0-9A-Fa-f]\\{2\\}"  ; \:03b1 \.e9
          "\\||[0-9A-Fa-f]\\{6\\}\\|[0-7]\\{3\\}"     ; \|01d4b6 \101
          "\\|[!()*/^_@&%+$]\\)")                      ; linear syntax \! \( \)
  "Escapes of a Wolfram string that are kept as they are.
The Wolfram parser reads them as single characters, so they must not have
their backslash doubled when the string is written back.")

(defun wolfram-nb--escape-string (str)
  "Escape STR for inclusion in a Mathematica string literal.
Handles backslash, double-quote, newline, and tab in a single pass.  A
backslash that starts a character escape such as `\\[Alpha]' is kept."
  (replace-regexp-in-string
   (concat wolfram-nb--character-escape-regexp "\\|[\\\\\"\n\t]")
   (lambda (match)
     (if (> (length match) 1)
         match
       (pcase (aref match 0)
         (?\\ "\\\\")
         (?\" "\\\"")
         (?\n "\\n")
         (?\t "\\t")
         (_   match))))
   str nil t))

;;;; Low-level parsing

(defvar wolfram-nb--parse-syntax-table
  (let ((st (make-syntax-table)))
    (modify-syntax-entry ?\[ "(]" st)
    (modify-syntax-entry ?\] ")[" st)
    (modify-syntax-entry ?{ "(}" st)
    (modify-syntax-entry ?} "){" st)
    (modify-syntax-entry ?\" "\"" st)
    (modify-syntax-entry ?\\ "\\" st)
    st)
  "Syntax table for parsing Mathematica notebook expressions.")

(defun wolfram-nb--find-cell-end (start)
  "Find the end position of a Cell[...] starting at START.
Returns the position after the closing bracket, or nil."
  (save-excursion
    (goto-char start)
    (when (looking-at "Cell\\[")
      (with-syntax-table wolfram-nb--parse-syntax-table
        (goto-char (+ start 4)) ;; Go to the '['
        (ignore-errors
          (forward-sexp 1)
          (point))))))

(defun wolfram-nb--is-cellgroupdata (cell-string)
  "Return non-nil if CELL-STRING is a CellGroupData wrapper."
  (string-prefix-p "Cell[CellGroupData[" cell-string))

(defun wolfram-nb--extract-head-argument (str head)
  "Extract the first argument of HEAD[...] in STR.
HEAD is a string like \"Cell\" or \"StyleBox\".
Returns the raw string content of the first argument, or nil if not found."
  (with-temp-buffer
    (set-syntax-table wolfram-nb--parse-syntax-table)
    (insert str)
    (goto-char (point-min))
    (when (search-forward (concat head "[") nil t)
      (let ((start (point))
            (end nil))
        (while (and (not (eobp)) (not end))
          (if (re-search-forward "[][{}\",]" nil t)
              (let ((char (char-before)))
                (goto-char (match-beginning 0))
                (cond
                 ((= char ?,)  (setq end (point)))
                 ((= char ?\]) (setq end (point)))
                 ((= char ?\[) (forward-sexp 1))
                 ((= char ?{)  (forward-sexp 1))
                 ((= char ?\") (forward-sexp 1))))
            (goto-char (point-max))))
        (when end
          (buffer-substring-no-properties start end))))))

(defun wolfram-nb--extract-first-argument (cell-string)
  "Extract the first argument of Cell[...] in CELL-STRING.
Returns the raw string content of the first argument, e.g. BoxData[...]."
  (wolfram-nb--extract-head-argument cell-string "Cell"))

(defun wolfram-nb--split-args (args-string)
  "Split ARGS-STRING by top-level commas.
Returns a list of strings."
  (with-temp-buffer
    (set-syntax-table wolfram-nb--parse-syntax-table)
    (insert args-string)
    (goto-char (point-min))
    (let ((parts '())
          (start (point)))
      (while (not (eobp))
        (if (re-search-forward "[][{}\",]" nil t)
            (let ((char (char-before)))
              (goto-char (match-beginning 0))
              (cond
               ((= char ?,)
                (push (string-trim (buffer-substring-no-properties start (point))) parts)
                (forward-char 1)
                (setq start (point)))
               ((= char ?\[) (ignore-errors (forward-sexp 1)))
               ((= char ?{)  (ignore-errors (forward-sexp 1)))
               ((= char ?\") (ignore-errors (forward-sexp 1)))
               (t (forward-char 1))))
          (goto-char (point-max))))
      (push (string-trim (buffer-substring-no-properties start (point))) parts)
      (nreverse parts))))

(defconst wolfram-nb--opaque-regexp "⟦wnb:\\([0-9]+\\)⟧"
  "Matches the text that stands for an inline box kept as it was.")

(defvar wolfram-nb--parse-opaque nil
  "While a notebook is parsed, the hash table collecting inline boxes.")

(defvar-local wolfram-nb--opaque-parts nil
  "Hash table from the number in a ⟦wnb:N⟧ token to the box it stands for.
Inline boxes that Org cannot show, such as hyperlinks and inline cells, are
replaced by a token in the text and put back when the notebook is saved.")

(defun wolfram-nb--opaque-token (part)
  "Return the text standing for the inline box PART, remembering PART."
  (if (null wolfram-nb--parse-opaque)
      part
    (let ((id (number-to-string (1+ (hash-table-count wolfram-nb--parse-opaque)))))
      (puthash id part wolfram-nb--parse-opaque)
      (format "⟦wnb:%s⟧" id))))

(defun wolfram-nb--styled-text (marker text)
  "Return TEXT wrapped in MARKER, with surrounding blanks left outside.
Org does not read `/ word/' as emphasis, so the blanks must not be inside."
  (let* ((lead (if (string-match "\\`[ \t\n]+" text) (match-string 0 text) ""))
         (trail (if (string-match "[ \t\n]+\\'" text) (match-string 0 text) ""))
         (core (string-trim text)))
    (if (string-empty-p core)
        text
      (concat lead marker core marker trail))))

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
            (if (not (and text (string-prefix-p "\"" text)))
                ;; Not plain text inside: keep the whole box as it is.
                (setq result (concat result (wolfram-nb--opaque-token part)))
              (let ((clean-text (wolfram-nb--unescape-string (substring text 1 -1))))
                ;; Check for Bold/Italic in the rest of the StyleBox
                (cond
                 ((string-match-p "\"Bold\"" style-part)
                  (setq result (concat result (wolfram-nb--styled-text "*" clean-text))))
                 ((string-match-p "\"Italic\"" style-part)
                  (setq result (concat result (wolfram-nb--styled-text "/" clean-text))))
                 ((string-match-p "\"Underlined\"" style-part)
                  (setq result (concat result (wolfram-nb--styled-text "_" clean-text))))
                 ((string-match-p "\"Courier\"" style-part)
                  (setq result (concat result (wolfram-nb--styled-text "=" clean-text))))
                 (t
                  (setq result (concat result clean-text))))))))
         ;; Any other inline box (a link, an inline cell, ...): keep it as it is
         (t
          (setq result (concat result (wolfram-nb--opaque-token part))))))
      result)))


;;;; Box data -> code text

(define-error 'wolfram-nb-unsupported-box "Box data cannot be shown as code")

(defun wolfram-nb--box-skip-blank ()
  "Skip whitespace and (* comments *) at point."
  (let ((again t))
    (while again
      (skip-chars-forward " \t\r\n")
      (if (looking-at "(\\*")
          (unless (search-forward "*)" nil t) (goto-char (point-max)))
        (setq again nil)))))

(defun wolfram-nb--box-parse-args (close)
  "Parse comma separated boxes up to the character CLOSE; return a list."
  (let ((args '()) (done nil))
    (while (not done)
      (wolfram-nb--box-skip-blank)
      (cond
       ((eobp) (signal 'wolfram-nb-unsupported-box '("unterminated")))
       ((eq (char-after) close) (forward-char 1) (setq done t))
       (t
        (push (wolfram-nb--box-parse) args)
        (wolfram-nb--box-skip-blank)
        (cond ((eq (char-after) ?,) (forward-char 1))
              ((eq (char-after) close))
              (t (signal 'wolfram-nb-unsupported-box '("separator")))))))
    (nreverse args)))

(defun wolfram-nb--box-parse-primary ()
  "Parse one box expression at point into a node."
  (wolfram-nb--box-skip-blank)
  (cond
   ((eobp) (signal 'wolfram-nb-unsupported-box '("end")))
   ((eq (char-after) ?\")
    (forward-char 1)
    (let ((start (point)))
      (while (not (eq (char-after) ?\"))
        (when (eobp) (signal 'wolfram-nb-unsupported-box '("string")))
        (forward-char (if (eq (char-after) ?\\) 2 1)))
      (prog1 (cons :str (buffer-substring-no-properties start (point)))
        (forward-char 1))))
   ((eq (char-after) ?{)
    (forward-char 1)
    (cons :list (wolfram-nb--box-parse-args ?})))
   ((looking-at "[A-Za-z$][A-Za-z0-9$`_]*")
    (let ((name (match-string-no-properties 0)))
      (goto-char (match-end 0))
      (if (eq (char-after) ?\[)
          (progn (forward-char 1)
                 (cons :call (cons name (wolfram-nb--box-parse-args ?\]))))
        (cons :atom name))))
   ((looking-at "[-+]?[0-9.]+\\(?:\\*\\^[-+]?[0-9]+\\)?")
    (goto-char (match-end 0))
    (cons :atom (match-string-no-properties 0)))
   (t (signal 'wolfram-nb-unsupported-box '("syntax")))))

(defun wolfram-nb--box-parse ()
  "Parse a box expression, allowing a trailing `->' or `:>' rule."
  (let ((lhs (wolfram-nb--box-parse-primary)))
    (wolfram-nb--box-skip-blank)
    (if (looking-at "->\\|:>")
        (progn (goto-char (match-end 0))
               (list :rule lhs (wolfram-nb--box-parse)))
      lhs)))

(defun wolfram-nb--box-token (raw)
  "Return the code text of the box string RAW (the text between its quotes)."
  (let ((text (wolfram-nb--unescape-string raw)))
    (setq text (replace-regexp-in-string "\\\\\\[IndentingNewLine\\]" "\n" text))
    (setq text (replace-regexp-in-string "\\\\\\[NoBreak\\]" "" text))
    (if (string= text ",") ", " text)))

(defun wolfram-nb--box-join (texts)
  "Join TEXTS, separating neighbours that would otherwise fuse into one token."
  (let ((out ""))
    (dolist (text texts)
      (setq out
            (cond
             ((string-empty-p out) text)
             ((string-empty-p text) out)
             ((or (and (string-match-p "[[:alnum:]$]\\'" out)
                       (string-match-p "\\`[[:alnum:]$]" text))
                  (and (string-match-p "[-+]\\'" out)
                       (string-match-p "\\`[-+]" text))
                  (and (string-match-p "[0-9]\\'" out)
                       (string-match-p "\\`\\." text)))
              (concat out " " text))
             (t (concat out text)))))
    out))

(defun wolfram-nb--box-join-lines (texts)
  "Join the lines TEXTS with newlines, but not where one already is."
  (let ((out ""))
    (dolist (text texts)
      (setq out (cond
                 ((string-empty-p out) text)
                 ((or (string-suffix-p "\n" out) (string-prefix-p "\n" text))
                  (concat out text))
                 (t (concat out "\n" text)))))
    out))

(defconst wolfram-nb--stop-tokens
  '("+" "-" "," ";" "=" ":=" "==" "!=" ">" "<" ">=" "<=" "&&" "||" "->" ":>" "/;"
    "//" "\\[Rule]" "\\[RuleDelayed]" "\\[Equal]" "\\[NotEqual]" "\\[LessEqual]"
    "\\[GreaterEqual]" "\\[And]" "\\[Or]")
  "Row tokens at which the operand of a big operator such as a sum ends.")

(defun wolfram-nb--box-string (node)
  "Return the raw text of NODE if it is a box string, else nil."
  (and (eq (car node) :str) (cdr node)))

(defun wolfram-nb--box-big-operator (node)
  "Return (KIND . ARGS) when NODE is a typeset big operator, else nil.
KIND is one of sum, product, integral, integral-definite, partial and limit."
  (pcase node
    (`(:call "UnderoverscriptBox" (:str . ,base) ,lo ,hi)
     (cond ((equal base "\\[Sum]") (list 'sum lo hi))
           ((equal base "\\[Product]") (list 'product lo hi))))
    (`(:call "SubsuperscriptBox" (:str . "\\[Integral]") ,lo ,hi)
     (list 'integral-definite lo hi))
    (`(:str . "\\[Integral]") (list 'integral))
    (`(:call "SubscriptBox" (:str . "\\[PartialD]") ,var) (list 'partial var))
    (`(:call "UnderscriptBox" (:str . ,(or "lim" "\\[Limit]")) ,under . ,_)
     (list 'limit under))))

(defun wolfram-nb--box-unsupported-operator-p (node)
  "Return non-nil if NODE is a big operator this converter cannot read."
  (let ((base (cond ((eq (car node) :str) (cdr node))
                    ((and (eq (car node) :call)
                          (member (cadr node)
                                  '("UnderoverscriptBox" "UnderscriptBox" "OverscriptBox"
                                    "SubsuperscriptBox" "SubscriptBox" "SuperscriptBox")))
                     (wolfram-nb--box-string (nth 2 node))))))
    (and base
         (member base '("\\[Sum]" "\\[Product]" "\\[Integral]" "\\[ContourIntegral]"
                       "\\[DoubleContourIntegral]" "\\[PartialD]" "\\[Del]" "\\[Union]"
                       "\\[Intersection]" "\\[Coproduct]" "\\[Bigoplus]" "\\[Bigotimes]"
                       "\\[Limit]" "lim" "max" "min" "arg" "sup" "inf"))
         (not (wolfram-nb--box-big-operator node)))))

(defun wolfram-nb--box-take-operand (nodes stop-at-differential)
  "Split NODES into (OPERAND . REST) for a big operator.
The operand runs to a token of lower precedence, or, for an integral, to the
differential, whose variable is returned as the last element of OPERAND's
cons: (OPERAND VARIABLE-NODE . REST)."
  (let ((operand '()) (rest nodes) (leading t) (found nil))
    (while (and rest (not found))
      (let* ((node (car rest)) (raw (wolfram-nb--box-string node))
             (text (and raw (wolfram-nb--box-token raw))))
        (cond
         ((and stop-at-differential raw (equal raw "\\[DifferentialD]"))
          (setq found (list (nreverse operand) (cadr rest) (cddr rest))
                rest nil))
         ((and (not stop-at-differential) text leading (member text '("+" "-")))
          (push node operand) (setq rest (cdr rest)))
         ((and text (not stop-at-differential) (member (string-trim text) wolfram-nb--stop-tokens))
          (setq found (list (nreverse operand) nil rest) rest nil))
         (t (push node operand) (setq rest (cdr rest) leading nil)))))
    (or found (list (nreverse operand) nil nil))))

(defun wolfram-nb--box-apply-operator (operator nodes)
  "Return (TEXT . REST) for big OPERATOR followed by the row elements NODES."
  (let* ((kind (car operator))
         (split (wolfram-nb--box-take-operand
                 nodes (memq kind '(integral integral-definite))))
         (body (wolfram-nb--box-join (mapcar #'wolfram-nb--box-text (nth 0 split))))
         (var-node (nth 1 split))
         (rest (nth 2 split)))
    (when (string-empty-p body)
      (signal 'wolfram-nb-unsupported-box '("operand")))
    (cl-flet ((row-parts (node)
                ;; RowBox[{v, "=", a}] -> (v . a)
                (let ((items (and (eq (car node) :call) (equal (cadr node) "RowBox")
                                  (eq (car (nth 2 node)) :list) (cdr (nth 2 node)))))
                  (unless (and (= (length items) 3)
                               (equal (wolfram-nb--box-string (nth 1 items)) "="))
                    (signal 'wolfram-nb-unsupported-box '("bounds")))
                  (cons (wolfram-nb--box-text (nth 0 items))
                        (wolfram-nb--box-text (nth 2 items))))))
      (cons
       (pcase kind
         ((or 'sum 'product)
          (let ((lo (row-parts (nth 1 operator))))
            (format "%s[%s, {%s, %s, %s}]"
                    (if (eq kind 'sum) "Sum" "Product") body (car lo) (cdr lo)
                    (wolfram-nb--box-text (nth 2 operator)))))
         ('integral-definite
          (unless var-node (signal 'wolfram-nb-unsupported-box '("differential")))
          (format "Integrate[%s, {%s, %s, %s}]" body (wolfram-nb--box-text var-node)
                  (wolfram-nb--box-text (nth 1 operator))
                  (wolfram-nb--box-text (nth 2 operator))))
         ('integral
          (unless var-node (signal 'wolfram-nb-unsupported-box '("differential")))
          (format "Integrate[%s, %s]" body (wolfram-nb--box-text var-node)))
         ('partial (format "D[%s, %s]" body (wolfram-nb--box-text (nth 1 operator))))
         ('limit (format "Limit[%s, %s]" body (wolfram-nb--box-text (nth 1 operator)))))
       rest))))

(defun wolfram-nb--box-row-text (nodes)
  "Return the code text of the elements NODES of a RowBox."
  (let ((out '()))
    (while nodes
      (let* ((node (car nodes))
             (operator (wolfram-nb--box-big-operator node)))
        (cond
         (operator
          (let ((applied (wolfram-nb--box-apply-operator operator (cdr nodes))))
            (push (car applied) out)
            (setq nodes (cdr applied))))
         ((wolfram-nb--box-unsupported-operator-p node)
          (signal 'wolfram-nb-unsupported-box '("operator")))
         (t (push (wolfram-nb--box-text node) out)
            (setq nodes (cdr nodes))))))
    (wolfram-nb--box-join (nreverse out))))

(defun wolfram-nb--box-simple-p (text)
  "Return non-nil if TEXT is one token or a call and needs no parentheses."
  (string-match-p "\\`-?[[:alnum:]$.`]+\\'\\|\\`[[:alnum:]$`]+\\[.*\\]\\'" text))

(defun wolfram-nb--box-paren (text)
  "Return TEXT, in parentheses unless it is simple."
  (if (wolfram-nb--box-simple-p text) text (concat "(" text ")")))

(defun wolfram-nb--expr-text (node)
  "Return the InputForm text of the expression NODE (an interpretation)."
  (pcase (car node)
    (:str (concat "\"" (cdr node) "\""))
    (:atom (cdr node))
    (:list (concat "{" (mapconcat #'wolfram-nb--expr-text (cdr node) ", ") "}"))
    (:rule (format "%s -> %s" (wolfram-nb--expr-text (nth 1 node))
                   (wolfram-nb--expr-text (nth 2 node))))
    (:call (format "%s[%s]" (cadr node)
                   (mapconcat #'wolfram-nb--expr-text (cddr node) ", ")))
    (_ (signal 'wolfram-nb-unsupported-box '("expression")))))

(defun wolfram-nb--box-text (node)
  "Return the code text of the box NODE; signal when it is not plain code."
  (pcase (car node)
    (:str (wolfram-nb--box-token (cdr node)))
    (:atom (cdr node))
    (:list (wolfram-nb--box-join-lines (mapcar #'wolfram-nb--box-text (cdr node))))
    (:rule (signal 'wolfram-nb-unsupported-box '("rule")))
    (:call
     (let ((head (cadr node)) (args (cddr node)))
       (cl-flet ((arg (n) (let ((a (nth n args)))
                            (unless a (signal 'wolfram-nb-unsupported-box '("arity")))
                            (wolfram-nb--box-text a))))
         (pcase head
           ("BoxData" (if (cdr args)
                          (signal 'wolfram-nb-unsupported-box '("BoxData arity"))
                        (arg 0)))
           ("RowBox"
            (let ((row (car args)))
              (unless (eq (car row) :list)
                (signal 'wolfram-nb-unsupported-box '("row")))
              (wolfram-nb--box-row-text (cdr row))))
           ("SuperscriptBox" (format "%s^%s" (arg 0) (wolfram-nb--box-paren (arg 1))))
           ("SubscriptBox"
            (when (or (wolfram-nb--box-big-operator node)
                      (wolfram-nb--box-unsupported-operator-p node))
              (signal 'wolfram-nb-unsupported-box '("operator")))
            (format "Subscript[%s, %s]" (arg 0) (arg 1)))
           ("SubsuperscriptBox"
            (when (or (wolfram-nb--box-big-operator node)
                      (wolfram-nb--box-unsupported-operator-p node))
              (signal 'wolfram-nb-unsupported-box '("operator")))
            (format "Subsuperscript[%s, %s, %s]" (arg 0) (arg 1) (arg 2)))
           ("FractionBox" (format "%s/%s" (wolfram-nb--box-paren (arg 0))
                                  (wolfram-nb--box-paren (arg 1))))
           ("SqrtBox" (format "Sqrt[%s]" (arg 0)))
           ("RadicalBox" (format "Surd[%s, %s]" (arg 0) (arg 1)))
           ("OverscriptBox" (format "Overscript[%s, %s]" (arg 0) (arg 1)))
           ("UnderscriptBox"
            (when (wolfram-nb--box-unsupported-operator-p node)
              (signal 'wolfram-nb-unsupported-box '("operator")))
            (format "Underscript[%s, %s]" (arg 0) (arg 1)))
           ("UnderoverscriptBox"
            (when (or (wolfram-nb--box-big-operator node)
                      (wolfram-nb--box-unsupported-operator-p node))
              (signal 'wolfram-nb-unsupported-box '("operator")))
            (format "Underoverscript[%s, %s, %s]" (arg 0) (arg 1) (arg 2)))
           ("GridBox"
            (let ((rows (car args)))
              (unless (and (eq (car rows) :list)
                           (cl-every (lambda (r) (eq (car r) :list)) (cdr rows)))
                (signal 'wolfram-nb-unsupported-box '("grid")))
              (concat "{"
                      (mapconcat
                       (lambda (r) (concat "{" (mapconcat #'wolfram-nb--box-text (cdr r) ", ") "}"))
                       (cdr rows) ", ")
                      "}")))
           ((or "TagBox" "FormBox" "StyleBox" "AdjustmentBox") (arg 0))
           ("InterpretationBox"
            (wolfram-nb--expr-text (or (nth 1 args)
                                       (signal 'wolfram-nb-unsupported-box '("interp")))))
           (_ (signal 'wolfram-nb-unsupported-box (list head)))))))
    (_ (signal 'wolfram-nb-unsupported-box '("node")))))

(defun wolfram-nb--boxes-to-code (boxdata)
  "Return the code text of the BoxData[...] string BOXDATA, or nil.
Nil means the boxes hold something that is not plain code."
  (condition-case nil
      (with-temp-buffer
        (set-syntax-table wolfram-nb--parse-syntax-table)
        (insert boxdata)
        (goto-char (point-min))
        (let ((node (wolfram-nb--box-parse)))
          (wolfram-nb--box-skip-blank)
          (and (eobp)
               (equal (cadr node) "BoxData")
               (wolfram-nb--box-text node))))
    (error nil)))

(defconst wolfram-nb--complex-box-regexp
  "GraphicsBox\\|Graphics3DBox\\|RasterBox\\|FormBox\\|GridBox\\|DynamicBox\\|DynamicModuleBox\\|TemplateBox\\|PanelBox"
  "Box heads whose cells cannot be reduced to code and must be kept verbatim.")

(defun wolfram-nb--extract-boxdata-code (cell-string)
  "Return the code in the BoxData CELL-STRING.
When the boxes are not plain code (graphics, templates, anything the
converter does not know) the whole `BoxData[...]' string is returned so that
it is written back unchanged."
  (if (string-match-p wolfram-nb--complex-box-regexp cell-string)
      (string-trim cell-string)
    (or (wolfram-nb--boxes-to-code cell-string)
        (string-trim cell-string))))

(defun wolfram-nb--extract-cell-options (cell-string match-end)
  "Extract raw options string from CELL-STRING starting at MATCH-END.
Returns the options string (without leading comma) or nil."
  (let ((len (length cell-string)))
    (when (< match-end (1- len))
      (let ((rest (substring cell-string match-end (1- len)))) ;; Remove closing ]
        (when (string-match "\\`[ \t\n]*,[ \t\n]*" rest)
          (string-trim (substring rest (match-end 0))))))))

(defun wolfram-nb--parse-attr-wolfram (attr)
  "Parse style and options from ATTR string.
ATTR is a string like \":style \\\"StyleName\\\" :options \\\"options\\\"\".
Returns a cons cell (style . options)."
  (let ((style "Text")
        (options nil))
    (when attr
      (when (string-match ":style[ \t\n]*\"\\([^\"]*\\)\"" attr)
        (setq style (match-string 1 attr)))
      (when (string-match ":options[ \t\n]*\"\\([^\"\\\\]*\\(?:\\\\\\(?:.\\|\n\\)[^\"\\\\]*\\)*\\)\"" attr)
        (setq options (wolfram-nb--unescape-string (match-string 1 attr)))))
    (cons style options)))

(defun wolfram-nb--skip-top-level-arg ()
  "Move point over one top-level argument, stopping at its closing , or ]."
  (let ((done nil))
    (while (and (not done) (not (eobp)))
      (if (re-search-forward "[][{}\",]" nil t)
          (let ((char (char-before)))
            (goto-char (match-beginning 0))
            (if (memq char '(?, ?\]))
                (setq done t)
              (forward-sexp 1)))
        (goto-char (point-max))))))

(defun wolfram-nb--cell-style-info (cell-string)
  "Return (STYLE . END) for the Cell[...] in CELL-STRING, or nil.
STYLE is the second argument when it is a string literal, and END is where
it ends as an index into CELL-STRING.  The argument is located by walking
the top-level arguments, so strings inside box data cannot be mistaken for
it."
  (or (ignore-errors
        (with-temp-buffer
          (set-syntax-table wolfram-nb--parse-syntax-table)
          (insert cell-string)
          (goto-char (point-min))
          (when (looking-at "Cell\\[")
            (goto-char (match-end 0))
            (wolfram-nb--skip-top-level-arg)
            (when (looking-at ",[ \t\n]*")
              (goto-char (match-end 0))
              (let ((start (point)))
                (wolfram-nb--skip-top-level-arg)
                (let ((arg (string-trim
                            (buffer-substring-no-properties start (point)))))
                  (when (string-match "\\`\"\\([A-Za-z][A-Za-z0-9]*\\)\"\\'" arg)
                    (cons (match-string 1 arg) (1- (point))))))))))
      (when (string-match "\\],[ \t\n]*\"\\([A-Z][a-zA-Z]*\\)\"" cell-string)
        (cons (match-string 1 cell-string) (match-end 0)))))

(defun wolfram-nb--parse-cell (cell-string)
  "Parse a single Cell[...] structure from CELL-STRING.
Returns a `wolfram-nb-cell' struct, or nil for CellGroupData/unparseable."
  (cond
   ;; CellGroupData wrapper — handled by extract-cells-from-group
   ((wolfram-nb--is-cellgroupdata cell-string)
    nil)

   ;; BoxData cell: Cell[BoxData[...], "Style", ...]
   ((string-match "\\`Cell\\[BoxData\\[" cell-string)
    (when-let ((info (wolfram-nb--cell-style-info cell-string)))
      (let* ((style (car info))
             (style-end (cdr info))
             ;; Extract only the BoxData[...] content (first argument), not the whole cell
             (boxdata-content (wolfram-nb--extract-first-argument cell-string))
             (code nil)
             (raw-options (wolfram-nb--extract-cell-options cell-string style-end)))
        ;; Now extract code from the boxdata-content, not the entire cell
        (setq code (wolfram-nb--extract-boxdata-code boxdata-content))
        (let ((options nil))
          (when (string-match "CellLabel->\"\\([^\"]*\\)\"" cell-string)
            (push (cons 'cell-label (match-string 1 cell-string)) options))
          (wolfram-nb-cell-create :content code :style style :options options
                                  :raw-options raw-options
                                  :boxes (and (not (wolfram-nb--box-cell-p code))
                                              boxdata-content))))))

   ;; DynamicModuleBox
   ((string-match "\\`Cell\\[DynamicModuleBox\\[" cell-string)
    (wolfram-nb-cell-create :content "[Dynamic content]" :style "Output"))

   ;; TextData cell: Cell[TextData[{...}], "Style"]
   ((string-match "\\`Cell\\[TextData\\[" cell-string)
    (when-let ((info (wolfram-nb--cell-style-info cell-string)))
      (let* ((style (car info))
             (style-end (cdr info))
             ;; Extract only the TextData content (the argument of TextData[...])
             (textdata-wrapper (wolfram-nb--extract-first-argument cell-string))
             (raw-options (wolfram-nb--extract-cell-options cell-string style-end)))
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
           :raw-options raw-options
           :boxes textdata-wrapper)))))

   ;; Simple text cell: Cell["text", "Style", ...]
   ((string-match "\\`Cell\\[\"\\([^\"\\\\]*\\(?:\\\\\\(?:.\\|\n\\)[^\"\\\\]*\\)*\\)\",[ \t\n]*\"\\([A-Z][a-zA-Z]*\\)\"" cell-string)
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
         :raw-options raw-options
         :boxes (propertize (concat "\"" content-raw "\"")
                            'wolfram-nb-literal t)))))

   ;; Fallback/General parser for any unrecognized Cell[...] structure
   ((string-match "\\`Cell\\[" cell-string)
    (let* ((trimmed-cell (string-trim cell-string))
           (inner-args (and (string-prefix-p "Cell[" trimmed-cell)
                            (string-suffix-p "]" trimmed-cell)
                            (substring trimmed-cell 5 -1)))
           (args (and inner-args (wolfram-nb--split-args inner-args))))
      (when args
        (let* ((arg1 (nth 0 args))
               (arg2 (nth 1 args))
               (style "Text")
               (raw-options nil)
               (content "")
               (options nil))
          ;; Determine style and raw-options
          (cond
           ;; Case 1: arg2 exists and is a quoted string -> it is the style
           ((and arg2 (string-prefix-p "\"" arg2) (string-suffix-p "\"" arg2))
            (setq style (substring arg2 1 -1))
            (when (> (length args) 2)
              (setq raw-options (string-join (nthcdr 2 args) ", "))))
           ;; Case 2: arg2 exists but is not a quoted string -> arg2 is an option, style defaults
           (arg2
            (setq style (if (string-prefix-p "BoxData[" arg1) "Input" "Text"))
            (setq raw-options (string-join (nthcdr 1 args) ", ")))
           ;; Case 3: arg2 does not exist -> style defaults, no options
           (t
            (setq style (if (string-prefix-p "BoxData[" arg1) "Input" "Text"))))

          ;; Determine content
          (cond
           ((and (string-prefix-p "\"" arg1) (string-suffix-p "\"" arg1))
            (setq content (wolfram-nb--unescape-string (substring arg1 1 -1))))
           (t
            (setq content arg1)))

          ;; Extract options
          (when (and raw-options (string-match "CellLabel->\"\\([^\"]*\\)\"" raw-options))
            (push (cons 'cell-label (match-string 1 raw-options)) options))

          (wolfram-nb-cell-create
           :content content
           :style style
           :options options
           :raw-options raw-options)))))

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

(defun wolfram-nb--sexp-end (pos)
  "Return the position after the balanced expression that starts at POS, or nil."
  (save-excursion
    (with-syntax-table wolfram-nb--parse-syntax-table
      (goto-char pos)
      (ignore-errors (forward-sexp 1) (point)))))

(defun wolfram-nb--notebook-options-between (list-end nb-end)
  "Return the notebook options between LIST-END and NB-END, or nil.
LIST-END is the end of the cell list, NB-END the end of Notebook[...]."
  (when (and list-end nb-end (> (1- nb-end) list-end))
    (let ((opts (string-trim
                 (replace-regexp-in-string
                  "\\`[ \t\n]*,[ \t\n]*" ""
                  (buffer-substring-no-properties list-end (1- nb-end))))))
      (and (not (string-empty-p opts)) opts))))

(defun wolfram-nb--parse-notebook (file)
  "Parse Wolfram Notebook FILE into a list of `wolfram-nb-cell' structs.
Recursively unwraps CellGroupData structures.  Only the cell list of the
notebook is scanned: a Cell[...] inside the notebook options, such as a
docked toolbar, is kept with the options.
When called from a `wolfram-nb-mode' buffer, also sets
`wolfram-nb--notebook-options' as a side effect."
  (let* ((calling-buffer (current-buffer))
         (wolfram-nb--parse-opaque
          (or (buffer-local-value 'wolfram-nb--opaque-parts calling-buffer)
              (make-hash-table :test 'equal))))
    (with-current-buffer calling-buffer
      (setq wolfram-nb--opaque-parts wolfram-nb--parse-opaque))
    (with-temp-buffer
      (insert-file-contents file)
      (goto-char (point-min))
      (unless (re-search-forward "Notebook\\[{" nil t)
        (signal 'wolfram-nb-parse-error (list "Not a valid Notebook file" file)))
      (let* ((nb-open (match-beginning 0))
             (list-end (wolfram-nb--sexp-end (1- (match-end 0))))
             (nb-end (wolfram-nb--sexp-end (+ nb-open (length "Notebook")))))
        (let ((cells '()))
          (while (re-search-forward "Cell\\[" (or list-end (point-max)) t)
            (goto-char (match-beginning 0))
            (let* ((cell-start (point))
                   (cell-end (wolfram-nb--find-cell-end cell-start)))
              (when cell-end
                (let ((cell-str (buffer-substring-no-properties cell-start cell-end)))
                  (if (wolfram-nb--is-cellgroupdata cell-str)
                      (setq cells (nconc cells (wolfram-nb--extract-cells-from-group cell-str)))
                    (let ((parsed (wolfram-nb--parse-cell cell-str)))
                      (when parsed
                        (setq cells (nconc cells (list parsed)))))))
                (goto-char cell-end))))
          ;; Extract notebook-level options
          (let ((opts (if list-end
                          (wolfram-nb--notebook-options-between list-end nb-end)
                        (goto-char (point-min))
                        (when (re-search-forward "}\\s-*," nil t)
                          (let ((rest (string-trim
                                       (buffer-substring-no-properties
                                        (point)
                                        (progn (goto-char (point-max))
                                               (skip-chars-backward " \t\n")
                                               (when (and (not (bobp)) (= (char-before) ?\]))
                                                 (backward-char))
                                               (point))))))
                            (and (not (string-empty-p rest)) rest))))))
            (when opts
              (with-current-buffer calling-buffer
                (setq wolfram-nb--notebook-options opts)
                (let ((session (wolfram-nb--session-from-tagging-rules opts)))
                  (when session
                    (setq wolfram-nb--session-raw session
                          wolfram-nb--session-endpoint (wolfram-nb--parse-endpoint session)))))))
          cells)))))

;;;; Cell -> Org conversion

(defun wolfram-nb--string-parts (string rich-context)
  "Return (PARTS . RICH) for the text STRING.
Tokens standing for inline boxes are replaced by the boxes themselves, which
makes the text rich."
  (if (not (and wolfram-nb--opaque-parts
                (string-match-p wolfram-nb--opaque-regexp string)))
      (if rich-context
          (cons (list (format "\"%s\"" (wolfram-nb--escape-string string))) nil)
        (cons (list string) nil))
    (let ((parts '()) (pos 0))
      (while (string-match wolfram-nb--opaque-regexp string pos)
        (let ((before (substring string pos (match-beginning 0)))
              (box (gethash (match-string 1 string) wolfram-nb--opaque-parts))
              (token (match-string 0 string)))
          (unless (string-empty-p before)
            (push (format "\"%s\"" (wolfram-nb--escape-string before)) parts))
          (push (or box (format "\"%s\"" (wolfram-nb--escape-string token))) parts)
          (setq pos (match-end 0))))
      (unless (= pos (length string))
        (push (format "\"%s\"" (wolfram-nb--escape-string (substring string pos)))
              parts))
      (cons (nreverse parts) t))))

(defun wolfram-nb--org-element-to-textdata (el &optional rich-context)
  "Convert Org element EL to a cons of (parts-list . is-rich).
RICH-CONTEXT is non-nil if we are inside a rich-text element (e.g. bold)."
  (cond
   ((stringp el)
    (wolfram-nb--string-parts el rich-context))
   (t
    (let* ((type (org-element-type el))
           (contents (org-element-contents el))
           (is-inline-rich (memq type '(bold italic underline code verbatim)))
           (any-rich is-inline-rich)
           (child-results '()))
      ;; First pass: check if any child is rich
      (dolist (c contents)
        (let ((res (wolfram-nb--org-element-to-textdata c (or rich-context is-inline-rich))))
          (push res child-results)
          (when (cdr res) (setq any-rich t))))
      (setq child-results (nreverse child-results))
      
      (let ((res-cons
             (cond
              ;; Link elements
              ((eq type 'link)
               (let* ((link-type (org-element-property :type el))
                      (path (org-element-property :path el))
                      (desc-parts '())
                      (desc (when contents
                              (dolist (c contents)
                                (setq desc-parts (append desc-parts (car (wolfram-nb--org-element-to-textdata c rich-context)))))
                              (string-join desc-parts "")))
                      (raw-link (pcase (org-element-property :format el)
                                  ('plain (org-element-property :raw-link el))
                                  ('angle (format "<%s>" (org-element-property :raw-link el)))
                                  (_ (if desc
                                         (format "[[%s:%s][%s]]" link-type path desc)
                                       (format "[[%s:%s]]" link-type path))))))
                 (cons (if rich-context
                           (list (format "\"%s\"" (wolfram-nb--escape-string raw-link)))
                         (list raw-link))
                       nil)))

              ;; Code or verbatim elements
              ((memq type '(code verbatim))
               (let ((val (org-element-property :value el)))
                 (cons (list (format "StyleBox[\"%s\", \"Courier\"]" (wolfram-nb--escape-string val))) t)))
              
              ;; Bold, Italic, Underline elements
              (is-inline-rich
               (let* ((style (cond ((eq type 'bold) "Bold")
                                   ((eq type 'italic) "Italic")
                                   ((eq type 'underline) "Underlined")))
                      (inner-parts '()))
                 (dolist (c contents)
                   (let ((res (wolfram-nb--org-element-to-textdata c t)))
                     (setq inner-parts (append inner-parts (car res)))))
                 (let ((joined-inner (string-join inner-parts ", ")))
                   (cons (list (format "StyleBox[%s, \"%s\"]" joined-inner style)) t))))
              
              ;; Other/Container elements
              (t
               (let ((parts '()))
                 (dolist (c contents)
                   (let ((res (wolfram-nb--org-element-to-textdata c (or rich-context any-rich))))
                     (setq parts (append parts (car res)))))
                 (cons parts any-rich))))))
        ;; Append trailing spaces if this is an inline element and has post-blank
        (let* ((post-blank (or (org-element-property :post-blank el) 0))
               (parts (car res-cons))
               (rich (cdr res-cons)))
          (if (and (> post-blank 0) (memq type '(bold italic underline code verbatim link)))
              (let ((blank-str (make-string post-blank ?\s)))
                (cons (append parts (list (if (or rich-context rich)
                                              (format "\"%s\"" blank-str)
                                            blank-str)))
                      rich))
            res-cons)))))))

(defun wolfram-nb--cell-uuid (opts)
  "Return the ExpressionUUID in the cell options OPTS, or an empty string."
  (if (and opts (string-match "ExpressionUUID[ \t\n]*->[ \t\n]*\"\\([^\"]*\\)\"" opts))
      (match-string 1 opts)
    ""))

(defun wolfram-nb--optionless-style-p (style)
  "Return non-nil if cells of STYLE cannot carry an attribute line in Org."
  (or (member style '("Title" "Subtitle"))
      (assoc style wolfram-nb-list-styles)
      (assoc style wolfram-nb-numbered-list-styles)))

(defun wolfram-nb--source-key (style opts text)
  "Return the key of a cell of STYLE with options OPTS shown as TEXT.
Each call counts one more occurrence of the same cell, so identical cells
get distinct keys in document order."
  (let* ((uuid (if (wolfram-nb--optionless-style-p style)
                   ""
                 (wolfram-nb--cell-uuid opts)))
         (base (concat style "\0" uuid "\0" (string-trim text)))
         (n (if wolfram-nb--box-counts (gethash base wolfram-nb--box-counts 0) 0)))
    (when wolfram-nb--box-counts
      (puthash base (1+ n) wolfram-nb--box-counts))
    (if (= n 0) base (format "%s\0#%d" base n))))

(defun wolfram-nb--remember-boxes (cell shown)
  "Remember the boxes and options of CELL, which is shown in Org as SHOWN."
  (let ((style (wolfram-nb-cell-style cell))
        (opts (wolfram-nb-cell-raw-options cell)))
    (when (or (wolfram-nb-cell-boxes cell)
              (and opts (wolfram-nb--optionless-style-p style)))
      (unless wolfram-nb--box-sources
        (setq wolfram-nb--box-sources (make-hash-table :test 'equal)))
      (puthash (wolfram-nb--source-key style opts shown)
               (cons (wolfram-nb-cell-boxes cell) opts)
               wolfram-nb--box-sources))))

(defun wolfram-nb--lookup-source (style opts text)
  "Return (BOXES . OPTIONS) remembered for the unedited cell shown as TEXT."
  (and wolfram-nb--box-sources
       (gethash (wolfram-nb--source-key style opts text)
                wolfram-nb--box-sources)))

(defun wolfram-nb--stash-cell-content (content)
  "Keep CONTENT in the buffer-local cell cache and return its placeholder ID."
  (unless wolfram-nb--large-cells-cache
    (setq wolfram-nb--large-cells-cache (make-hash-table :test 'equal)))
  (let ((id (format "large-cell-%d"
                    (1+ (hash-table-count wolfram-nb--large-cells-cache)))))
    (puthash id content wolfram-nb--large-cells-cache)
    id))

(defun wolfram-nb--format-size (len)
  "Format the character count LEN as a short size string."
  (if (>= len 1048576)
      (format "%.1fM" (/ (float len) 1048576.0))
    (format "%.1fK" (/ (float len) 1024.0))))

(defun wolfram-nb--box-cell-p (content)
  "Return non-nil if CONTENT is verbatim box data that must not be edited."
  (string-prefix-p "BoxData[" content))

(defun wolfram-nb--placeholder-block (id style raw-opts label)
  "Return the Org text of a raw placeholder block for cached cell ID.
STYLE is the cell style, RAW-OPTS its Wolfram options and LABEL describes it."
  (format "#+ATTR_WOLFRAM: :style \"%s\" :id \"%s\"%s\n#+begin_src wolfram-raw\n%s\n#+end_src\n\n"
          style id
          (if raw-opts
              (format " :options \"%s\"" (wolfram-nb--escape-string raw-opts))
            "")
          label))

(defun wolfram-nb--flatten-options (opts)
  "Return the cell options OPTS written on a single line, or nil.
Notebooks wrap long options over several lines, which would end the one-line
#+ATTR_WOLFRAM: keyword.  Whitespace outside strings that contains a newline
becomes one space.  Inside a string a newline becomes the escape \\n and a
backslash-newline continuation disappears, so no string changes its value."
  (when opts
    (let ((out nil) (in-string nil) (i 0) (n (length opts)))
      (while (< i n)
        (let ((c (aref opts i)))
          (cond
           (in-string
            (cond
             ((and (eq c ?\\) (< (1+ i) n))
              (let ((next (aref opts (1+ i))))
                (unless (eq next ?\n)
                  (push c out)
                  (push next out))
                (setq i (1+ i))))
             ((eq c ?\") (push c out) (setq in-string nil))
             ((eq c ?\n) (push ?\\ out) (push ?n out))
             (t (push c out))))
           ((eq c ?\") (push c out) (setq in-string t))
           ((memq c '(?\s ?\t ?\n ?\r))
            (let ((j i) (newline nil))
              (while (and (< j n) (memq (aref opts j) '(?\s ?\t ?\n ?\r)))
                (when (memq (aref opts j) '(?\n ?\r)) (setq newline t))
                (setq j (1+ j)))
              (if newline
                  (push ?\s out)
                (dotimes (k (- j i)) (push (aref opts (+ i k)) out)))
              (setq i (1- j))))
           (t (push c out))))
        (setq i (1+ i)))
      (apply #'string (nreverse out)))))

(defun wolfram-nb--paragraph-safe-p (content)
  "Return non-nil if CONTENT survives as one ordinary Org paragraph.
Blank lines split a paragraph, and a line that starts like a headline, list
item, comment, table or keyword changes the kind of cell it becomes."
  (and (not (string-empty-p content))
       (not (string-match-p "\\`[ \t\n]\\|[ \t\n]\\'" content))
       (not (string-match-p "\n[ \t]*\n" content))
       (not (string-match-p
             (concat "\\(?:\\`\\|\n\\)[ \t]*"
                     "\\(?:[-+*][ \t]\\|[0-9]+[.)][ \t]\\|#\\|:[ \t]\\||\\|-----"
                     "\\|\\\\\\(?:begin\\|\\[\\)\\|\\[fn:\\)")
             content))))

(defun wolfram-nb--attr-line (style default-style opts)
  "Return the #+ATTR_WOLFRAM: line for a block of STYLE with options OPTS.
DEFAULT-STYLE is the style read back when the line does not name one.  The
result is empty when there is nothing to record."
  (let ((opts (wolfram-nb--flatten-options opts)))
    (cond
     ((and (equal style default-style) (not opts)) "")
     ((equal style default-style) (format "#+ATTR_WOLFRAM: %s\n" opts))
     (t (format "#+ATTR_WOLFRAM: :style \"%s\"%s\n" style
                (if opts
                    (format " :options \"%s\"" (wolfram-nb--escape-string opts))
                  ""))))))

(defun wolfram-nb--parse-block-attr (attr default-style)
  "Return (STYLE . OPTIONS) from the ATTR_WOLFRAM string ATTR of a block.
ATTR is either raw cell options or the keyword form `:style \"S\" :options \"O\"'."
  (cond
   ((or (null attr) (string-empty-p (string-trim attr)))
    (cons default-style nil))
   ((string-prefix-p ":" (string-trim attr))
    (let ((parsed (wolfram-nb--parse-attr-wolfram attr)))
      (cons (if (string-match-p ":style[ \t\n]*\"" attr) (car parsed) default-style)
            (cdr parsed))))
   (t (cons default-style attr))))

(defun wolfram-nb--with-label (opts name)
  "Return the options OPTS with CellLabel set to the block NAME, if any."
  (cond
   ((null name) opts)
   ((and opts (string-match "CellLabel[ \t\n]*->[ \t\n]*\"[^\"]*\"" opts))
    (replace-match (format "CellLabel->\"%s\"" name) t t opts))
   (opts (format "%s, CellLabel->\"%s\"" opts name))
   (t (format "CellLabel->\"%s\"" name))))

(defun wolfram-nb--trim-trailing-newline (parts rich)
  "Drop the newline Org leaves at the end of the last of PARTS when RICH."
  (let* ((last-part (car (last parts)))
         (body (and rich last-part
                    (string-match "\\`\"\\(.*\\)\"\\'" last-part)
                    (match-string 1 last-part))))
    (if (not body)
        parts
      (while (and (string-suffix-p "\\n" body)
                  ;; an escape only if an even number of backslashes precede it
                  (let ((k 0) (j (- (length body) 3)))
                    (while (and (>= j 0) (eq (aref body j) ?\\))
                      (setq k (1+ k) j (1- j)))
                    (= (% k 2) 0)))
        (setq body (substring body 0 -2)))
      (append (butlast parts)
              (unless (string-empty-p body) (list (format "\"%s\"" body)))))))

(defun wolfram-nb--parts-to-content (parts rich)
  "Join the text PARTS into cell content; RICH parts become a TextData."
  (let ((parts (wolfram-nb--trim-trailing-newline parts rich)))
    (if rich
        (format "TextData[{%s}]" (string-join parts ", "))
      (string-join parts ""))))

(defun wolfram-nb--text-block-content (value)
  "Return the cell content for the text VALUE of a wolfram-text block.
Inline markup is read with Org's object parser only, so nothing in VALUE can
be taken for a headline, list or keyword."
  (let* ((text (string-trim-right (org-unescape-code-in-string value) "\n"))
         (objects (org-element-parse-secondary-string
                   text (org-element-restriction 'paragraph)))
         (res (wolfram-nb--org-element-to-textdata
               (cons 'paragraph (cons nil objects)))))
    (wolfram-nb--unprotect-markup
     (wolfram-nb--parts-to-content (car res) (cdr res)))))

(defun wolfram-nb-cell-boxes-rich-p (cell)
  "Return non-nil if CELL was built from TextData, whose markers are formatting."
  (let ((boxes (wolfram-nb-cell-boxes cell)))
    (and boxes (not (get-text-property 0 'wolfram-nb-literal boxes)))))

(defun wolfram-nb--element-text (element)
  "Return the raw text of the paragraph ELEMENT in the current buffer.
Unlike `org-element-interpret-data' this leaves out affiliated keywords."
  (string-trim
   (buffer-substring-no-properties (org-element-property :contents-begin element)
                                   (org-element-property :contents-end element))))

(defun wolfram-nb--markup-p (text)
  "Return non-nil if Org would read inline markup or a link in TEXT."
  (cl-some (lambda (object) (not (stringp object)))
           (org-element-parse-secondary-string
            text (org-element-restriction 'paragraph))))

(defun wolfram-nb--protect-markup (text)
  "Return TEXT with a zero-width space before markers Org would act on.
For plain strings, whose asterisks and slashes are not formatting."
  (if (not (wolfram-nb--markup-p text))
      text
    (replace-regexp-in-string
     "\\(\\`\\|[[:space:](\\[{'\"-]\\)\\([*/_=~+]\\|\\[\\[\\)"
     "\\1\u200b\\2" text)))

(defun wolfram-nb--unprotect-markup (text)
  "Remove the zero-width spaces `wolfram-nb--protect-markup' added to TEXT."
  (replace-regexp-in-string "\u200b" "" text))

(defun wolfram-nb--one-line (text)
  "Return TEXT with each newline turned into a space."
  (replace-regexp-in-string "[ \t]*\n[ \t]*" " " text))

(defun wolfram-nb--cell-to-org (cell)
  "Convert a `wolfram-nb-cell' CELL to Org-mode text."
  (let* ((style (wolfram-nb-cell-style cell))
         (content (wolfram-nb-cell-content cell))
         (raw-opts (wolfram-nb-cell-raw-options cell)))
    (if (or (wolfram-nb--box-cell-p content)
            (and (> (length content) 50000)
                 (string-match-p "BoxData\\|GraphicsBox\\|RasterBox\\|CompressedData" content)))
        (wolfram-nb--placeholder-block
         (wolfram-nb--stash-cell-content content)
         style raw-opts
         (if (> (length content) 50000)
             (format "<Large Cell Block (%s) - Hidden to prevent Emacs from freezing. Will be preserved on save.>"
                     (wolfram-nb--format-size (length content)))
           (format "<Graphics Block (%s) - kept verbatim and preserved on save.>"
                   (wolfram-nb--format-size (length content)))))
      (progn
        (wolfram-nb--remember-boxes
         cell (cond
               ((or (assoc style wolfram-nb-headline-styles)
                    (member style '("Title" "Subtitle")))
                (wolfram-nb--one-line content))
               ((or (assoc style wolfram-nb-list-styles)
                    (assoc style wolfram-nb-numbered-list-styles))
                (replace-regexp-in-string
                 "\\`[•●◦-][ \t]*\\|\\`[0-9]+\\.\\s-*" "" content))
               (t content)))
      (cond
       ;; Special Keywords
       ((string= style "Title")
        (format "#+TITLE: %s\n\n" (wolfram-nb--one-line content)))
       ((string= style "Subtitle")
        (format "#+SUBTITLE: %s\n\n" (wolfram-nb--one-line content)))
       
       ;; Headlines
       ((assoc style wolfram-nb-headline-styles)
        (let ((level (cdr (assoc style wolfram-nb-headline-styles))))
          (format "%s %s\n%s"
                  (make-string level ?*)
                  (wolfram-nb--one-line content)
                  (if raw-opts
                      (format ":PROPERTIES:\n:WOLFRAM_OPTIONS: %s\n:END:\n"
                              (wolfram-nb--flatten-options raw-opts))
                    ""))))

       ;; A plain item whose characters Org would read as markup: a literal block.
       ((and (or (assoc style wolfram-nb-list-styles)
                 (assoc style wolfram-nb-numbered-list-styles))
             (not (wolfram-nb-cell-boxes-rich-p cell))
             (not (string-empty-p content))
             (wolfram-nb--markup-p content))
        (format "%s#+begin_src wolfram-string\n%s\n#+end_src\n\n"
                (wolfram-nb--attr-line style "Text" raw-opts)
                (org-escape-code-in-string content)))

       ;; Lists
       ((or (assoc style wolfram-nb-list-styles)
            (assoc style wolfram-nb-numbered-list-styles))
        (let* ((numbered (assoc style wolfram-nb-numbered-list-styles))
               (level (cdr (or numbered (assoc style wolfram-nb-list-styles))))
               (indent (make-string (* (1- level) 2) ?\s))
               (bullet (if numbered "1. " "- ")))
          (format "%s%s%s\n"
                  indent
                  bullet
                  (replace-regexp-in-string "\\`[•●◦-][ \t]*\\|\\`[0-9]+\\.\\s-*" "" content))))

       ;; Blockquotes
       ((string= style "Quote")
        (format "%s#+begin_quote\n%s\n#+end_quote\n\n"
                (wolfram-nb--attr-line style "Quote" raw-opts)
                content))

       ;; Paragraphs: ordinary text stays a paragraph, anything Org would
       ;; read differently is kept in a block that Org does not interpret.
       ((or (string= style "Text") (string= style "ItemParagraph"))
        (cond
         ;; A plain string whose characters Org would read as markup is
         ;; kept literally: the asterisks in it are not formatting.
         ((and (null (wolfram-nb-cell-boxes-rich-p cell))
               (not (string-empty-p content))
               (wolfram-nb--markup-p content))
          (format "%s#+begin_src wolfram-string\n%s\n#+end_src\n\n"
                  (wolfram-nb--attr-line style "Text" raw-opts)
                  (org-escape-code-in-string content)))
         ((wolfram-nb--paragraph-safe-p content)
          (format "%s%s\n\n"
                  (wolfram-nb--attr-line style "Text" raw-opts)
                  content))
         (t
          (format "%s#+begin_src wolfram-text\n%s\n#+end_src\n\n"
                  (wolfram-nb--attr-line style "Text" raw-opts)
                  (org-escape-code-in-string content)))))

       ;; Code Blocks
       ((or (string= style "Code") (string= style "Input"))
        (let ((label (cdr (assoc 'cell-label (wolfram-nb-cell-options cell)))))
          (format "%s%s#+begin_src wolfram\n%s\n#+end_src\n\n"
                  (if label (format "#+NAME: %s\n" label) "")
                  (wolfram-nb--attr-line style "Input" raw-opts)
                  (org-escape-code-in-string content))))
       
       ;; Example Blocks
       ((or (string= style "Output") (string= style "Print"))
        (let ((label (cdr (assoc 'cell-label (wolfram-nb-cell-options cell)))))
          (format "%s%s#+begin_example\n%s\n#+end_example\n\n"
                  (if label (format "#+NAME: %s\n" label) "")
                  (wolfram-nb--attr-line style "Output" raw-opts)
                  (org-escape-code-in-string content))))

       ;; Fallback
       (t
        (format "#+ATTR_WOLFRAM: :style \"%s\"%s\n#+begin_src wolfram-raw\n%s\n#+end_src\n\n"
                style
                (if raw-opts (format " :options \"%s\"" (wolfram-nb--escape-string raw-opts)) "")
                (org-escape-code-in-string content))))))))

(defun wolfram-nb--cells-to-org (cells)
  "Convert a list of `wolfram-nb-cell' CELLS to Org-mode text."
  (let ((body (let ((wolfram-nb--box-counts (make-hash-table :test 'equal)))
                (mapconcat #'wolfram-nb--cell-to-org cells "")))
        (session wolfram-nb--session-raw))
    (if (and session (not (string-empty-p session)))
        (concat (format "#+WOLFRAM_SESSION: %s\n\n" session) body)
      body)))

;;;; Org -> Cell conversion

(defun wolfram-nb--make-cell-string (content style &optional raw-options)
  "Create a Cell[...] string with CONTENT and STYLE.
RAW-OPTIONS, if provided, is appended after the style.
If CONTENT looks like raw BoxData/TextData/RawData/DynamicModuleBox,
it is inserted as-is without extra quotes/escaping."
  (let* ((literal (and (> (length content) 0)
                       (get-text-property 0 'wolfram-nb-literal content)))
         (trimmed (string-trim content))
         (final-content
          (cond
           (literal (substring-no-properties content))
           ((string-match-p "\\`\\(BoxData\\|TextData\\|RawData\\|DynamicModuleBox\\)\\s-*\\[" trimmed)
            trimmed)
           ((and wolfram-nb--opaque-parts
                 (string-match-p wolfram-nb--opaque-regexp trimmed))
            (format "TextData[{%s}]"
                    (string-join (car (wolfram-nb--string-parts trimmed t)) ", ")))
           (t (concat "\"" (wolfram-nb--escape-string trimmed) "\"")))))
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
  (let ((cache wolfram-nb--large-cells-cache)
        (sources wolfram-nb--box-sources)
        (opaque wolfram-nb--opaque-parts))
    (with-temp-buffer
      (insert org-text)
      (org-mode)
      (setq-local wolfram-nb--large-cells-cache cache)
      (setq-local wolfram-nb--box-sources sources)
      (setq-local wolfram-nb--opaque-parts opaque)
      (let ((tree (org-element-parse-buffer))
            (cells '())
            (wolfram-nb--box-counts (make-hash-table :test 'equal)))
      ;; #+TITLE: -> Title cell
      (org-element-map tree 'keyword
        (lambda (kw)
          (pcase (org-element-property :key kw)
            ((or "TITLE" "SUBTITLE")
             (let* ((style (if (equal (org-element-property :key kw) "TITLE")
                               "Title" "Subtitle"))
                    (value (org-element-property :value kw))
                    (entry (wolfram-nb--lookup-source style nil value)))
               (push (wolfram-nb--make-cell-string
                      (or (car entry) value) style (cdr entry))
                     cells))))))
      ;; Main content
      (org-element-map tree '(headline paragraph plain-list src-block example-block quote-block table horizontal-rule)
        (lambda (element)
          (pcase (org-element-type element)
            ('headline
             (let* ((level (org-element-property :level element))
                    (title-objects (org-element-property :title element))
                    (title (org-element-interpret-data title-objects))
                    (title-res (wolfram-nb--org-element-to-textdata
                                (cons 'paragraph (cons nil title-objects))))
                    (style (or (car (rassoc level wolfram-nb-headline-styles))
                               "Section"))
                    (raw-opts (org-element-property :WOLFRAM_OPTIONS element)))
               (push (wolfram-nb--make-cell-string
                      (or (car (wolfram-nb--lookup-source style raw-opts title))
                          (wolfram-nb--unprotect-markup
                           (wolfram-nb--parts-to-content (car title-res) (cdr title-res))))
                      style raw-opts)
                     cells)))

            ('paragraph
             (unless (org-element-lineage element '(item quote-block))
               (let* ((res (wolfram-nb--org-element-to-textdata element))
                      (attr (wolfram-nb--parse-block-attr
                             (car (org-element-property :attr_wolfram element))
                             "Text"))
                      (cell-content
                       (or (car (wolfram-nb--lookup-source
                                 (car attr) (cdr attr)
                                 (wolfram-nb--element-text element)))
                           (wolfram-nb--unprotect-markup
                            (wolfram-nb--parts-to-content (car res) (cdr res))))))
                 (unless (string-blank-p cell-content)
                   (push (wolfram-nb--make-cell-string
                          cell-content (car attr) (cdr attr))
                         cells)))))

            ('plain-list
             (unless (org-element-lineage element '(item plain-list))
               (org-element-map element 'item
                 (lambda (item)
                   (let* ((list-depth
                           (let ((lvl 0) (p (org-element-property :parent item)))
                             (while p
                               (when (eq (org-element-type p) 'plain-list)
                                 (setq lvl (1+ lvl)))
                               (setq p (org-element-property :parent p)))
                             lvl))
                          (is-numbered (string-match-p "\\`[0-9]" (or (org-element-property :bullet item) "")))
                          (style (if is-numbered
                                     (or (car (rassoc list-depth wolfram-nb-numbered-list-styles)) "ItemNumbered")
                                   (or (car (rassoc list-depth wolfram-nb-list-styles)) "Item")))
                          (first-child (car (org-element-contents item)))
                          ;; Only the item's own paragraph: sub-items are cells of their own.
                          (res (wolfram-nb--org-element-to-textdata
                                (if (and first-child
                                         (eq (org-element-type first-child) 'paragraph))
                                    first-child
                                  item)))
                          (entry (wolfram-nb--lookup-source
                                  style nil
                                  (if (and first-child
                                           (eq (org-element-type first-child) 'paragraph))
                                      (wolfram-nb--element-text first-child)
                                    "")))
                          (text (or (car entry)
                                    (wolfram-nb--unprotect-markup
                                     (wolfram-nb--parts-to-content (car res) (cdr res))))))
                     (unless (string-blank-p text)
                       (push (wolfram-nb--make-cell-string text style (cdr entry))
                             cells)))))))

            ('quote-block
             (let ((text (string-trim (org-element-interpret-data element)))
                   (attr (wolfram-nb--parse-block-attr
                          (car (org-element-property :attr_wolfram element))
                          "Quote")))
               (push (wolfram-nb--make-cell-string text (car attr) (cdr attr))
                     cells)))

            ('table
             (let ((text (string-trim (org-element-interpret-data element))))
               (push (wolfram-nb--make-cell-string text "Text") cells)))

            ('horizontal-rule
             (push (wolfram-nb--make-cell-string "----" "Text") cells))

            ('src-block
             (let* ((lang (org-element-property :language element))
                    (value (org-element-property :value element))
                    (name (org-element-property :name element))
                    (raw-opts (car (org-element-property :attr_wolfram element))))
               (cond
                ((string= lang "wolfram-raw")
                 (let* ((id (and raw-opts
                                 (string-match ":id[ \t\n]*\"\\([^\"]*\\)\"" raw-opts)
                                 (match-string 1 raw-opts)))
                        (cached-content (and id
                                             wolfram-nb--large-cells-cache
                                             (gethash id wolfram-nb--large-cells-cache)))
                        (cell-content (or cached-content
                                          (org-unescape-code-in-string value)))
                        (parsed-attr (wolfram-nb--parse-attr-wolfram raw-opts))
                        (style (car parsed-attr))
                        (opts (wolfram-nb--with-label (cdr parsed-attr) name)))
                   (push (wolfram-nb--make-cell-string cell-content style opts) cells)))
                ((string= lang "wolfram-string")
                 (let* ((attr (wolfram-nb--parse-block-attr raw-opts "Text"))
                        (text (string-trim-right
                               (org-unescape-code-in-string value) "\n")))
                   (push (wolfram-nb--make-cell-string
                          (or (car (wolfram-nb--lookup-source
                                    (car attr) (cdr attr) text))
                              text)
                          (car attr)
                          (wolfram-nb--with-label (cdr attr) name))
                         cells)))
                ((string= lang "wolfram-text")
                 (let ((attr (wolfram-nb--parse-block-attr raw-opts "Text")))
                   (push (wolfram-nb--make-cell-string
                          (or (car (wolfram-nb--lookup-source
                                    (car attr) (cdr attr)
                                    (string-trim-right
                                     (org-unescape-code-in-string value) "\n")))
                              (wolfram-nb--text-block-content value))
                          (car attr)
                          (wolfram-nb--with-label (cdr attr) name))
                         cells)))
                (t
                 (let ((attr (wolfram-nb--parse-block-attr
                              raw-opts
                              (if (and lang (string= lang "wolfram")) "Input" "Code"))))
                   (push (wolfram-nb--make-cell-string
                          (let ((text (org-unescape-code-in-string value)))
                            (or (car (wolfram-nb--lookup-source
                                      (car attr) (cdr attr) text))
                                text))
                          (car attr)
                          (wolfram-nb--with-label (cdr attr) name))
                         cells))))))

            ('example-block
             (let* ((value (org-element-property :value element))
                    (name (org-element-property :name element))
                    (attr (wolfram-nb--parse-block-attr
                           (car (org-element-property :attr_wolfram element))
                           "Output")))
               (push (wolfram-nb--make-cell-string
                      (let ((text (org-unescape-code-in-string value)))
                        (or (car (wolfram-nb--lookup-source
                                  (car attr) (cdr attr) text))
                            text))
                      (car attr)
                      (wolfram-nb--with-label (cdr attr) name))
                     cells))))))
      (nreverse cells)))))

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
    (wolfram-nb-apply-buffer-overlays)
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
  "Parse RAW endpoint into (HOST PORT PATH).
RAW is a string like \"host:port\" or \"host:port/path\".
Defaults host to \"localhost\" and path to \"/\" when not given."
  (when (and raw (not (string-empty-p (string-trim raw))))
    (let* ((s (string-trim raw))
           (port-part s)
           (path "/")
           (host "localhost")
           (port nil))
      (when (string-match "\\`\\([^/]+\\)\\(/.*\\)\\'" s)
        (setq port-part (match-string 1 s)
              path (match-string 2 s)))
      (if (string-match "\\`\\([^:]+\\):\\([0-9]+\\)\\'" port-part)
          (setq host (match-string 1 port-part)
                port (string-to-number (match-string 2 port-part)))
        (setq port (string-to-number port-part)))
      (list host port path))))

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
       (nth 1 wolfram-nb--session-endpoint)
       (> (nth 1 wolfram-nb--session-endpoint) 0)))

(defun wolfram-nb--session-url ()
  "Build the full URL for the session endpoint."
  (when (wolfram-nb--session-active-p)
    (format "http://%s:%d%s"
            (nth 0 wolfram-nb--session-endpoint)
            (nth 1 wolfram-nb--session-endpoint)
            (nth 2 wolfram-nb--session-endpoint))))

;;;; Evaluation — HTTP session

(defun wolfram-nb--eval-via-session (expr)
  "Evaluate EXPR synchronously via HTTP POST to the session server.
Returns the result string."
  (require 'json)
  (let* ((url (wolfram-nb--session-url))
         (url-request-method "POST")
         (post-data (format "expr=%s" (url-hexify-string expr)))
         (url-request-data (encode-coding-string post-data 'utf-8))
         (url-request-extra-headers '(("Content-Type" . "application/x-www-form-urlencoded")))
         (result nil)
         (error-msg nil)
         (retrieve-buf nil))
    (unless url
      (signal 'wolfram-nb-eval-error '("No session endpoint configured")))
    (let ((inhibit-message t))
      (condition-case err
          (let ((buf (url-retrieve-synchronously url t t wolfram-nb-session-timeout)))
            (if (not buf)
                (setq error-msg "Could not retrieve URL (nil buffer)")
              (setq retrieve-buf buf)
              (with-current-buffer buf
                (goto-char (point-min))
                (if (re-search-forward "^HTTP/1\\..+ +\\([0-9]+\\)" nil t)
                    (let ((status (string-to-number (match-string 1))))
                      (if (= status 200)
                          (progn
                            (re-search-forward "^$" nil t)
                            (forward-char 1)
                            (let* ((raw-body (buffer-substring-no-properties (point) (point-max)))
                                   (decoded (string-trim (decode-coding-string
                                                          (encode-coding-string raw-body 'raw-text)
                                                          'utf-8))))
                              (let* ((json-object-type 'alist)
                                     (json-key-type 'string)
                                     (parsed (condition-case nil
                                                 (json-read-from-string decoded)
                                               (error nil))))
                                (if parsed
                                    (let ((success (cdr (assoc "Success" parsed))))
                                      (if (and success (not (eq success :json-false)))
                                          (setq result (cdr (assoc "Result" parsed)))
                                        (setq error-msg (cdr (assoc "Failure" parsed)))))
                                  (setq result decoded)))))
                        (setq error-msg (format "HTTP %d from session" status))))
                  (setq error-msg "No HTTP response from session")))))
        (error (setq error-msg (format "Session error: %s" (error-message-string err))))
        (quit (setq error-msg "Session evaluation timed out")))
      (when (buffer-live-p retrieve-buf)
        (kill-buffer retrieve-buf)))
    (if error-msg
        (signal 'wolfram-nb-eval-error (list error-msg))
      (or result ""))))

(defun wolfram-nb--eval-via-session-async (expr callback)
  "Evaluate EXPR asynchronously via HTTP POST to the session server.
Calls CALLBACK with the result string on success, or nil on error."
  (require 'json)
  (let* ((url (wolfram-nb--session-url))
         (url-request-method "POST")
         (post-data (format "expr=%s" (url-hexify-string expr)))
         (url-request-data (encode-coding-string post-data 'utf-8))
         (url-request-extra-headers '(("Content-Type" . "application/x-www-form-urlencoded"))))
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
                                    (let* ((raw-body (buffer-substring-no-properties (point) (point-max)))
                                           (decoded (string-trim (decode-coding-string
                                                                  (encode-coding-string raw-body 'raw-text)
                                                                  'utf-8))))
                                      (let* ((json-object-type 'alist)
                                             (json-key-type 'string)
                                             (parsed (condition-case nil
                                                         (json-read-from-string decoded)
                                                       (error nil))))
                                        (if parsed
                                            (let ((success (cdr (assoc "Success" parsed))))
                                              (if (and success (not (eq success :json-false)))
                                                  (setq result (cdr (assoc "Result" parsed)))
                                                (setq error-msg (cdr (assoc "Failure" parsed)))))
                                          (setq result decoded)))))
                                (setq error-msg (format "HTTP %d from session" http-status))))
                          (setq error-msg "No HTTP response from session")))
                      (kill-buffer)
                      (funcall cb (if error-msg nil (or result "")) error-msg)))
                  (list callback)
                  t)))

;;;; Evaluation — synchronous

(defun wolfram-nb--check-wolframscript ()
  "Return the path to wolframscript if available, nil otherwise.
If `wolfram-nb-wolframscript-path' is not found in PATH, searches in standard
system installation directories."
  (or (executable-find wolfram-nb-wolframscript-path)
      (let ((fallbacks
             (cond
              ((eq system-type 'darwin)
               '("/Applications/Mathematica.app/Contents/MacOS/wolframscript"
                 "/Applications/Wolfram Desktop.app/Contents/MacOS/wolframscript"
                 "/Applications/Wolfram Engine.app/Contents/MacOS/wolframscript"
                 "/usr/local/bin/wolframscript"
                 "/opt/homebrew/bin/wolframscript"))
              ((eq system-type 'windows-nt)
               '("C:\\Program Files\\Wolfram Research\\WolframScript\\wolframscript.exe"
                 "C:\\Program Files\\Wolfram Research\\Mathematica\\14.0\\wolframscript.exe"
                 "C:\\Program Files\\Wolfram Research\\Mathematica\\13.3\\wolframscript.exe"
                 "C:\\Program Files\\Wolfram Research\\Mathematica\\13.2\\wolframscript.exe"))
              (t
               '("/usr/bin/wolframscript"
                 "/usr/local/bin/wolframscript")))))
        (cl-find-if #'file-executable-p fallbacks))))

(defun wolfram-nb--eval-expression (expr &optional format)
  "Evaluate EXPR synchronously via wolframscript, return result string."
  (unless (wolfram-nb--check-wolframscript)
    (signal 'wolfram-nb-eval-error
            '("wolframscript not found; install Wolfram Engine or set wolfram-nb-wolframscript-path")))
  (with-temp-buffer
    (let* ((eval-expr (if format
                          (format "ExportString[%s, %S]" expr format)
                        expr))
           (exit-code (call-process wolfram-nb-wolframscript-path
                                    nil t nil "-code" eval-expr))
           (output nil))
      (setq output (buffer-substring-no-properties (point-min) (point-max)))
      (if (= exit-code 0)
          (string-trim output)
        (signal 'wolfram-nb-eval-error
                (list (format "Exit %d: %s" exit-code (string-trim output))))))))

;;;; Evaluation — persistent kernel

(defun wolfram-nb--kernel (&optional start)
  "Return the live kernel of the current buffer.
When START is non-nil and none is running, start one if that is possible and
allowed by `wolfram-nb-use-kernel'."
  (cond
   ((wolfram-nb-kernel-live-p wolfram-nb--kernel)
    wolfram-nb--kernel)
   ((and start wolfram-nb-use-kernel (wolfram-nb-kernel-available-p))
    (let ((crashed (and wolfram-nb--kernel t)))
      (setq wolfram-nb--kernel (wolfram-nb-kernel-start))
      (add-hook 'kill-buffer-hook #'wolfram-nb-kernel-quit nil t)
      (when crashed
        (message "Wolfram kernel was restarted; earlier definitions are gone."))
      wolfram-nb--kernel))))

(defun wolfram-nb-kernel-quit ()
  "Shut down the kernel of the current buffer."
  (interactive)
  (when wolfram-nb--kernel
    (wolfram-nb-kernel-stop wolfram-nb--kernel)
    (setq wolfram-nb--kernel nil)
    (when (called-interactively-p 'interactive)
      (message "Wolfram kernel stopped."))))

(defun wolfram-nb-kernel-restart ()
  "Restart the kernel of the current buffer, forgetting all definitions."
  (interactive)
  (wolfram-nb-kernel-quit)
  (if (wolfram-nb--kernel t)
      (message "Wolfram kernel starting...")
    (user-error "No Wolfram kernel available; set `wolfram-nb-kernel-program'")))

(defun wolfram-nb-kernel-info ()
  "Describe the kernel of the current buffer."
  (interactive)
  (let ((kernel wolfram-nb--kernel))
    (cond
     ((wolfram-nb-kernel-ready-p kernel)
      (message "Wolfram kernel ready: %s (%s)"
               (wolfram-nb-kernel-version kernel)
               (mapconcat #'identity (wolfram-nb-kernel-command kernel) " ")))
     ((wolfram-nb-kernel-live-p kernel)
      (message "Wolfram kernel is starting..."))
     (wolfram-nb--kernel
      (message "Wolfram kernel is not running: %s"
               (or (wolfram-nb-kernel-last-error kernel) "exited")))
     (t (message "No Wolfram kernel yet; it starts on the first evaluation.")))))

;;;; Evaluation results

(defun wolfram-nb--png-p (string)
  "Return non-nil if STRING starts with the PNG signature."
  (and (stringp string)
       (>= (length string) 4)
       (= (aref string 0) 137)
       (= (aref string 1) 80)
       (= (aref string 2) 78)
       (= (aref string 3) 71)))

(defun wolfram-nb--normalize-result (raw)
  "Turn RAW, a string from wolframscript or a session, into a result plist."
  (if (wolfram-nb--png-p raw)
      (list :status "ok" :result "" :png raw)
    (list :status "ok" :result (or raw ""))))

(defun wolfram-nb--result-text (result)
  "Return the text shown for the result plist RESULT."
  (string-join
   (cl-remove-if #'string-empty-p
                 (mapcar (lambda (key) (string-trim (or (plist-get result key) "")))
                         '(:stdout :messages :result)))
   "\n"))

(defun wolfram-nb--kernel-code (code format)
  "Return the code sent to the kernel for CODE with export FORMAT."
  (if (and format (not (string= (upcase format) "PNG")))
      (format "ExportString[(%s), %S]" code format)
    code))

(defun wolfram-nb--kernel-flags (format)
  "Return the kernel request flags for export FORMAT."
  (if (and format (string= (upcase format) "PNG")) "pb" "gb"))

(defun wolfram-nb--check-status (result)
  "Signal an eval error when RESULT reports a failed evaluation."
  (let ((status (plist-get result :status)))
    (when (member status '("timeout" "aborted"))
      (signal 'wolfram-nb-eval-error
              (list (format "Evaluation %s after %ss" status
                            (or (plist-get result :seconds) "?")))))
    result))

(defun wolfram-nb--eval-detailed (code &optional format)
  "Evaluate CODE and return a result plist.
The plist has :status, :result and, when there is any, :stdout, :messages,
:png and :boxes.  Uses the HTTP session when one is configured, else the
buffer's kernel, else a fresh wolframscript.  Signals `wolfram-nb-eval-error'."
  (wolfram-nb--refresh-session)
  (cond
   ((wolfram-nb--session-active-p)
    (wolfram-nb--normalize-result
     (wolfram-nb--eval-via-session
      (if format (format "ExportString[(%s), %S]" code format) code))))
   ((and wolfram-nb-use-kernel (wolfram-nb--kernel t))
    (condition-case err
        (wolfram-nb--check-status
         (wolfram-nb-kernel-eval-sync
          (wolfram-nb--kernel t) (wolfram-nb--kernel-code code format)
          :timeout wolfram-nb-eval-timeout
          :flags (wolfram-nb--kernel-flags format)))
      (wolfram-nb-kernel-error
       (signal 'wolfram-nb-eval-error (cdr err)))))
   (t
    (wolfram-nb--normalize-result (wolfram-nb--eval-expression code format)))))

(defun wolfram-nb--eval-one-shot-async (code format callback)
  "Evaluate CODE with a fresh wolframscript and call CALLBACK (RESULT ERROR)."
  (unless (wolfram-nb--check-wolframscript)
    (user-error "wolframscript not found"))
  (let* ((eval-code (if format (format "ExportString[(%s), %S]" code format) code))
         (proc
          (make-process
           :name "wolfram-eval"
           :buffer (generate-new-buffer " *wolfram-eval*")
           :command (list wolfram-nb-wolframscript-path "-code" eval-code)
           :sentinel
           (lambda (process _event)
             (when (memq (process-status process) '(exit signal))
               (let ((output (with-current-buffer (process-buffer process)
                               (string-trim (buffer-string))))
                     (exit-code (process-exit-status process)))
                 (kill-buffer (process-buffer process))
                 (if (= exit-code 0)
                     (funcall callback (wolfram-nb--normalize-result output) nil)
                   (funcall callback nil output))))))))
    (setq wolfram-nb--async-process proc)
    (run-at-time wolfram-nb-eval-timeout nil
                 (lambda ()
                   (when (and (processp proc) (process-live-p proc))
                     (kill-process proc)
                     (message "Evaluation timed out after %ds"
                              wolfram-nb-eval-timeout))))))

(defun wolfram-nb--eval-detailed-async (code format callback)
  "Evaluate CODE in the background and call CALLBACK with (RESULT ERROR).
RESULT is a plist as returned by `wolfram-nb--eval-detailed'."
  (wolfram-nb--refresh-session)
  (cond
   ((wolfram-nb--session-active-p)
    (wolfram-nb--eval-via-session-async
     (if format (format "ExportString[(%s), %S]" code format) code)
     (lambda (result error-msg)
       (funcall callback
                (and (not error-msg) (wolfram-nb--normalize-result result))
                error-msg))))
   ((and wolfram-nb-use-kernel (wolfram-nb--kernel t))
    (condition-case err
        (wolfram-nb-kernel-eval
         (wolfram-nb--kernel t) (wolfram-nb--kernel-code code format)
         (lambda (result)
           (condition-case eval-err
               (funcall callback (wolfram-nb--check-status result)
                        (plist-get result :error))
             (wolfram-nb-eval-error
              (funcall callback nil (cadr eval-err)))))
         :timeout wolfram-nb-eval-timeout
         :flags (wolfram-nb--kernel-flags format))
      (wolfram-nb-kernel-error
       (funcall callback nil (cadr err)))))
   (t
    (wolfram-nb--eval-one-shot-async code format callback))))

(defun wolfram-nb--eval-expression-smart (expr &optional format)
  "Evaluate EXPR with the session, kernel or wolframscript, return a string.
With FORMAT \"PNG\" the string holds the PNG bytes when the evaluation
produced an image."
  (let ((result (wolfram-nb--eval-detailed expr format)))
    (or (plist-get result :png)
        (wolfram-nb--result-text result))))

(defun wolfram-nb--format-output (output)
  "Format evaluation OUTPUT for display in Org."
  (if (string-match-p "\\`\\(Graphics\\|Graphics3D\\|Image\\)" output)
      (concat output "\n; Graphics output — view in Mathematica")
    output))

;;;; Evaluation — writing results into the buffer

(defun wolfram-nb--output-block-end ()
  "If an evaluation output block starts at point, return the position after it.
An output block is an example block or a generated Output placeholder."
  (save-excursion
    (cond
     ((looking-at "[ \t]*#\\+begin_example")
      (when (re-search-forward "^[ \t]*#\\+end_example[ \t]*\n?" nil t)
        (point)))
     ((looking-at "[ \t]*#\\+ATTR_WOLFRAM:.*:style \"Output\".*:id \"")
      (forward-line 1)
      (when (looking-at "[ \t]*#\\+begin_src wolfram-raw")
        (when (re-search-forward "^[ \t]*#\\+end_src[ \t]*\n?" nil t)
          (point)))))))

(defun wolfram-nb--delete-following-output ()
  "Delete the output block that follows point, and the blank lines after it."
  (let ((start (point)))
    (skip-chars-forward " \t\n")
    (goto-char (line-beginning-position))
    (let ((end (wolfram-nb--output-block-end)))
      (if end
          (progn
            (goto-char end)
            (skip-chars-forward " \t\n")
            (delete-region start (point))
            (goto-char start))
        (goto-char start)))))

(defun wolfram-nb--prepare-insertion ()
  "Make point a line start preceded by a blank line, ready for output text."
  (unless (bolp) (insert "\n"))
  (unless (or (bobp) (save-excursion (forward-line -1) (looking-at "[ \t]*$")))
    (insert "\n")))

(defun wolfram-nb--prune-overlays ()
  "Forget overlays that were deleted with their text."
  (setq wolfram-nb--overlays
        (cl-remove-if-not #'overlay-buffer wolfram-nb--overlays)))

(defun wolfram-nb--insert-example (text)
  "Insert TEXT as an example block at point and return its (START . END)."
  (wolfram-nb--prepare-insertion)
  (let ((start (point)))
    (insert "#+begin_example\n" (org-escape-code-in-string text)
            "\n#+end_example\n\n")
    (cons start (point))))

(defun wolfram-nb--insert-graphics-output (boxes png)
  "Insert a kept-verbatim Output cell for BOXES previewed by PNG.
Returns the (START . END) region of the inserted block."
  (let* ((content (format "BoxData[%s]" boxes))
         (id (wolfram-nb--stash-cell-content content)))
    (unless wolfram-nb--png-cache
      (setq wolfram-nb--png-cache (make-hash-table :test 'equal)))
    (puthash id png wolfram-nb--png-cache)
    (wolfram-nb--prepare-insertion)
    (let ((start (point)))
      (insert (wolfram-nb--placeholder-block
               id "Output" nil
               (format "<Graphics output (%s) - kept verbatim and preserved on save.>"
                       (wolfram-nb--format-size (length content)))))
      (let ((ov (wolfram-nb--make-fold-overlay start (point) id)))
        (wolfram-nb--set-overlay-image ov png))
      (cons start (point)))))

(defun wolfram-nb--apply-eval-result (position result code)
  "Replace the output after POSITION by the evaluation RESULT of CODE.
POSITION is where the evaluated source block ends.  Return non-nil."
  (save-excursion
    (let ((inhibit-read-only t)
          (png (plist-get result :png))
          (boxes (plist-get result :boxes))
          (text (wolfram-nb--result-text result)))
      (goto-char position)
      (wolfram-nb--delete-following-output)
      (wolfram-nb--prune-overlays)
      (cond
       ((and png boxes)
        (let ((printed (string-join
                        (cl-remove-if #'string-empty-p
                                      (mapcar (lambda (key)
                                                (string-trim (or (plist-get result key) "")))
                                              '(:stdout :messages)))
                        "\n")))
          (unless (string-empty-p printed)
            (wolfram-nb--insert-example printed)))
        (wolfram-nb--insert-graphics-output boxes png))
       (png
        (let ((region (wolfram-nb--insert-example
                       (if (image-type-available-p 'png)
                           "<binary PNG data>"
                         (format "<PNG image, %d bytes, saved to %s>"
                                 (length png) (wolfram-nb--save-png png))))))
          (wolfram-nb--render-evaluation-output
           (car region) (cdr region) png code)))
       ((not (string-empty-p text))
        (let ((region (wolfram-nb--insert-example
                       (wolfram-nb--format-output text))))
          (wolfram-nb--render-evaluation-output
           (car region) (cdr region) text code))))
      t)))

;;;; Evaluation — commands

(defun wolfram-nb--block-at-point ()
  "Return (CODE FORMAT END) for the wolfram source block at point."
  (let* ((element (org-element-at-point))
         (type (org-element-type element)))
    (unless (eq type 'src-block)
      (user-error "Not inside a source block"))
    (unless (string= (org-element-property :language element) "wolfram")
      (user-error "Not a wolfram source block"))
    (let ((params (org-element-property :parameters element)))
      (list (org-unescape-code-in-string (org-element-property :value element))
            (when (and params
                       (string-match ":format[ \t\n]+\\([^ \t\n]+\\)" params))
              (match-string 1 params))
            (org-element-property :end element)))))

(defun wolfram-nb-eval-block ()
  "Evaluate the Wolfram source block at point and insert output below.
Uses the HTTP session if one is configured, else this buffer's persistent
kernel, else a fresh wolframscript.  Return non-nil on success."
  (interactive)
  (pcase-let ((`(,code ,format ,end) (wolfram-nb--block-at-point)))
    (message "Evaluating...")
    (condition-case err
        (let ((result (wolfram-nb--eval-detailed code format)))
          (wolfram-nb--apply-eval-result end result code)
          (message "Done.")
          t)
      (wolfram-nb-eval-error
       (message "Eval error: %s" (cadr err))
       nil))))

(defun wolfram-nb-eval-buffer ()
  "Evaluate all Wolfram source blocks of the buffer, top to bottom.
Definitions carry over from one block to the next."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0) (errors 0))
      (while (re-search-forward "^[ \t]*#\\+begin_src[ \t]+wolfram\\([ \t\n]\\|$\\)" nil t)
        (beginning-of-line)
        (if (wolfram-nb-eval-block)
            (setq count (1+ count))
          (setq errors (1+ errors)))
        (when (re-search-forward "^[ \t]*#\\+end_src" nil t)
          (forward-line 1)))
      (message "Evaluated %d blocks (%d errors)" count errors))))

;;;; Evaluation — asynchronous

(defun wolfram-nb-eval-block-async ()
  "Evaluate the Wolfram source block at point without blocking Emacs."
  (interactive)
  (pcase-let ((`(,code ,format ,end) (wolfram-nb--block-at-point)))
    (let ((end-marker (copy-marker end))
          (buf (current-buffer)))
      (message "Evaluating (async)...")
      (wolfram-nb--eval-detailed-async
       code format
       (lambda (result error-msg)
         (when (buffer-live-p buf)
           (with-current-buffer buf
             (if error-msg
                 (message "Async eval error: %s" error-msg)
               (wolfram-nb--apply-eval-result end-marker result code)
               (message "Async eval complete."))))
         (set-marker end-marker nil))))))

;;;; org-babel integration

(declare-function wolfram-nb--eval-expression-smart "wolfram-nb-mode")

(defun org-babel-execute:wolfram (body _params)
  "Execute Wolfram Language BODY.
Uses session if active, otherwise wolframscript.
_PARAMS is the org-babel parameter alist (currently unused)."
  (wolfram-nb--eval-expression-smart body))

(defun wolfram-nb-clear-outputs ()
  "Remove all evaluation outputs from the buffer.
That covers example blocks and the Output cells kept verbatim as graphics."
  (interactive)
  (save-excursion
    (goto-char (point-min))
    (let ((count 0)
          (inhibit-read-only t))
      (while (re-search-forward
              "^[ \t]*\\(#\\+begin_example\\|#\\+ATTR_WOLFRAM:.*:style \"Output\".*:id \"\\)"
              nil t)
        (goto-char (match-beginning 0))
        (let ((end (wolfram-nb--output-block-end)))
          (if end
              (progn (delete-region (point) end)
                     (setq count (1+ count)))
            (forward-line 1))))
      (wolfram-nb--prune-overlays)
      (message "Cleared %d output blocks" count))))

;;;; Imenu integration

(defun wolfram-nb--imenu-create-index ()
  "Create an Imenu index for the current wolfram-nb buffer.
Groups entries by cell type."
  (let ((index '())
        (heading-re "^\\(\\*+\\) \\(.+\\)$")
        (src-re "^#\\+begin_src \\(wolfram-raw\\|wolfram\\)\\([ \t]\\|$\\)"))
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
          (let* ((block-type (match-string 1))
                 (label
                  (if (string= block-type "wolfram-raw")
                      ;; Try to extract style from previous ATTR_WOLFRAM
                      (save-excursion
                        (goto-char (match-beginning 0))
                        (forward-line -1)
                        (let ((line (buffer-substring-no-properties (line-beginning-position) (line-end-position))))
                          (if (string-match ":style[ \t\n]*\"\\([^\"]*\\)\"" line)
                              (format "Raw block [%s] #%d" (match-string 1 line) n)
                            (format "Raw block #%d" n))))
                    (format "Code block #%d" n))))
            (push (cons label (match-beginning 0)) index)))))
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
    (message "Session: %s:%d%s (active)" (nth 0 wolfram-nb--session-endpoint)
             (nth 1 wolfram-nb--session-endpoint)
             (nth 2 wolfram-nb--session-endpoint))
    (if wolfram-nb--session-raw
        (message "Session: %s (invalid)" wolfram-nb--session-raw)
      (cond
       ((and wolfram-nb-use-kernel (wolfram-nb-kernel-available-p))
        (wolfram-nb-kernel-info))
       ((wolfram-nb--check-wolframscript)
        (message "No session. Using wolframscript: %s" wolfram-nb-wolframscript-path))
       (t (message "No session and no wolframscript available."))))))

(defun wolfram-nb-session-ping ()
  "Test connectivity to the session endpoint by evaluating \"$Version\"."
  (interactive)
  (wolfram-nb--refresh-session)
  (if (not (wolfram-nb--session-active-p))
      (message "No active session to ping.")
    (message "Pinging %s:%d%s..." (nth 0 wolfram-nb--session-endpoint)
             (nth 1 wolfram-nb--session-endpoint)
             (nth 2 wolfram-nb--session-endpoint))
    (condition-case err
        (let ((result (wolfram-nb--eval-via-session "$Version")))
          (message "Session alive: %s" result))
      (wolfram-nb-eval-error
       (message "Session ping failed: %s" (cadr err))))))

;;;; Visual Overlays & Inline Previews

(defconst wolfram-nb--fold-label
  " 🖼️  [Raw Graphics Block - Click to Expand / TAB]\n"
  "Text shown in place of a folded raw block.")

(defun wolfram-nb-clear-overlays ()
  "Remove all active visual overlays in the current buffer."
  (interactive)
  (dolist (ov wolfram-nb--overlays)
    (when (overlayp ov)
      (delete-overlay ov)))
  (setq wolfram-nb--overlays nil))

(defun wolfram-nb--display-code (content)
  "Return Wolfram code that evaluates to something displayable from CONTENT.
CONTENT is Wolfram source or the text of a `BoxData[...]' cell."
  (format "With[{e = ToExpression[ByteArrayToString[BaseDecode[\"%s\"], \"UTF-8\"]]}, If[Head[e] === BoxData, ToExpression[e, StandardForm], e]]"
          (base64-encode-string (encode-coding-string content 'utf-8) t)))

(defun wolfram-nb--rasterize-one-shot (content callback)
  "Rasterize CONTENT with a fresh wolframscript; CALLBACK gets (PNG-FILE ERROR)."
  (if (not (wolfram-nb--check-wolframscript))
      (funcall callback nil "wolframscript not found")
    (let* ((temp-content-file (make-temp-file "wolfram-nb-content" nil ".txt"))
           (temp-png-file (make-temp-file "wolfram-nb-img" nil ".png"))
           (buf (current-buffer))
           (code (format "Quiet[Export[%S, Rasterize[ToExpression[Import[%S, \"Text\"]], ImageResolution -> 72], \"PNG\"]]"
                         temp-png-file temp-content-file)))
      ;; The content goes through a file to avoid command-line limits.
      (with-temp-file temp-content-file
        (insert content))
      (make-process
       :name "wolfram-rasterize-async"
       :buffer (generate-new-buffer " *wolfram-rasterize*")
       :command (list wolfram-nb-wolframscript-path "-code" code)
       :sentinel
       (lambda (process _event)
         (when (memq (process-status process) '(exit signal))
           (let ((exit-status (process-exit-status process)))
             (kill-buffer (process-buffer process))
             (when (file-exists-p temp-content-file)
               (delete-file temp-content-file))
             (when (buffer-live-p buf)
               (with-current-buffer buf
                 (if (= exit-status 0)
                     (funcall callback temp-png-file nil)
                   (when (file-exists-p temp-png-file)
                     (delete-file temp-png-file))
                   (funcall callback nil "Rasterization failed")))))))))))

(defun wolfram-nb--render-png-async (content callback)
  "Rasterize CONTENT in the background and call CALLBACK with (PNG ERROR).
PNG is a unibyte string.  The buffer's kernel renders it when there is one."
  (let ((kernel (and wolfram-nb-use-kernel
                     (not (progn (wolfram-nb--refresh-session)
                                 (wolfram-nb--session-active-p)))
                     (wolfram-nb--kernel t)))
        (buf (current-buffer)))
    (if kernel
        (wolfram-nb-kernel-eval
         kernel (wolfram-nb--display-code content)
         (lambda (result)
           (when (buffer-live-p buf)
             (with-current-buffer buf
               (if (plist-get result :png)
                   (funcall callback (plist-get result :png) nil)
                 (funcall callback nil
                          (or (plist-get result :error)
                              "Rasterization failed"))))))
         :timeout 120 :flags "p")
      (wolfram-nb--rasterize-one-shot
       content
       (lambda (png-file err)
         (if err
             (funcall callback nil err)
           (let ((png (with-temp-buffer
                        (set-buffer-multibyte nil)
                        (insert-file-contents-literally png-file)
                        (buffer-string))))
             (delete-file png-file)
             (funcall callback png nil))))))))

(defun wolfram-nb--rasterize-async (content callback)
  "Rasterize CONTENT in the background and call CALLBACK with (PNG-FILE ERROR)."
  (wolfram-nb--render-png-async
   content
   (lambda (png err)
     (if (not png)
         (funcall callback nil err)
       (let ((file (make-temp-file "wolfram-nb-img" nil ".png")))
         (let ((coding-system-for-write 'no-conversion))
           (with-temp-file file
             (set-buffer-multibyte nil)
             (insert png)))
         (funcall callback file nil))))))

(defun wolfram-nb--image-spec (png &optional file)
  "Return an image display spec for the PNG bytes, or for FILE when given.
Return nil when this Emacs cannot display PNG images."
  (when (image-type-available-p 'png)
    (if file
        (create-image file 'png nil :max-width 600)
      (create-image png 'png t :max-width 600))))

(defun wolfram-nb--save-png (png)
  "Write the PNG bytes to a temporary file and return its name."
  (let ((file (make-temp-file "wolfram-nb-img" nil ".png"))
        (coding-system-for-write 'no-conversion))
    (with-temp-file file
      (set-buffer-multibyte nil)
      (insert png))
    file))

(defun wolfram-nb--make-fold-overlay (start end &optional id)
  "Create the foldable overlay for a raw block from START to END.
ID is the placeholder id of a block whose content is kept in the cache."
  (let ((ov (make-overlay start end))
        (map (make-sparse-keymap)))
    (overlay-put ov 'wolfram-nb-fold t)
    (overlay-put ov 'wolfram-nb-id id)
    (overlay-put ov 'folded wolfram-nb-fold-raw-blocks)
    (when wolfram-nb-fold-raw-blocks
      (overlay-put ov 'display wolfram-nb--fold-label))
    (overlay-put ov 'evaporate t)
    (overlay-put ov 'face 'highlight)
    (define-key map [mouse-1] #'wolfram-nb-toggle-block-at-point)
    (define-key map (kbd "RET") #'wolfram-nb-toggle-block-at-point)
    (define-key map (kbd "TAB") #'wolfram-nb-toggle-block-at-point)
    (overlay-put ov 'keymap map)
    (push ov wolfram-nb--overlays)
    ov))

(defun wolfram-nb--set-overlay-image (ov png)
  "Show the PNG bytes in the folded overlay OV."
  (let ((spec (wolfram-nb--image-spec png)))
    (when spec
      (overlay-put ov 'folded-display spec)
      (when (overlay-get ov 'folded)
        (overlay-put ov 'display spec)))))

(defun wolfram-nb-toggle-block-at-point ()
  "Toggle the folded/expanded state of the block overlay at point."
  (interactive)
  (let ((ovs (overlays-at (point)))
        (found nil))
    (dolist (ov ovs)
      (when (overlay-get ov 'wolfram-nb-fold)
        (setq found t)
        (let ((folded (overlay-get ov 'folded))
              (preview-ov (overlay-get ov 'preview-overlay)))
          (if folded
              ;; Expand
              (progn
                (overlay-put ov 'folded nil)
                (overlay-put ov 'display nil)
                (when preview-ov
                  (overlay-put preview-ov 'invisible nil)))
            ;; Collapse
            (progn
              (overlay-put ov 'folded t)
              (overlay-put ov 'display (or (overlay-get ov 'folded-display)
                                           wolfram-nb--fold-label))
              (when preview-ov
                (overlay-put preview-ov 'invisible t)))))))
    (unless found
      (message "No block overlay at point"))))

(defun wolfram-nb--placeholder-id-at (block-start)
  "Return (ID . ATTR-START) of the placeholder attribute above BLOCK-START."
  (save-excursion
    (goto-char block-start)
    (when (and (zerop (forward-line -1))
               (looking-at "#\\+ATTR_WOLFRAM:.*:id \"\\([^\"]+\\)\""))
      (cons (match-string-no-properties 1) (line-beginning-position)))))

(defun wolfram-nb--overlay-cached-block (id start end)
  "Overlay the placeholder block START..END of cached cell ID with a preview."
  (let* ((ov (wolfram-nb--make-fold-overlay start end id))
         (content (and wolfram-nb--large-cells-cache
                       (gethash id wolfram-nb--large-cells-cache)))
         (png (and wolfram-nb--png-cache (gethash id wolfram-nb--png-cache)))
         (buf (current-buffer)))
    (cond
     (png (wolfram-nb--set-overlay-image ov png))
     ((and wolfram-nb-rasterize-graphics content
           (wolfram-nb--box-cell-p content))
      (wolfram-nb--render-png-async
       content
       (lambda (data err)
         (cond
          (err (message "Rasterization warning: %s" err))
          ((buffer-live-p buf)
           (with-current-buffer buf
             (unless wolfram-nb--png-cache
               (setq wolfram-nb--png-cache (make-hash-table :test 'equal)))
             (puthash id data wolfram-nb--png-cache)
             (when (overlay-buffer ov)
               (wolfram-nb--set-overlay-image ov data)))))))))
    ov))

(defun wolfram-nb-apply-buffer-overlays ()
  "Scan the buffer for raw/unrecognized blocks and apply overlays."
  (interactive)
  (wolfram-nb-clear-overlays)
  (save-excursion
    (goto-char (point-min))
    (while (re-search-forward "^#\\+begin_src wolfram-raw\n" nil t)
      (let* ((block-start (match-beginning 0))
             (content-start (match-end 0))
             (placeholder (wolfram-nb--placeholder-id-at block-start)))
        (when (re-search-forward "^#\\+end_src\n?" nil t)
          (let* ((block-end (point))
                 (content-end (match-beginning 0))
                 (content (buffer-substring-no-properties content-start content-end)))
            (if placeholder
                (wolfram-nb--overlay-cached-block
                 (car placeholder) (cdr placeholder) block-end)
              (let ((fold-ov (wolfram-nb--make-fold-overlay block-start block-end)))
                ;; If it contains graphical constructs, rasterize it in the background.
                (when (and wolfram-nb-rasterize-graphics
                           (string-match-p "BoxData\\|Graphics\\|Raster\\|Image\\|DynamicModule" content))
                  (let ((preview-ov (make-overlay (1- block-end) block-end)))
                    (overlay-put preview-ov 'wolfram-nb-preview t)
                    (when wolfram-nb-fold-raw-blocks
                      (overlay-put preview-ov 'invisible t))
                    (overlay-put preview-ov 'evaporate t)
                    (overlay-put fold-ov 'preview-overlay preview-ov)
                    (push preview-ov wolfram-nb--overlays)
                    (wolfram-nb--rasterize-async
                     content
                     (lambda (png-path err)
                       (if err
                           (message "Rasterization warning: %s" err)
                         (when (and (file-exists-p png-path)
                                    (overlay-buffer preview-ov))
                           (overlay-put preview-ov 'display
                                        (list (wolfram-nb--image-spec nil png-path)
                                              "\n")))))))))))))))
  (length wolfram-nb--overlays))

(defun wolfram-nb--render-evaluation-output (start end result &optional original-expr)
  "Render evaluation RESULT inline as an overlay from START to END if graphical.
RESULT is PNG bytes or the printed result; ORIGINAL-EXPR is the evaluated code."
  (if (wolfram-nb--png-p result)
      (let ((result-ov (make-overlay start end))
            (spec (wolfram-nb--image-spec result)))
        (overlay-put result-ov 'wolfram-nb-result t)
        (overlay-put result-ov 'evaporate t)
        (push result-ov wolfram-nb--overlays)
        (when spec
          (overlay-put result-ov 'display spec)
          (wolfram-nb--make-toggle-keymap result-ov spec)))
    (let ((is-graphics (string-match-p "\\`\\(Graphics\\|Graphics3D\\|Image\\|Show\\|Plot\\|ContourPlot\\|DensityPlot\\|BarChart\\|PieChart\\)\\s-*\\[" (string-trim result)))
          (is-label (string-match-p "\\`-\\(Graphics\\|Graphics3D\\|Image\\)-" (string-trim result))))
      (when (and wolfram-nb-rasterize-graphics
                 (or is-graphics (and is-label original-expr)))
        (let ((result-ov (make-overlay start end))
              (source (if (and is-label original-expr) original-expr result)))
          (overlay-put result-ov 'wolfram-nb-result t)
          (overlay-put result-ov 'evaporate t)
          (push result-ov wolfram-nb--overlays)
          (wolfram-nb--render-png-async
           source
           (lambda (png err)
             (if err
                 (message "Evaluation rasterization warning: %s" err)
               (let ((spec (and (overlay-buffer result-ov)
                                (wolfram-nb--image-spec png))))
                 (when spec
                   (overlay-put result-ov 'display spec)
                   (wolfram-nb--make-toggle-keymap result-ov spec)))))))))))

(defun wolfram-nb--make-toggle-keymap (ov spec)
  "Let a click on overlay OV switch between the image SPEC and the raw text."
  (let ((map (make-sparse-keymap)))
    (define-key map [mouse-1]
      (lambda ()
        (interactive)
        (overlay-put ov 'display (if (overlay-get ov 'display) nil spec))))
    (overlay-put ov 'keymap map)))

(defun wolfram-nb-toggle-overlays ()
  "Toggle the visual overlays on/off in the current buffer."
  (interactive)
  (if wolfram-nb--overlays
      (progn
        (wolfram-nb-clear-overlays)
        (message "Visual overlays cleared."))
    (wolfram-nb-apply-buffer-overlays)
    (message "Visual overlays applied.")))

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
    (define-key map (kbd "C-c C-o") #'wolfram-nb-toggle-overlays)
    (define-key map (kbd "C-c C-z") #'wolfram-nb-kernel-restart)
    (define-key map (kbd "C-c C-q") #'wolfram-nb-kernel-quit)
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
(add-to-list 'auto-mode-alist '("\\.nb\\'" . wolfram-nb-mode))

(defun wolfram-nb--auto-open ()
  "Automatically parse .nb files when opened in wolfram-nb-mode."
  (when (and wolfram-nb-auto-open
             wolfram-nb--original-file
             (not (buffer-modified-p))
             (= (point-min) (point-max)))
    (let* ((file wolfram-nb--original-file)
           (cells (wolfram-nb--parse-notebook file))
           (inhibit-read-only t))
      (erase-buffer)
      (insert (wolfram-nb--cells-to-org cells))
      (goto-char (point-min))
      (set-buffer-modified-p nil)
      (setq wolfram-nb--cells cells
            wolfram-nb--cell-count (length cells))
      (wolfram-nb--refresh-session)
      (wolfram-nb-apply-buffer-overlays)
      (message "Opened %s (%d cells)%s"
               (file-name-nondirectory file) wolfram-nb--cell-count
               (if wolfram-nb--session-raw
                   (format " [session: %s]" wolfram-nb--session-raw)
                 "")))))

(add-hook 'wolfram-nb-mode-hook #'wolfram-nb--auto-open)

(provide 'wolfram-nb-mode)
;;; wolfram-nb-mode.el ends here
